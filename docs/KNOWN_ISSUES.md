# Problemas conocidos y pendientes

## Bloqueos

1. **Kernel stock no disponible.** El volcado público solo trae la partición vendor. `boot.img` aparece en su índice, pero no está en el repositorio. Para resolverlo hace falta uno de estos dos:
   - el `boot.img` del paquete fastboot oficial de la versión **exacta** instalada en el teléfono; o
   - leerlo del propio teléfono, lo que requiere root o un recovery ya en marcha.
   No se usa un kernel compilado desde fuente: en recovery-in-boot ese kernel también arranca Android, y si no coincide con los módulos de vendor o con `vendor_boot` puede dejar Android sin Wi-Fi o audio, o sin arrancar.
2. **Blobs de cifrado sin extraer** (26 ficheros, `proprietary-files.txt`). Se pueden sacar del teléfono por ADB (`/vendor` se puede leer sin root) o del volcado público. Bajarlos del volcado requiere autorización expresa.
3. **Sin hardware conectado.** Todo lo marcado [PEND] en `HARDWARE.md` sigue sin confirmar.

## Riesgos técnicos

- **Firmware distinto del de referencia.** Los blobs y el kernel deben coincidir con el firmware instalado: MIUI 13, MIUI 14 o una ROM custom tienen keymaster y kernel distintos. Si un usuario lleva otro firmware, el descifrado puede fallar. Mitigación: extraer siempre del propio teléfono (`--adb`).
- **Cabecera de boot y tamaños** proceden de OrangeFox. Si la cabecera real no fuera v3, `extract-stock-kernel.sh` aborta.
- **`odm` y `mi_ext`.** El fstab stock lista `mi_ext` pero no `odm`, y OFox lista `odm`. Hay que confirmarlo con `lpdump`.
- **`overrideprops.sh` eliminado.** OFox ponía a cero las fechas de build para esquivar el anti-rollback de OTA (`FOX_BUGGED_AOSP_ARB_WORKAROUND`). Si la instalación de OTAs desde AERA lo necesitara, se tratará como un cambio aparte y documentado.
- **Ramdisk en gzip.** LZ4 reduciría el tamaño, pero antes hay que confirmar `CONFIG_RD_LZ4` en el kernel stock (`extract-ikconfig`).
- **SELinux.** No se fuerza el modo permisivo por cmdline. En header v3 la cmdline viene de `vendor_boot`, y el recovery corre en el dominio `recovery`.

## Funciones fuera de la primera versión

- Vibración (`AERA_NO_HAPTICS`): falta incluir los blobs AIDL de `vendor.qti.hardware.vibrator`.
- Wi-Fi: requiere `qca_cld3_wlan.ko` (que debe coincidir con el kernel stock), el firmware de la partición modem y la configuración de `wpa_supplicant`.
- Aceleración GPU para LVGL: no está configurada, se usa el renderizado por software.
- Audio y redes móviles: fuera de alcance.
- Plugins (SSH/SFTP, MCP Bridge, AI Diagnostics): etapa 2, no se implementan.

## Entorno de build

- El volumen NTFS `/mnt/2E6421A46421702F` tiene una entrada corrupta (`aera_source/aera.ext4`) que dejó un `fallocate` fallido de ntfs3. Se repara con `chkdsk /f` desde Windows. No afecta a `aera_src.ext4`.
- La interfaz ethernet `enp129s0` obtiene IP por DHCP pero no recibe puerta de enlace, así que el tráfico sale por Wi-Fi.
