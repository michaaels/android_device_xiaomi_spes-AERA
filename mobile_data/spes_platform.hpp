/* SPDX-License-Identifier: Apache-2.0 */
// spes / spesn (SM6225, integrated modem, IPA data path) platform glue for the
// AERA cellular provider: recovery detection and the modem lifecycle.
//
// The official AERA providers boot the modem themselves (remoteproc plus their
// own RAM storage helpers). On spes the modem is already brought up by the
// device's Wi-Fi stack, because the WLAN firmware also runs on the modem:
// spes-wlan-up.sh prepares the RAM sandbox (EFS on RAM loops, persist/rfs and
// /data/vendor on tmpfs), starts the stock QMI daemons from a RAM copy of the
// installed vendor and spes-modem-hold.sh holds /dev/subsys_modem. Mobile data
// reuses exactly that path, so nothing the modem writes reaches a partition.
//
// The modem is shared with Wi-Fi and stays held until recovery reboots, like
// the Wi-Fi bring-up; stopping mobile data only ends the data session.
#pragma once

#include <cutils/properties.h>
#include <dirent.h>
#include <fcntl.h>
#include <net/if.h>
#include <sys/socket.h>
#include <unistd.h>
#include <atomic>
#include <chrono>
#include <fstream>
#include <stdexcept>
#include <string>
#include <thread>

namespace aera::mobile::spes {
inline constexpr const char *kPrepareProperty = "spes.wlan.prep";  // 1 / fail
inline constexpr const char *kStartProperty = "spes.modem.up";     // init.recovery.wifi.rc
inline constexpr const char *kPrepareScript = "/system/bin/spes-wlan-up.sh";
inline constexpr const char *kModemHoldService = "init.svc.spes-modem-hold";
inline constexpr const char *kSubsystems = "/sys/bus/msm_subsys/devices";

// Data-path format. The official integrated-modem provider (SM8850) uses
// QMAPv5 with checksum offload; the SM6225 modem negotiates QMAP v1 only
// (WDA set-data-format answers UL/DL aggregation 5 when asked for 9), which
// carries no MAPv5 checksum trailer. Values were confirmed on spes hardware.
struct DataFormat {
  uint32_t aggregation;   // WDA UL/DL aggregation protocol (5 = QMAP)
  uint32_t rmnet_flags;   // IFLA_RMNET_FLAGS: ingress deaggregation only
  uint32_t ipa_egress;    // RMNET_IOCTL_SET_EGRESS_DATA_FORMAT: MAP|AGG|MUX
  uint32_t ipa_ingress;   // RMNET_IOCTL_SET_INGRESS_DATA_FORMAT: MAP|DEAGG|DEMUX|AGG_DATA
};
inline constexpr DataFormat kDataFormat{5, 0x00000001, 0x0e, 0x2e};

// rmnet_ipa3 on this 4.19 kernel sets up the WAN pipes on the first
// SET_EGRESS/INGRESS_DATA_FORMAT and rejects any later call with EINVAL (the
// pipes are not torn down on disconnect). Configure them once per boot; the
// marker lives in RAM, so it is gone after a reboot like the pipes.
inline constexpr const char *kIpaFormatMarker = "/tmp/aera-cellular/ipa-format-configured";
inline bool IpaFormatConfigured() { return access(kIpaFormatMarker, F_OK) == 0; }
inline void MarkIpaFormatConfigured() {
  const int fd = open(kIpaFormatMarker, O_WRONLY | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (fd >= 0) close(fd);
}

inline std::string ReadLine(const std::string &path) {
  std::ifstream input(path);
  std::string line;
  std::getline(input, line);
  return line;
}

inline std::string Property(const char *name) {
  char value[PROPERTY_VALUE_MAX]{};
  property_get(name, value, "");
  return value;
}

// State of the "modem" peripheral as reported by the Qualcomm subsystem
// restart framework (OFFLINE, ONLINE, OFFLINING...); empty if not found.
inline std::string SubsystemState() {
  DIR *dir = opendir(kSubsystems);
  if (!dir) return {};
  std::string state;
  while (auto *entry = readdir(dir)) {
    if (entry->d_name[0] == '.') continue;
    const std::string path = std::string(kSubsystems) + "/" + entry->d_name;
    if (ReadLine(path + "/name") == "modem") { state = ReadLine(path + "/state"); break; }
  }
  closedir(dir);
  return state;
}

// The official providers require ro.bootmode=recovery. spes has no recovery
// partition: AERA lives in boot and the bootloader leaves ro.bootmode at
// "unknown". The recovery init service exists only in the recovery ramdisk,
// so it still keeps the provider from ever running inside Android.
inline bool InRecovery() {
  return Property("ro.bootmode") == "recovery" || Property("init.svc.recovery") == "running";
}

inline bool Running() {
  return SubsystemState() == "ONLINE" && Property(kModemHoldService) == "running";
}

// Empty when this device can provide mobile data, otherwise the reason shown
// in the UI. It runs when the provider starts with recovery, before the modem
// is prepared, so it must not require rmnet_ipa0: that interface only appears
// once spes-wlan-up.sh loads the IPA firmware (checked by Start()).
inline std::string Capability() {
  if (SubsystemState().empty()) return "No supported Qualcomm modem control was found";
  if (access("/dev/subsys_modem", R_OK)) return "The modem control device is unavailable";
  if (access(kPrepareScript, X_OK)) return "The modem preparation script is not installed";
  const int transport = socket(42 /* AF_QIPCRTR */, SOCK_DGRAM | SOCK_CLOEXEC, 0);
  if (transport < 0) return "The kernel has no QRTR modem transport";
  close(transport);
  return {};
}

// Brings the shared modem up (no-op when Wi-Fi already did) and waits until
// it is online. Throws on failure or when cancel becomes true.
inline void Start(const std::atomic<bool> &cancel) {
  using namespace std::chrono_literals;
  const auto wait = [&](auto done, unsigned seconds, const char *error) {
    for (unsigned i = 0; i < seconds * 10; ++i) {
      if (cancel.load()) throw std::runtime_error("Connection cancelled");
      if (done()) return;
      std::this_thread::sleep_for(100ms);
    }
    throw std::runtime_error(error);
  };
  if (Property(kPrepareProperty) != "1") {
    property_set(kPrepareProperty, "");
    property_set(kStartProperty, "1");
    wait([] { const auto s = Property(kPrepareProperty); return s == "1" || s == "fail"; },
         60, "Modem preparation timed out");
    if (Property(kPrepareProperty) != "1")
      throw std::runtime_error("Modem preparation failed. See /tmp/recovery.log");
  }
  wait(Running, 60, "The modem did not come online");
  wait([] { return if_nametoindex("rmnet_ipa0") != 0; }, 10,
       "The kernel IPA data interface is unavailable");
}
}  // namespace aera::mobile::spes
