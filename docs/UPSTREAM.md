# Code origin, changes and contribution

Spanish version: [UPSTREAM.es.md](UPSTREAM.es.md). The other documents in
`docs/` are in Spanish.

## Upstream and sources

| Source | Use | License |
|---|---|---|
| `AERA-Recovery/android_manifest` `aera-16.0` | build manifest | no license file (AOSP components, Apache-2.0) |
| `AERA-Recovery/android_bootable_recovery` `aera-16.0` | not modified by the tree; the generic fixes below are kept as separate patches | GPL-3.0 / Apache-2.0 per file |
| `AERA-Recovery/android_device_xiaomi_dada-AERA`, `garnet-AERA` | conventions (layout, `AERA_*` names, `vendorsetup.sh`, USB rc) | Apache-2.0 / GPL-3.0 (headers) |
| `AERA-Recovery/android_device_oneplus_infiniti-AERA` | mobile data provider (`mobile_data/`, from `f7fca594`) | Apache-2.0 |
| `OrangeFox/device/spes` `fox-12.1` (Jashkirat) | board values (sizes, platform, brightness, display) | Apache-2.0 (LineageOS headers) / GPL-3.0 (`vendorsetup.sh`) |
| `spes-development/spes-vendor-dump` | fstab, props, VINTF, module and blob lists (reference only) | Xiaomi/Qualcomm proprietary firmware |
| `device/qcom/twrp-common` (AERA) | Qualcomm decryption services (through `qcom_decrypt*`) | unchanged |

The kernel and the vendor files were extracted from the EvolutionX 16.0 11.10
build for spes; provenance in `prebuilt/kernel.info` and `tools/blobs.sha256`.

### Repository not reused

`Aim-uses-Malware/android_device_spes-AERA` (2026-10-16) is an earlier AERA
attempt for spes. **No code was reused**: it has no license, ships blobs of
undocumented origin and values marked TODO. It only confirmed that there was
no official port.

## Changes to AERA components

The device tree does not modify AERA. There are **eleven generic patches**
proposed for `bootable/recovery`, kept apart in `patches/bootable_recovery/`
and applied with `tools/apply-aera-patches.sh <source root>` (which also
regenerates `catalog_generated.cpp` when the catalog changes). The tree builds
without them. None has been sent upstream yet.

- **`0001-partition-skip-fsync-on-ADB-backup-stream.diff`**: in
  `TWPartition::Raw_Read_Write`, skip `fsync()` when the destination is a FIFO
  (the `adb backup` stream). There it always fails with `EINVAL`, and AERA
  reported a correct backup as failed. Writes to files and partitions,
  including ADB restore, are still synced. Tested on spes.

