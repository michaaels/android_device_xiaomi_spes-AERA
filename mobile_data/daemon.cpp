/* SPDX-License-Identifier: Apache-2.0 */
// AERA cellular provider for spes / spesn.
// Based on AERA-Recovery/android_device_oneplus_infiniti-AERA mobile_data/daemon.cpp
// (aera-16.0, f7fca594), which shares the integrated-modem IPA data path. The
// QMI, SIM, registration, data-session, rmnet and DNS handling are unchanged.
// spes-specific: the modem is brought up by the device Wi-Fi stack
// (spes_platform.hpp) instead of remoteproc plus private RAM storage helpers, and
// it stays shared with Wi-Fi when mobile data stops. Recovery detection does
// not rely on ro.bootmode, which spes leaves unset (recovery lives in boot),
// the QMAP data format comes from spes::kDataFormat (QMAP v1, no QMAPv5), and
// the IPA pipe formats are set once per boot (rmnet_ipa3 rejects a second set).
// The operator name is decoded by plmn_name.hpp (ASCII or GSM 7-bit packed).
// DMS Set Operating Mode is retried while a freshly booted modem is not ready.
// Dual SIM: empty provisioning sessions are filled and the default data
// subscription follows the selected SIM (sim_session.hpp).
#include "aera_mobile/client.hpp"
#include "qmi.hpp"
#include "sim.hpp"
#include "sim_session.hpp"
#include "spes_platform.hpp"
#include "plmn_name.hpp"
#include <openssl/sha.h>
#include <arpa/inet.h>
#include <dirent.h>
#include <linux/if_link.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/wait.h>
#include <cutils/properties.h>
#include <json/json.h>
#include <array>
#include <condition_variable>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <thread>
#include <csignal>

