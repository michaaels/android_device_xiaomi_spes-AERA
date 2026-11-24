/* SPDX-License-Identifier: Apache-2.0 */
// SIM provisioning sessions and default data subscription for dual-SIM modems.
//
// The modem provisions a SIM application into a session (primary or
// secondary GW) only when the HLOS radio stack asks for it with QMI UIM Change
// Provisioning Session, and keeps what Android last asked for. Recovery has no
// radio stack: a slot Android left inactive, or the second SIM, stays
// "detected" with no session, and the modem registers on no network at all
// while the primary session is empty. Data also follows the modem's default
// data subscription (DDS), not the WDS binding: Android moves it with QMI DSD
// Switch DDS, as qcril does for setPreferredDataModem.
#pragma once
#include "qmi.hpp"

namespace aera::mobile {
constexpr uint16_t kNoSession=0xffff;
constexpr uint8_t kPrimaryGwSession=0,kSecondaryGwSession=2;

struct SimApplication {
  unsigned slot=0,type=0,state=0;
  Bytes aid;
};
struct SimSessions {
  uint16_t primary=kNoSession,secondary=kNoSession;
  std::vector<SimApplication> applications;
};

// Same TLV as ParseSimCards (UIM Get Card Status 0x10), keeping the AIDs.
inline SimSessions ParseSimSessions(const Bytes &bytes) {
  if(bytes.size()<9)throw std::runtime_error("Truncated SIM card status");
  SimSessions out;out.primary=U16(bytes.data());out.secondary=U16(bytes.data()+4);
  size_t offset=9;
  auto byte=[&]() -> unsigned {
    if(offset>=bytes.size())throw std::runtime_error("Truncated SIM application status");
    return bytes[offset++];
  };
  for(unsigned slot=0;slot<bytes[8];++slot) {
    for(unsigned i=0;i<5;++i)byte();
    const unsigned applications=byte();
    for(unsigned app=0;app<applications;++app) {
      SimApplication application;application.slot=slot+1;
      application.type=byte();application.state=byte();
      for(unsigned i=0;i<4;++i)byte();
      const unsigned aid=byte();
      for(unsigned i=0;i<aid;++i)application.aid.push_back(static_cast<uint8_t>(byte()));
      for(unsigned i=0;i<7;++i)byte();
      out.applications.push_back(application);
    }
  }
  return out;
}
inline unsigned SessionSlot(uint16_t index) {
  return index==kNoSession?0:(index>>8)+1;
}
// The SIM or USIM application of a slot (types 1 and 2), as ParseSimCards.
inline const SimApplication *GwApplication(const SimSessions &sessions,unsigned slot) {
  for(const auto &application:sessions.applications)
    if(application.slot==slot&&(application.type==1||application.type==2))return &application;
  return nullptr;
}
inline Bytes ProvisionRequest(uint8_t session,const SimApplication &application) {
  Bytes payload,info{static_cast<uint8_t>(application.slot),
                     static_cast<uint8_t>(application.aid.size())};
  info.insert(info.end(),application.aid.begin(),application.aid.end());
  Tlv(payload,1,{session,1});Tlv(payload,0x10,info);
  return payload;
}
// Slot to provision into an empty session: the slot the session belongs to by
// convention (primary = slot 1, secondary = slot 2), else the other one, never
// a slot the other session already uses. 0 when no slot has a GW application.
inline unsigned SlotForSession(const SimSessions &sessions,uint8_t session) {
  const unsigned taken=SessionSlot(session==kPrimaryGwSession?sessions.secondary:sessions.primary);
  const unsigned preferred=session==kPrimaryGwSession?1:2;
  for(unsigned slot:{preferred,3-preferred})
    if(slot!=taken&&GwApplication(sessions,slot))return slot;
  return 0;
}
}