- **`0002-catalog-fix-corrupted-Spanish-translations.diff`**: in
  `aeraui/localization/catalog/catalog.json`, 6 `es-ES` strings had `?`
  instead of `ó`, `ú`, `ñ` or `í` (for example "A?adir red", "Mostrar
  contrase?a"). Checked that `generate_catalog.py` reproduces upstream's
  `catalog_generated.cpp` exactly from the original JSON.

- **`0003-catalog-complete-Spanish-translation.diff`** (needs `0002`): completes
  the `es-ES` catalog. Only `es-ES` entries change, with no reformatting (the
  JSON is rewritten with `indent=2`, which reproduces the original byte for
  byte). Coverage goes from 2094 to 2747 of 2768 strings.
  - **653 strings added**, out of the 674 without a translation.
  - **13 fixed** that were identical to English without being proper names
    (`Backup`, `Wipe`, `Slot %s`, `Flashing %s`, `Update %s?`...).
  - **14 repaired** with misplaced placeholders or extra line breaks (for
    example `%u downloads` → `"Descargas de%u "`).
  - **21 left in English on purpose**: product names (`AERA Doom`, `AERA
    Gallery`...), technical terms and abbreviations (`Firmware`, `RAM`,
    `DNS 1`...) and format-only strings (`%.1f MB`, `%d %s`...).
  - Style: neutral technical Spanish, consistent with the existing strings
    (informal *tú* in instructions, infinitive on buttons). Fixed terminology:
    *slot* → ranura, *flash* → flashear, *snapshot* → instantánea, *plugin* →
    complemento. Paths, commands and tool names stay literal.
  - Validation: valid JSON; in every `es-ES` string the printf/`{n}`
    placeholders, the number of line breaks and the leading and trailing
    spaces match English; `generate_catalog.py` runs clean; in
    `chinese_catalog_test.py` the "generated catalog is up to date" check
    passes, and the Chinese coverage failures are the same with and without
    the patch (an upstream issue).

- **`0004-wifi-localize-status-and-test-result-Spanish-respaldo.diff`** (needs
  `0003`): Wi-Fi texts that stayed in English on the phone, plus "respaldo"
  in short Spanish labels. Touches `aeraui/scenes/wifi_scene.cpp` and the
  catalog.
  - Code (generic):
    - `BusyTitle()` translates the base text before appending the animated
      dots. Before, "Turning Wi-Fi on..." matched no key.
    - Raw backend states (`wlan_state`: `enabling`, `disabling`,
      `disconnecting`, `scanning`, `connecting`) are shown as catalog labels
      (`WifiStateTag()`).
    - The lines returned by the network test in `wlan.cpp` ("Connected: …",
      "IP address: …", "Internet: Failed"...) are translated when shown
      (`TranslateTestResult()`): the label and the `OK`/`Failed` status are
      translated, and the SSID and IP stay as they are. `wlan.cpp` is not
      changed, because `aera_backend.cpp` compares those values literally.
  - Catalog: 9 new keys with `en`, `es-ES`, `zh_CN` and `zh_TW` (so no Chinese
    coverage failure is added), and 38 changed `es-ES` strings.
  - Validation: `clang++ -fsyntax-only -Wall -Wextra` with no new warnings;
    the same placeholder checks as `0003`; `0001`–`0004` apply in sequence on
    a clean upstream.

- **`0005-wifi-translate-remaining-state-labels.diff`** (needs `0004`): Wi-Fi
  state labels that were still in English.

- **`0006-aeraui-rotate-scaled-software-frame-in-landscape.diff`**: in
  `aeraui/core/engine.cpp`, the scaled software frame copy did not apply the
  rotation in landscape. LVGL hands over a `height_` × `width_` frame and
  leaves the quarter turn to the flush. The patch uses the same transform as
  `SetPointer()`. Fixes landscape with software rendering and
  `AERA_UI_ADAPTIVE_RESOLUTION` (verified on spes, build 24).

- **`0007-catalog-mobile-data-strings-es-zh.diff`**: 57 entries for the mobile
  data screen and messages in `en`, `es-ES`, `zh_CN` and `zh_TW`.
  `chinese_catalog_test.py` goes from 58 to 54 failures (the upstream ones),
  adding none.

- **`0008-browser-enable-Zink-on-Adreno-without-hw-multiview.diff`**: adds
  `TU_DEBUG=noconform` to the AERA Browser engine environment in
  `aeraui/features/browser/jail_main.cpp`.
  - Cause: in Mesa 26.2.2, Turnip reports Vulkan 1.1 only when the GPU has
    hardware multiview (`tu_is_vk_1_1()` → `tu_has_multiview()`), and
    `VK_KHR_maintenance5` depends on it. The Adreno 610 (and the A702, profile
    `a6xx_gen1_low` with `has_hw_multiview = False`) stays at Vulkan 1.0
    without `maintenance5`. Zink requires it and silently rejects the device:
    "egl: failed to create dri2 screen", `EGL_NOT_INITIALIZED`, and the WebKit
    engine aborts.
  - Effect: in Turnip, `TU_DEBUG_NOCONFORM` is only read by
    `tu_has_multiview()`. On those GPUs it exposes multiview (not
    CTS-conformant) and with it Vulkan 1.1 and `maintenance5`. It changes
    nothing on other GPUs, which already have hardware multiview.
  - Measured on spes with a Vulkan probe inside the plugin runtime: without
    the variable, "Adreno (TM) 610 api 1.0.354", no `VK_KHR_multiview` and no
    `VK_KHR_maintenance5`; with it, "api 1.3.354" with both, and
    `vkCreateDevice` succeeds in both cases. AERA Browser then loads pages.
  - Alternative without touching `bootable/recovery`: the same change inside
    the signed plugin runtime (a Mesa patch for A610/A702, like the A722/A825
    ones in `AERA-Plugins/browser`). Proposed in the jail because it is one
    line, needs no Mesa rebuild and is harmless on other GPUs.

- **`0009-browser-send-Enter-from-the-keyboard-action-key.diff`**: in
  `aeraui/features/browser/web_scene.cpp`, the action key (✓) of a page
  keyboard only closed the keyboard, so a Google search or a form could not
  be submitted with Enter. LVGL reports that key only as `LV_EVENT_READY`,
  before the `VALUE_CHANGED` branch that injects keys, and `HideKeyboard()`
  clears `web_keyboard`. The `READY` branch now sends Enter (13) to the page,
  then closes the keyboard. Tested on spes (build 35).

- **`0010-mobile-data-show-the-private-IPv4-address.diff`**: in
  `aeraui/scenes/mobile_data_scene.cpp`, the mobile data connection card adds
  a "Private IPv4" row (the `address` the provider already publishes in
  `status.json`) under "Public IPv4". Carriers often share the public address
  behind NAT (both test SIMs got the same one), so only the private address
  shows which SIM carries the data. Catalog: 1 new key in `en`, `es-ES`,
  `zh_CN` and `zh_TW`. Verified on hardware (build 41). The AERA web demo
  already shows more rows in that card (carrier, network, data SIM, default
  connection), but that code is not public: on 2026-11-23 the local
  `bootable/recovery` (`1cabc50`, 2026-11-15) was the head of `aera-16.0`
  and has none of those strings. The patch must be redone on that version
  once it is published.

- **`0011-catalog-Spanish-review-labels.diff`** (needs `0004`): Spanish labels
  for the Backup, Restore and Wipe buttons and confirmation sheet. "Review"
  had been translated as the noun "reseña" (a product review): `Review
  backup` → "Crear respaldo", `Review restore` → "Restaurar respaldo",
  `Review wipe` → "Borrar particiones", `Review %s` → "Detalle %s" (sheet
  title, for example "Detalle Respaldo") and `Review` → "Revisar". Only 5
  `es-ES` values change. Verified on hardware (build 42).

### Proposal without a patch: `blob:` downloads in AERA Browser

The "Download" button of a file on GitHub, and in general any
`<a download href="blob:…">`, downloads nothing. The `decide-policy` handler
in `aeraui/features/browser/worker.cpp` (identical to `aera_worker.cpp`)
ignores every navigation whose URL does not pass `Address()`, which only
accepts `http(s)://`. `https://` downloads do work (a GitHub Releases asset,
build 35). Suggested change in the `NAVIGATION_ACTION` branch, before the
`ignore`:

```cpp
// Same-origin blob: URLs are how pages hand a generated file to the user
// (<a download href="blob:https://...">). Never render them; save them.
if (uri && g_str_has_prefix(uri, "blob:https://")) {
  webkit_policy_decision_download(d); return TRUE;
}
```

The worker ships inside `prebuilt/runtime.xz` (built with `build-worker.sh`
against WPE 2.52.6), so the runtime has to be rebuilt and re-signed to test
it, which could not be done here. Untested which file name WebKit suggests in
that case (the `download` attribute or the blob UUID).

The Plugin SDK was not touched.

### Proposal for the official mobile data provider: dual SIM

The code lives in the device tree (`mobile_data/sim_session.hpp`, new, and
`ProvisionSims` / `SelectDataSubscription` in `daemon.cpp`), so there is no
`bootable/recovery` patch. It applies to the provider spes derives from
(`mobile_data/` in infiniti). Without the Android radio stack:

- The modem leaves empty the provisioning sessions Android did not activate
  (the second SIM, or SIM 1 if Android left it inactive), and with no primary
  session it registers on no network at all. They are filled with UIM 0x38
  *Change Provisioning Session* (primary → slot 1, secondary → slot 2, with
  the AID of the SIM/USIM application read from UIM 0x2F).
- Data follows the modem's default data subscription (DDS), not the WDS
  binding, so with SIM 2 selected the call came up on SIM 1. The DDS is moved
  with DSD 0x4E *Switch DDS* (TLV 0x01 = subscription), then the provider
  waits for DSD 0x4F *Get Current DDS* to confirm it, because the switch is
  asynchronous and a call started before it completes comes up on the
  previous SIM. The message IDs come from qcril (`libril-qc-hal-qmi.so`,
  `DSDModemEndPointModule::qmiDDSSwitchRequest` and
  `DSDModemEndPoint::getCurrentDDSSync`).

Verified on spes with two SIMs (build 40). Each SIM gets its own private
address, switching works without a reboot, and the modem DDS follows the
selected SIM. It should help any official tree with the same provider and
dual SIM, but it was only tested on SM6225. `sim_session.hpp` is
device-independent. Details: [MOBILE_DATA.md](MOBILE_DATA.md) (Spanish),
steps 6 and 6b.

## Attribution

- `init.recovery.usb.rc` is new (Apache-2.0). The first version was based on
  The Linux Foundation's BSD template. It was rewritten to defer to AERA's
  `init.rc` and no longer contains that code.
- `BoardConfig.mk`, `device.mk`, `twrp_spes.mk` and `AndroidProducts.mk` keep
  the 2021 LineageOS copyright of the original spes tree.

## Official contribution

Repository: https://github.com/michaaels/android_device_xiaomi_spes-AERA,
branch `aera-16.0`, path `device/xiaomi/spes`. It is proposed for spes only.
The tree also detects spesn, but that variant is untested.

Status of the conditions:

1. Reproducible build from the public manifest: done. Clean build on the
   latest public AERA sources, commit `e038300` (see `BUILD.md`).
2. Kernel and blobs with documented provenance: `prebuilt/kernel.info` and
   `tools/blobs.sha256`.
3. `TESTING.md` matrix PASS for boot, display, touch, ADB, partitions,
   decryption and return to Android: done, plus Wi-Fi, mobile data,
   backup/restore and permanent install.

The repository is public. No pull request has been opened and no release has
been published. The AERA team has not been contacted yet.
