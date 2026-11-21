/* SPDX-License-Identifier: Apache-2.0 */
// Operator name from the QMI NAS serving-system "current PLMN" TLV (0x12).
//
// Not spes-specific; candidate for the shared AERA mobile data sources. Some
// modems send the network description as ASCII, others as GSM 03.38 7-bit
// packed text without any coding indicator in this TLV. The SM6225 modem with
// Claro Ecuador sends "43 66 50 fa 04 15 87", which is "CLARO EC" packed.
// Printable ASCII is kept as is; otherwise the bytes are unpacked as GSM 7-bit.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace aera::mobile {
inline bool PrintableAscii(const std::vector<uint8_t> &text) {
  for (uint8_t c : text)
    if (c < 0x20 || c > 0x7e) return false;
  return !text.empty();
}

// GSM 03.38 default alphabet, basic set, mapped to ASCII where it exists.
// Characters with no ASCII equivalent and the escape code become '?'.
inline char GsmToAscii(uint8_t septet) {
  static const char kTable[129] =
      "@?$?????????\n??\r?_?????????????? !\"#?%&'()*+,-./0123456789:;<=>?"
      "?ABCDEFGHIJKLMNOPQRSTUVWXYZ?????"
      "?abcdefghijklmnopqrstuvwxyz?????";
  return septet < 128 ? kTable[septet] : '?';
}

inline std::string UnpackGsm7(const std::vector<uint8_t> &packed) {
  std::string out;
  unsigned carry = 0, bits = 0;
  for (uint8_t byte : packed) {
    carry |= unsigned(byte) << bits;
    bits += 8;
    while (bits >= 7) {
      out += GsmToAscii(carry & 0x7f);
      carry >>= 7;
      bits -= 7;
    }
  }
  // A final septet of zero or CR is padding (GSM 03.38 / 23.038).
  while (!out.empty() && (out.back() == '@' || out.back() == '\r')) out.pop_back();
  return out;
}

// Returns the decoded operator name, or an empty string when the TLV has none.
inline std::string PlmnName(const std::vector<uint8_t> &plmn) {
  // mcc(2) mnc(2) description length(1) description
  if (plmn.size() < 5 || plmn[4] > plmn.size() - 5) return {};
  const std::vector<uint8_t> text(plmn.begin() + 5, plmn.begin() + 5 + plmn[4]);
  if (PrintableAscii(text)) return std::string(text.begin(), text.end());
  const std::string name = UnpackGsm7(text);
  for (char c : name)
    if (c == '?') return {};  // not GSM 7-bit either: show no name, not garbage
  return name;
}
}  // namespace aera::mobile