namespace aera::mobile {
namespace {
constexpr const char *kDirectory="/tmp/aera-cellular";
constexpr const char *kInterface="rmnet_aera";
constexpr uint16_t kQmiDeviceNotReady=52;
std::atomic<bool> cancel{false}, exiting{false}, working{false};
std::mutex state_mutex, completion_mutex;
std::condition_variable completion;
Json::Value status(Json::objectValue);
std::string pending_pin,pending_pin_request;
uint64_t pin_request_sequence=0;
void ClearPin(std::string &pin) {
  volatile char *data=pin.data();for(size_t i=0;i<pin.size();++i)data[i]=0;
  pin.clear();
}
std::string SimIdentity(const Bytes &iccid) {
  unsigned char digest[SHA256_DIGEST_LENGTH];
  SHA256(iccid.data(),iccid.size(),digest);
  const char *hex="0123456789abcdef";std::string out;
  for(unsigned char c:digest){out+=hex[c>>4];out+=hex[c&15];}
  return out;
}

std::string Read(const std::string &path,size_t maximum=16384) {
  Fd fd(open(path.c_str(),O_RDONLY|O_CLOEXEC));
  if(fd.get()<0)return {};
  std::string result;char buffer[1024];
  while(result.size()<maximum) {
    ssize_t n=read(fd.get(),buffer,std::min(sizeof(buffer),maximum-result.size()));
    if(n<0&&errno==EINTR)continue;
    if(n<=0)break;
    result.append(buffer,n);
  }
  while(!result.empty()&&(result.back()=='\n'||result.back()=='\r'))result.pop_back();
  return result;
}
bool Write(const std::string &path,const std::string &value,int flags=O_WRONLY,mode_t mode=0600) {
  Fd fd(open(path.c_str(),flags|O_CLOEXEC|O_NOFOLLOW,mode));
  if(fd.get()<0)return false;
  if((flags&O_CREAT)&&fchmod(fd.get(),mode))return false;
  size_t off=0;
  while(off<value.size()) {
    ssize_t n=write(fd.get(),value.data()+off,value.size()-off);
    if(n<0&&errno==EINTR)continue;
    if(n<=0)return false;
    off+=n;
  }
  return true;
}
void SaveLocked() {
  status["boot_id"]=Read("/proc/sys/kernel/random/boot_id");
  status["pid"]=getpid();status["version"]=1;
  Json::StreamWriterBuilder builder;builder["indentation"]="";
  if(Write(std::string(kStatus)+".new",Json::writeString(builder,status),O_WRONLY|O_CREAT|O_TRUNC))
    rename((std::string(kStatus)+".new").c_str(),kStatus);
}
void Phase(const std::string &state,const std::string &message) {
  std::lock_guard<std::mutex> lock(state_mutex);
  status["state"]=state;status["message"]=message;SaveLocked();
  fprintf(stderr,"mobile: %s: %s\n",state.c_str(),message.c_str());
}
void ClearConnectionLocked() {
  status["connected"]=false;status["registered"]=false;status["signal_valid"]=false;
  status["bars"]=-1;status["signal_dbm"]=0;
  for(const char *key:{"address","gateway","interface","operator","technology","dns1","dns2","effective_apn"})
    status[key]="";
  status.removeMember("mtu");
}
void CheckCancelled() { if(cancel.load())throw std::runtime_error("Connection cancelled"); }
void Delay(unsigned milliseconds) {
  for(unsigned elapsed=0;elapsed<milliseconds;elapsed+=50) {
    CheckCancelled();std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
}
std::string Capability() { return spes::Capability(); }
int Run(const std::vector<std::string> &args) {
  if(args.empty())return -1;
  pid_t pid=fork();if(pid<0)return -1;
  if(pid==0) {
    std::vector<char *> argv;for(const auto &arg:args)argv.push_back(const_cast<char *>(arg.c_str()));
    argv.push_back(nullptr);execv(argv[0],argv.data());_exit(127);
  }
  int result=0;while(waitpid(pid,&result,0)<0)if(errno!=EINTR)return -1;
  return WIFEXITED(result)?WEXITSTATUS(result):-1;
}
void Ip(std::initializer_list<std::string> args,bool required=true) {
  std::vector<std::string> command{"/sbin/busybox","ip"};command.insert(command.end(),args);
  if(Run(command)&&required)throw std::runtime_error("Network interface configuration failed");
}
using IpaData=std::array<uint32_t,6>;
IpaData Ipa(IpaData data) {
  Fd fd(socket(AF_INET,SOCK_DGRAM|SOCK_CLOEXEC,0));
  ifreq request{};strcpy(request.ifr_name,"rmnet_ipa0");
  request.ifr_data=reinterpret_cast<char *>(data.data());
  if(fd.get()<0||ioctl(fd.get(),0x89fd,&request))
    throw std::runtime_error("The kernel IPA data interface is unsupported (command "+
        std::to_string(data[0])+", errno "+std::to_string(errno)+")");
  return data;
}
Bytes Attribute(uint16_t type,const Bytes &value) {
  Bytes b;Put16(b,value.size()+4);Put16(b,type);b.insert(b.end(),value.begin(),value.end());
  b.resize((b.size()+3)&~size_t(3));return b;
}
void Append(Bytes &a,const Bytes &b){a.insert(a.end(),b.begin(),b.end());}
Bytes StringBytes(const std::string &s){Bytes b(s.begin(),s.end());b.push_back(0);return b;}
void CreateLink() {
  unsigned parent=if_nametoindex("rmnet_ipa0");
  if(!parent||if_nametoindex(kInterface))throw std::runtime_error("Mobile network interface is already in use");
  Fd fd(socket(AF_NETLINK,SOCK_RAW|SOCK_CLOEXEC,NETLINK_ROUTE));
  if(fd.get()<0)throw std::runtime_error("Cannot open route control");
  sockaddr_nl addr{};addr.nl_family=AF_NETLINK;
  if(bind(fd.get(),reinterpret_cast<sockaddr *>(&addr),sizeof(addr)))throw std::runtime_error("Cannot bind route control");
  Bytes data=Attribute(1,Bytes{1,0});Append(data,Attribute(2,Words({spes::kDataFormat.rmnet_flags,0xffffffff})));
  Bytes info=Attribute(1,StringBytes("rmnet"));Append(info,Attribute(2|NLA_F_NESTED,data));
  Bytes attrs=Attribute(IFLA_LINK,Words({parent}));Append(attrs,Attribute(IFLA_IFNAME,StringBytes(kInterface)));
  Append(attrs,Attribute(IFLA_LINKINFO|NLA_F_NESTED,info));
  nlmsghdr header{};header.nlmsg_len=sizeof(header)+sizeof(ifinfomsg)+attrs.size();
  header.nlmsg_type=RTM_NEWLINK;header.nlmsg_flags=NLM_F_REQUEST|NLM_F_ACK|NLM_F_CREATE|NLM_F_EXCL;header.nlmsg_seq=1;
  Bytes packet(header.nlmsg_len);memcpy(packet.data(),&header,sizeof(header));
  memcpy(packet.data()+sizeof(header)+sizeof(ifinfomsg),attrs.data(),attrs.size());
  if(sendto(fd.get(),packet.data(),packet.size(),0,reinterpret_cast<sockaddr *>(&addr),sizeof(addr))<0)
    throw std::runtime_error("Cannot create mobile network interface");
  pollfd p{fd.get(),POLLIN,0};uint8_t buffer[4096];
  if(poll(&p,1,3000)<=0)throw std::runtime_error("Route control timed out");
  ssize_t n=recv(fd.get(),buffer,sizeof(buffer),0);
  if(n<static_cast<ssize_t>(NLMSG_LENGTH(sizeof(nlmsgerr))))throw std::runtime_error("Invalid route response");
  auto *reply=reinterpret_cast<nlmsghdr *>(buffer);
  auto *error=reinterpret_cast<nlmsgerr *>(NLMSG_DATA(reply));
  if(reply->nlmsg_type!=NLMSG_ERROR||reply->nlmsg_seq!=1||error->error)
    throw std::runtime_error("The kernel rejected the rmnet link");
}
std::string Address(const Values &v,uint8_t tag) {
  const auto &b=Field(v,tag);if(b.size()!=4)return {};
  in_addr address{htonl(U32(b.data()))};char text[INET_ADDRSTRLEN];
  return inet_ntop(AF_INET,&address,text,sizeof(text))?text:"";
}
int Prefix(const std::string &netmask) {
  in_addr a{};if(inet_pton(AF_INET,netmask.c_str(),&a)!=1)throw std::runtime_error("Missing IPv4 netmask");
  uint32_t mask=ntohl(a.s_addr);int prefix=0;
  while(mask&0x80000000){++prefix;mask<<=1;}
  if(mask)throw std::runtime_error("Invalid IPv4 netmask");return prefix;
}
bool WifiConnected() {
  if(Read("/sys/class/net/wlan0/carrier")!="1")return false;
  Fd fd(socket(AF_INET,SOCK_DGRAM|SOCK_CLOEXEC,0));
  ifreq request{};strcpy(request.ifr_name,"wlan0");
  if(fd.get()<0||ioctl(fd.get(),SIOCGIFADDR,&request)||
      !reinterpret_cast<sockaddr_in *>(&request.ifr_addr)->sin_addr.s_addr)return false;
  std::istringstream routes(Read("/proc/net/route"));std::string line;
  while(std::getline(routes,line)) {
    std::istringstream fields(line);std::string iface,destination,gateway;unsigned flags=0;
    if(fields>>iface>>destination>>gateway>>std::hex>>flags)
      if(iface=="wlan0"&&destination=="00000000"&&(flags&1))return true;
  }
  return false;
}

struct Session {
  Fd lease;
  std::unique_ptr<QmiClient> dpm,wda,wds,nas;
  std::string old_resolv,own_resolv,dns1,dns2;
  std::array<std::string,2> old_dns;
  bool link_owned=false,dns_owned=false;
  bool old_resolv_exists=false;
  bool established=false;
  std::thread network_worker;
  std::atomic<bool> network_stop{false};
  std::mutex network_mutex;
  std::string network_error;
  uint32_t handle=0;
  std::map<unsigned,std::string> SimIdentities(QmiClient &uim) {
    std::map<unsigned,std::string> out;
    for(const auto &entry:ParseSimIdentifiers(Field(uim.Call(0x47,{},5,&cancel),0x10)))
      out[entry.first]=SimIdentity(entry.second);
    return out;
  }
  // The primary session is needed for any registration, the secondary one for
  // subscription 2 (sim_session.hpp). Sessions already in use are kept.
  void ProvisionSims(QmiClient &uim,int subscription) {
    auto sessions=ParseSimSessions(Field(uim.Call(0x2f,{},5,&cancel),0x10));
    for(const uint8_t session:{kPrimaryGwSession,kSecondaryGwSession}) {
      if(session==kSecondaryGwSession&&subscription!=2)break;
      if((session==kPrimaryGwSession?sessions.primary:sessions.secondary)!=kNoSession)continue;
      // No usable slot: WaitForSim reports the selected SIM as missing.
      const unsigned slot=SlotForSession(sessions,session);
      if(!slot)continue;
      uim.Call(0x38,ProvisionRequest(session,*GwApplication(sessions,slot)),10,&cancel);
      sessions=ParseSimSessions(Field(uim.Call(0x2f,{},5,&cancel),0x10));
    }
  }
  // Data comes up on the modem's default data subscription whatever WDS is
  // bound to (sim_session.hpp). Modems without DSD have a single subscription.
  void SelectDataSubscription(const std::vector<Endpoint> &endpoints,uint32_t node,int subscription) {
    Endpoint dsd;
    try{dsd=Find(endpoints,42,node);}catch(const std::exception &){return;}
    Bytes request;Tlv(request,1,Words({static_cast<uint32_t>(subscription)}));
    QmiClient client(dsd);
    try {
      client.Call(0x4e,request,10,&cancel);
      // The switch completes asynchronously, and a call started before it does
      // comes up on the previous SIM (observed on spes): wait for Get Current DDS.
      for(int attempt=0;attempt<40;++attempt) {
        const auto reply=client.Call(0x4f,{},5,&cancel);const auto &current=Field(reply,0x10);
        if(current.size()==4&&U32(current.data())==static_cast<uint32_t>(subscription))return;
        CheckModem();Delay(250);
      }
    }catch(const QmiError &){}
    throw std::runtime_error("The modem did not move mobile data to the selected SIM");
  }
  void WaitForSim(const Endpoint &endpoint,int subscription) {
    QmiClient uim(endpoint);
    std::map<unsigned,std::string> identities;
    try {
      identities=SimIdentities(uim);
    }catch(const std::exception &){CheckCancelled();}
    ProvisionSims(uim,subscription);
    unsigned initializing=0,polls=0;
    const std::string request=std::to_string(getpid())+"-"+std::to_string(++pin_request_sequence);
    while(true) {
      CheckCancelled();CheckModem();
      if(++polls%10==0) {
        try{identities=SimIdentities(uim);}catch(const std::exception &){CheckCancelled();}
      }
      const auto cards=ParseSimCards(Field(uim.Call(0x2f,{},5,&cancel),0x10));
      const uint16_t index=subscription==2?cards.secondary:cards.primary;
      const SimCard *selected=nullptr;
      Json::Value sims(Json::arrayValue);
      for(const auto &card:cards.cards) {
        Json::Value sim;sim["slot"]=card.slot;sim["id"]=identities[card.slot];
        sim["state"]=SimState(card);sim["retries"]=card.retries;sims.append(sim);
        if(card.slot==unsigned((index>>8)+1)&&card.application==unsigned(index&255))selected=&card;
      }
      if(!selected) {
        {
          std::lock_guard<std::mutex> lock(state_mutex);status["sims"]=sims;
          status["sim_state"]="initializing";status["state"]="initializing";
          status["message"]="Preparing SIM";SaveLocked();
        }
        if(++initializing>60)throw std::runtime_error("The selected data SIM has no provisioning application");
        Delay(500);continue;
      }
      if(selected->slot>2)throw std::runtime_error("Unsupported SIM slot");
      const auto state=SimState(*selected);
      const std::string identity=identities[selected->slot];
      {
        std::lock_guard<std::mutex> lock(state_mutex);
        status["sims"]=sims;status["sim_slot"]=selected->slot;status["sim_id"]=identity;
        status["pin_retries"]=selected->retries;status["pin_request"]=request;
        status["sim_state"]=state;
        if(state!="ready") {
          status["state"]=pending_pin.empty()?state:"verifying_pin";status["message"]=state=="pin_required"?"SIM PIN required":
            state=="puk_required"?"SIM requires PUK. Unlock it in Android":
            state=="blocked"?"SIM is blocked":state=="absent"?"Selected SIM is not present":"Preparing SIM";
        }
        SaveLocked();
      }
      if(state=="ready")return;
      if(state=="absent")throw std::runtime_error("Selected SIM is not present");
      if(state=="initializing"&&++initializing>60)throw std::runtime_error("SIM initialization timed out");
      std::string pin;
      {
        std::lock_guard<std::mutex> lock(state_mutex);
        if(pending_pin_request==request)pin.swap(pending_pin);
        pending_pin_request.clear();
      }
      if(!pin.empty()) {
        if(state!="pin_required") {ClearPin(pin);continue;}
        Bytes payload,info{static_cast<uint8_t>(selected->universal?3:1),static_cast<uint8_t>(pin.size())};
        info.insert(info.end(),pin.begin(),pin.end());ClearPin(pin);
        Tlv(payload,1,{static_cast<uint8_t>(selected->slot==1?6:7),0});Tlv(payload,2,info);
        std::fill(info.begin(),info.end(),0);
        Phase("verifying_pin","Verifying SIM PIN");
        std::string outcome="success";
        try {
          if(!identity.empty()&&SimIdentities(uim)[selected->slot]!=identity)
            throw std::runtime_error("SIM changed before PIN verification");
          uim.Call(0x26,payload,10,&cancel);
        }
        catch(const QmiError &){outcome="failed";}
        catch(const std::exception &){outcome="unknown";}
        std::fill(payload.begin(),payload.end(),0);
        {
          std::lock_guard<std::mutex> lock(state_mutex);
          status["pin_result"]["request"]=request;status["pin_result"]["id"]=identity;
          status["pin_result"]["outcome"]=outcome;SaveLocked();
        }
        // Even on a transport timeout, only query status; never resend a PIN.
        CheckCancelled();
      }
      Delay(500);
    }
  }
  ~Session(){try{Stop();}catch(const std::exception &e){fprintf(stderr,"mobile cleanup: %s\n",e.what());}}

  void CheckModem() {
    if(!spes::Running())throw std::runtime_error("The modem stopped");
  }
  Endpoint Find(const std::vector<Endpoint> &endpoints,uint32_t service,uint32_t node=UINT32_MAX) {
    for(const auto &e:endpoints)if(e.service==service&&(e.instance>>8)==0&&(node==UINT32_MAX||e.node==node))return e;
    throw std::runtime_error("Required modem service "+std::to_string(service)+" is unavailable");
  }
  void Dns() {
    if(WifiConnected()) { RestoreDns();return; }
    // AERA's Wi-Fi-off path can retain a default route. Delete only routes
    // belonging to a WLAN whose carrier is down, never another active link.
    std::istringstream routes(Read("/proc/net/route"));std::string line;
    while(std::getline(routes,line)) {
      std::istringstream fields(line);std::string iface,destination,gateway;
      fields>>iface>>destination>>gateway;
      if(iface=="wlan0"&&destination=="00000000"&&Read("/sys/class/net/wlan0/carrier")!="1") {
        uint32_t raw=0;std::istringstream(gateway)>>std::hex>>raw;
        in_addr a{raw};char text[INET_ADDRSTRLEN];
        if(inet_ntop(AF_INET,&a,text,sizeof(text)))Ip({"route","del","default","via",text,"dev",iface},false);
      }
    }
    if(dns_owned)return;
    struct stat resolver{};
    const int existing=lstat("/etc/resolv.conf",&resolver);
    if((existing&&errno!=ENOENT)||(!existing&&!S_ISREG(resolver.st_mode)))
      throw std::runtime_error("Unsupported recovery resolver file");
    old_resolv_exists=existing==0;
    struct statfs fs{};
    // A clean recovery boot may not have a resolver yet. Validate the RAM
    // parent in that case, then create the file instead of rejecting it.
    if(statfs(old_resolv_exists?"/etc/resolv.conf":"/etc",&fs)||
        (static_cast<unsigned long>(fs.f_type)!=0x01021994UL&&static_cast<unsigned long>(fs.f_type)!=0x858458f6UL))
      throw std::runtime_error("Resolver configuration is not in volatile recovery memory");
    old_resolv=Read("/etc/resolv.conf");
    own_resolv="nameserver "+dns1+"\nnameserver "+dns2;
    char value[PROPERTY_VALUE_MAX];
    property_get("net.dns1",value,"");old_dns[0]=value;
    property_get("net.dns2",value,"");old_dns[1]=value;
    if(!Write("/etc/resolv.conf",own_resolv+"\n",O_WRONLY|O_CREAT|O_TRUNC,0644))
      throw std::runtime_error("Cannot configure mobile DNS");
    property_set("net.dns1",dns1.c_str());property_set("net.dns2",dns2.c_str());dns_owned=true;
  }
  void RestoreDns() {
    if(!dns_owned)return;
    if(Read("/etc/resolv.conf")==own_resolv) {
      if(old_resolv_exists)Write("/etc/resolv.conf",old_resolv+"\n",O_WRONLY|O_TRUNC);
      // Keep the inode stable for read-only resolver mounts in plugin jails.
      else Write("/etc/resolv.conf","",O_WRONLY|O_TRUNC);
    }
    char value[PROPERTY_VALUE_MAX];
    property_get("net.dns1",value,"");if(value==dns1)property_set("net.dns1",old_dns[0].c_str());
    property_get("net.dns2",value,"");if(value==dns2)property_set("net.dns2",old_dns[1].c_str());
    dns_owned=false;
  }
  void WatchNetwork() {
    // Route/DNS handover must not wait for NAS/WDS requests to finish.
    network_worker=std::thread([this] {
      try {
        while(!network_stop.load()&&!cancel.load()) {
          Dns();
          for(int i=0;i<5&&!network_stop.load()&&!cancel.load();++i)
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
      }catch(const std::exception &error) {
        std::lock_guard<std::mutex> lock(network_mutex);network_error=error.what();
      }
    });
  }
  void Signal() {
    bool registered=false;std::string rat;int dbm=0;
    Values serving;
    try { serving=nas->Call(0x24,{},3,&cancel); }
    catch(const QmiError &error) {
      if(error.code!=74)throw;
      CheckCancelled();
    }
    const auto &system=Field(serving,1);
    if(system.size()>=5&&system[4]<=system.size()-5) {
      registered=system[0]==1&&system[2]==1;
      for(size_t i=5;i<5u+system[4];++i) {
        switch(system[i]) {
          case 4:rat="2G";break;case 5:case 9:if(rat!="4G"&&rat!="5G")rat="3G";break;
          case 8:if(rat!="5G")rat="4G";break;case 12:rat="5G";break;default:break;
        }
      }
    }
    // NR service must actually be available; a stored NR measurement alone
    // is not evidence that the current connection is using 5G.
    try {const auto info=nas->Call(0x4d,{},3,&cancel);const auto &nr=Field(info,0x4a);
      if(nr.size()>=3&&nr[0]==2&&nr[2])rat="5G";
    }catch(const std::exception &){CheckCancelled();}
    try {
      const auto info=nas->Call(0x4f,{},3,&cancel);
      if(rat=="5G"&&Field(info,0x17).size()>=2)dbm=static_cast<int16_t>(U16(Field(info,0x17).data()));
      else if(rat=="4G"&&Field(info,0x14).size()>=4)dbm=static_cast<int16_t>(U16(&Field(info,0x14)[2]));
      else if(rat=="3G"&&Field(info,0x13).size()>=1)dbm=static_cast<int8_t>(Field(info,0x13)[0]);
      else if(rat=="2G"&&Field(info,0x12).size()>=1)dbm=static_cast<int8_t>(Field(info,0x12)[0]);
    }catch(const std::exception &){CheckCancelled();}
    const bool valid=registered&&dbm>=-160&&dbm<=-20;
    int bars=-1;
    if(valid) {
      const bool rsrp=rat=="4G"||rat=="5G";
      bars=rsrp?(dbm>=-95?4:dbm>=-105?3:dbm>=-115?2:dbm>=-125?1:0):
                 (dbm>=-75?4:dbm>=-85?3:dbm>=-95?2:dbm>=-105?1:0);
    }
    std::lock_guard<std::mutex> lock(state_mutex);
    status["registered"]=registered;status["technology"]=registered?rat:"";
    status["signal_valid"]=valid;status["signal_dbm"]=valid?dbm:0;status["bars"]=bars;
    const std::string operator_name=PlmnName(Field(serving,0x12));
    if(!operator_name.empty())status["operator"]=operator_name;
    SaveLocked();
  }
  void Connect(const std::string &apn,int subscription) {
    lease.reset(open(kLease,O_RDWR|O_CREAT|O_CLOEXEC|O_NOFOLLOW,0600));
    if(lease.get()<0||flock(lease.get(),LOCK_SH|LOCK_NB))throw std::runtime_error("Finish the current storage operation first");
    const auto reason=Capability();if(!reason.empty())throw std::runtime_error(reason);
    Phase("starting","Preparing the modem");
    spes::Start(cancel);
    Phase("registering","Waiting for mobile network registration");
    std::vector<Endpoint> endpoints;Endpoint nase;
    bool found=false;
    for(int attempt=0;attempt<30&&!found;++attempt) {
      CheckModem();endpoints=Discover(&cancel);
      try{nase=Find(endpoints,3);Find(endpoints,2,nase.node);Find(endpoints,1,nase.node);found=true;}
      catch(const std::exception &){Delay(300);}
    }
    if(!found)throw std::runtime_error("The modem did not expose its data services");
    QmiClient dms(Find(endpoints,2,nase.node));Bytes online;Tlv(online,1,{0});
    // A modem that has just booted lists DMS before it accepts Set Operating
    // Mode, and answers QMI_ERR_DEVICE_NOT_READY (52) for a few seconds.
    for(int attempt=0;;++attempt) {
      try{dms.Call(0x2e,online,12,&cancel);break;}
      catch(const QmiError &e){if(e.code!=kQmiDeviceNotReady||attempt>=40)throw;}
      CheckModem();Delay(500);
    }
    nas=std::make_unique<QmiClient>(nase);
    wds=std::make_unique<QmiClient>(Find(endpoints,1,nase.node));
    if(subscription) {
      Bytes binding;Tlv(binding,1,Words({static_cast<uint32_t>(subscription)}));
      wds->Call(0xaf,binding,6,&cancel);
      const auto bound=wds->Call(0xb0,{},6,&cancel);
      const auto &selected=Field(bound,0x10);
      if(selected.size()!=4||U32(selected.data())!=static_cast<uint32_t>(subscription))
        throw std::runtime_error("The modem did not select the requested data SIM");
      // NAS binding is client-local too, and must match the selected WDS SIM.
      Bytes nas_binding;Tlv(nas_binding,1,{static_cast<uint8_t>(subscription-1)});
      nas->Call(0x45,nas_binding,6,&cancel);
    }
    int selected_subscription=subscription;
    if(!selected_subscription) {
      const auto bound=wds->Call(0xb0,{},6,&cancel);const auto &value=Field(bound,0x10);
      if(value.size()==4)selected_subscription=static_cast<int>(U32(value.data()));
    }
    WaitForSim(Find(endpoints,11,nase.node),selected_subscription);
    if(subscription)SelectDataSubscription(endpoints,nase.node,subscription);
    Phase("registering","Waiting for mobile network registration");
    bool attached=false;
    for(int attempt=0;attempt<60&&!attached;++attempt) {
      CheckModem();
      try {
        auto reply=nas->Call(0x24,{},4,&cancel);const auto &serving=Field(reply,1);
        attached=serving.size()>=3&&serving[0]==1&&serving[2]==1;
      }catch(const QmiError &error) {
        // NAS may be published before subscription information is available.
        if(error.code!=74)throw;
        CheckCancelled();
      }
      if(!attached)Delay(750);
    }
    if(!attached)throw std::runtime_error("SIM is not registered for data. Check PIN, coverage and SIM selection");
    const auto endpoint=Ipa({3,0,0,0,0,0}),pipes=Ipa({0x10,0,0,0,0,0});
    dpm=std::make_unique<QmiClient>(Find(endpoints,47,nase.node));
    Bytes hardware{1};Append(hardware,Words({4,endpoint[1],pipes[1],pipes[2]}));Bytes request;
    Tlv(request,0x11,hardware);dpm->Call(0x20,request,12,&cancel);
    wda=std::make_unique<QmiClient>(Find(endpoints,26,nase.node));
    Bytes format;Tlv(format,0x10,{0});
    for(const auto &v:std::vector<std::pair<uint8_t,uint32_t>>{{0x11,2},{0x12,spes::kDataFormat.aggregation},{0x13,spes::kDataFormat.aggregation},{0x15,32},{0x16,16384},{0x1b,32},{0x1c,16384}})
      Tlv(format,v.first,Words({v.second}));
    Tlv(format,0x17,Words({4,endpoint[1]}));auto negotiated=wda->Call(0x20,format,12,&cancel);
    for(uint8_t tag:{0x11,0x12,0x13}) {
      const auto &value=Field(negotiated,tag);
      if(value.size()!=4||U32(value.data())!=(tag==0x11?2u:spes::kDataFormat.aggregation))
        throw std::runtime_error("Unsupported modem data format (field "+std::to_string(tag)+"="+
            (value.size()==4?std::to_string(U32(value.data())):std::string("none"))+")");
    }
    Bytes binding;Tlv(binding,0x10,Words({4,endpoint[1]}));Tlv(binding,0x11,{1});wds->Call(0xa2,binding,12,&cancel);
    Bytes family;Tlv(family,1,{4});wds->Call(0x4d,family,12,&cancel);
    std::string effective_apn=apn;
    if(effective_apn.empty()) {
      try {
        const auto attach=wds->Call(0x85,{},5,&cancel);
        const auto &value=Field(attach,0x10);
        if(!value.empty()&&value.size()<=100) {
          std::string candidate(value.begin(),value.end());
          if(candidate.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")==std::string::npos)
            effective_apn=candidate;
        }
      }catch(const std::exception &){CheckCancelled();}
      if(effective_apn.empty())throw std::runtime_error("Enter the access point name (APN) supplied by your carrier");
    }
    {std::lock_guard<std::mutex> lock(state_mutex);status["effective_apn"]=effective_apn;}
    Phase("connecting","Establishing the data connection");
    Bytes start;Tlv(start,0x14,Bytes(effective_apn.begin(),effective_apn.end()));Tlv(start,0x19,{4});
    auto reply=wds->Call(0x20,start,45,&cancel);const auto &value=Field(reply,1);
    if(value.size()!=4)throw std::runtime_error("The modem returned no data session handle");handle=U32(value.data());
    Bytes settings_request;Tlv(settings_request,0x10,Words({0x2310}));const auto settings=wds->Call(0x2d,settings_request,12,&cancel);
    std::string address=Address(settings,0x1e),gateway=Address(settings,0x20),netmask=Address(settings,0x21);
    dns1=Address(settings,0x15);dns2=Address(settings,0x16);
    if(address.empty()||gateway.empty()||dns1.empty()||dns1=="0.0.0.0")throw std::runtime_error("The network returned incomplete IPv4 settings");
    if(dns2.empty()||dns2=="0.0.0.0")dns2=dns1;
    int mtu=1500;const auto &mtu_field=Field(settings,0x29);if(mtu_field.size()==4)mtu=U32(mtu_field.data());
    if(mtu<576||mtu>9000)throw std::runtime_error("Invalid modem MTU");
    CreateLink();link_owned=true;
    Ip({"link","set","rmnet_ipa0","up"});Ip({"link","set",kInterface,"mtu",std::to_string(mtu),"up"});
    Ip({"addr","add",address+"/"+std::to_string(Prefix(netmask)),"dev",kInterface});
    if(!spes::IpaFormatConfigured()) {
      Ipa({6,spes::kDataFormat.ipa_egress,0,0,0,0});Ipa({7,spes::kDataFormat.ipa_ingress,16384,32,0,0});
      spes::MarkIpaFormatConfigured();
    }
    IpaData channel{};channel[0]=5;channel[1]=1;memcpy(&channel[2],kInterface,strlen(kInterface)+1);Ipa(channel);
    Ip({"route","add","default","via",gateway,"dev",kInterface,"metric","900"});
    Dns();
    {std::lock_guard<std::mutex> lock(state_mutex);status["connected"]=true;status["interface"]=kInterface;
      status["address"]=address;status["gateway"]=gateway;status["dns1"]=dns1;status["dns2"]=dns2;status["mtu"]=mtu;}
    established=true;
    Phase("connected","Mobile data connected");
    WatchNetwork();
    while(!cancel.load()) {
      {std::lock_guard<std::mutex> lock(network_mutex);
        if(!network_error.empty())throw std::runtime_error(network_error);}
      CheckModem();
      Bytes current=wds->Call(0x22,{},4,&cancel)[1];
      if(current.empty()||current[0]!=2)throw std::runtime_error("The mobile network disconnected");
      Signal();Delay(2500);
    }
  }
  void Stop() {
    network_stop.store(true);
    if(network_worker.joinable())network_worker.join();
    if(wds&&handle) {
      try{Bytes payload;Tlv(payload,1,Words({handle}));wds->Call(0x21,payload,5);}catch(const std::exception &e){fprintf(stderr,"Stop data: %s\n",e.what());}
      handle=0;
    }
    RestoreDns();
    if(link_owned){Ip({"link","del",kInterface},false);link_owned=false;}
    wds.reset();wda.reset();dpm.reset();nas.reset();
    lease.reset();
  }
};

void Worker(std::string apn,int subscription) {
  std::string failure;
  bool was_connected=false;
  unsigned retry_seconds=5;
  while(!cancel.load()) {
    Session session;
    try{session.Connect(apn,subscription);}catch(const std::exception &e){if(!cancel.load())failure=e.what();}
    was_connected|=session.established;
    if(session.established)retry_seconds=5;
    Phase("stopping","Disconnecting mobile data");
    try{session.Stop();}catch(const std::exception &e){Phase("error",e.what());}
    {std::lock_guard<std::mutex> lock(state_mutex);ClearConnectionLocked();}
    if(cancel.load()||!was_connected)break;
    Phase("waiting","Mobile connection lost. Retrying in "+std::to_string(retry_seconds)+" seconds");
    try{Delay(retry_seconds*1000);}catch(const std::exception &){break;}
    retry_seconds=std::min(60u,retry_seconds*2);
  }
  {std::lock_guard<std::mutex> lock(state_mutex);status["enabled"]=false;status["connected"]=false;
    ClearPin(pending_pin);pending_pin_request.clear();status["pin_request"]="";
    status["registered"]=false;status["signal_valid"]=false;status["bars"]=-1;status["technology"]="";status["address"]="";}
  if(cancel.load())failure.clear();
  Phase(failure.empty()?"off":"error",failure.empty()?"Mobile data is off":failure);
  {std::lock_guard<std::mutex> lock(completion_mutex);working.store(false);}completion.notify_all();
}
bool Disconnect() {
  cancel.store(true);
  std::unique_lock<std::mutex> lock(completion_mutex);
  return completion.wait_for(lock,std::chrono::seconds(60),[]{return !working.load();});
}
void OnSignal(int){cancel.store(true);exiting.store(true);}
}

int Main(int argc,char **argv) {
  if(argc==4&&std::string(argv[1])=="connect") {
    Json::Value config;config["apn"]=argv[2];
    if(strlen(argv[3])!=1||argv[3][0]<'0'||argv[3][0]>'2')return 2;
    config["subscription"]=argv[3][0]-'0';
    Json::StreamWriterBuilder builder;builder["indentation"]="";
    std::string reply;
    bool ok=Request("connect "+Json::writeString(builder,config),&reply)&&reply=="OK";
    fprintf(stdout,"%s\n",reply.c_str());return ok?0:1;
  }
  if(argc>1&&std::string(argv[1])=="disconnect") {
    std::string reply;return Request("disconnect",&reply,65000)&&reply=="OK"?0:1;
  }
  if(argc!=1)return 2;
  if(!spes::InRecovery())return 1;
  umask(0077);
  if(mkdir(kDirectory,0700)&&errno!=EEXIST)return 1;
  struct statfs fs{};if(statfs(kDirectory,&fs)||
      (static_cast<unsigned long>(fs.f_type)!=0x01021994UL&&static_cast<unsigned long>(fs.f_type)!=0x858458f6UL))return 1;
  Fd instance(open("/tmp/aera-cellular-daemon.lock",O_RDWR|O_CREAT|O_CLOEXEC|O_NOFOLLOW,0600));
  if(instance.get()<0||flock(instance.get(),LOCK_EX|LOCK_NB))return 1;
  Fd server(socket(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC|SOCK_NONBLOCK,0));
  sockaddr_un address{};address.sun_family=AF_UNIX;strcpy(address.sun_path,kSocket);
  unlink(kSocket);
  if(server.get()<0||bind(server.get(),reinterpret_cast<sockaddr *>(&address),sizeof(address))||listen(server.get(),4))return 1;
  chmod(kSocket,0600);signal(SIGPIPE,SIG_IGN);signal(SIGTERM,OnSignal);signal(SIGINT,OnSignal);
  status["available"]=Capability().empty();status["enabled"]=false;status["connected"]=false;status["bars"]=-1;
  Phase("off",Capability().empty()?"Mobile data is off":Capability());
  std::thread worker;
  while(!exiting.load()) {
    pollfd p{server.get(),POLLIN,0};if(poll(&p,1,250)<=0)continue;
    Fd client(accept4(server.get(),nullptr,nullptr,SOCK_CLOEXEC));if(client.get()<0)continue;
    ucred credentials{};socklen_t length=sizeof(credentials);
    if(getsockopt(client.get(),SOL_SOCKET,SO_PEERCRED,&credentials,&length)||credentials.uid!=0)continue;
    pollfd request_poll{client.get(),POLLIN,0};if(poll(&request_poll,1,250)<=0)continue;
    char buffer[1024];ssize_t count=recv(client.get(),buffer,sizeof(buffer),MSG_TRUNC);
    if(count<=0||count>=static_cast<ssize_t>(sizeof(buffer)))continue;
    std::string command(buffer,count),reply="ERROR";
    if(command=="disconnect")reply=Disconnect()?"OK":"Modem is still stopping. Reboot before flashing";
    else if(command=="disconnect-async"){cancel.store(true);reply="OK";}
    else if(command.rfind("verify-pin ",0)==0) {
      Json::CharReaderBuilder reader;Json::Value config;std::string error;
      std::istringstream input(command.substr(11));
      if(Json::parseFromStream(reader,input,&config,&error)&&config.isObject()&&
          config["pin"].isString()&&config["request"].isString()&&config["id"].isString()) {
        std::string pin=config["pin"].asString();
        std::lock_guard<std::mutex> lock(state_mutex);
        if(working.load()&&!cancel.load()&&status["state"]=="pin_required"&&pending_pin.empty()&&
            status["pin_request"]==config["request"]&&status["sim_id"]==config["id"]&&
            ValidPin(pin)&&status.get("pin_retries",0).asUInt()>0) {
          pending_pin.swap(pin);pending_pin_request=config["request"].asString();
          status["pin_attempt"]=status.get("pin_attempt",0).asUInt()+1;
          status["state"]="verifying_pin";status["message"]="Verifying SIM PIN";
          status.removeMember("pin_result");SaveLocked();reply="OK";
        }else reply="SIM state changed. Check the selected SIM and try again";
        ClearPin(pin);
      }
      ClearPin(command);memset(buffer,0,sizeof(buffer));
    }
    else if(command.rfind("connect ",0)==0&&!working.load()) {
      Json::CharReaderBuilder reader;Json::Value config;std::string error;
      std::istringstream input(command.substr(8));
      if(Json::parseFromStream(reader,input,&config,&error)&&config.isObject()&&
          config["apn"].isString()&&config["subscription"].isInt()) {
        std::string apn=config["apn"].asString();int subscription=config["subscription"].asInt();
        bool valid=apn.size()<=100&&subscription>=0&&subscription<=2;
        for(unsigned char c:apn)valid&=(c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='.'||c=='-'||c=='_';
        if(valid) {
          if(worker.joinable())worker.join();cancel.store(false);working.store(true);
          {std::lock_guard<std::mutex> lock(state_mutex);ClearConnectionLocked();status["enabled"]=true;status["subscription"]=subscription;status["apn"]=apn;
            ClearPin(pending_pin);pending_pin_request.clear();status["pin_request"]="";
            status["sim_state"]="";status["sim_slot"]=0;status["sim_id"]="";status["pin_attempt"]=0;
            status.removeMember("pin_result");status["sims"]=Json::Value(Json::arrayValue);SaveLocked();}
          worker=std::thread(Worker,apn,subscription);reply="OK";
        }else reply="Invalid APN or SIM selection";
      }
    }
    send(client.get(),reply.data(),reply.size(),MSG_NOSIGNAL);
  }
  Disconnect();if(worker.joinable())worker.join();unlink(kSocket);return 0;
}
}
int main(int argc,char **argv){return aera::mobile::Main(argc,argv);}
