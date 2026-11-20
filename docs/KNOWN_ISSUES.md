# Problemas conocidos y pendientes

## Bloqueos resueltos (2026-11-20)

- **Kernel**: se extrajo del `boot.img` del firmware instalado (EvolutionX 16.0 11.10, Linux 4.19.325-cip132-st16-Cherry). La trazabilidad está en `prebuilt/kernel.info`.
- **Blobs**: los 33 ficheros salen de la partición `vendor` de ese mismo firmware (`vendor.img` extraído de `payload.bin`, con el hash verificado). Los checksums están en `tools/blobs.sha256`.

## Pendientes

1. **Sin hardware conectado**: quedan sin confirmar los puntos [PEND] de `HARDWARE.md` y toda la matriz de pruebas en dispositivo.
2. **El build ya funciona** (incremental, `EXIT 0`). Falta confirmar un build limpio completo sin errores.

## Riesgos técnicos

- **⚠️ No flashear `boot.img` tal cual para arrancar Android.** La cabecera declara `os_version 99.87.36` y `os_patch_level 2099-12`, porque `PLATFORM_*` lo exige el descifrado en recovery; el `boot` de EvolutionX declara 16.0.0 / 2026-08. Si Android arranca con esta cabecera, el bootloader pasa ese nivel de parche al TEE y el Keymaster de Android puede actualizar sus claves de forma permanente. Volver al boot original dejaría entonces `/data` sin poder descifrarse. En recovery no ocurre: el vold de AERA solo escribe las claves actualizadas en `/tmp` (`system/vold/KeyStorage.cpp`). La instalación permanente solo debe hacerse con el repack de AERA sobre el `boot` actual, que conserva la cabecera original. Que el repack conserve la cabecera está **[PEND]** de verificar.

- **La imagen depende del firmware.** El kernel y los blobs son de EvolutionX 11.10. Con MIUI o con otra ROM, el descifrado puede fallar y el kernel no corresponde. Al cambiar de firmware hay que regenerarlos con `tools/extract-stock-kernel.sh` y `tools/extract-files.sh`.
- **Librerías AOSP del ramdisk.** Los blobs necesitan `android.hardware.keymaster@4.0/4.1`, `android.hardware.gatekeeper@1.0`, `android.hardware.boot@1.0/1.1/1.2`, libbinder, libhidlbase, libxml2, libcrypto, etc. Se supone que el build de AERA los incluye en el ramdisk; se comprobará en la imagen generada.
- **Variante.** No está confirmado que EvolutionX exponga `ro.boot.product.hardware.sku`. Si no lo hace, el script deja los valores del build (spes).
- **`odm` / `mi_ext`.** EvolutionX no tiene ninguna de las dos. `mi_ext` se queda en el fstab con `nofail` para quien use MIUI.
- **`overrideprops.sh` (OFox) eliminado.** OFox lo usaba para esquivar el anti-rollback de OTA. Si hiciera falta, irá como un cambio aparte y documentado.
- **SELinux.** No se fuerza el modo permisivo. La cmdline de `vendor_boot` [EVOX] no incluye `androidboot.selinux`.

## Funciones fuera de la primera versión

- Vibración (`AERA_NO_HAPTICS`): hay que incluir el servicio AIDL `vendor.qti.hardware.vibrator` de EvolutionX.
- Wi-Fi: el driver está integrado en el kernel. Faltan el firmware `qca_cld`, la configuración de `wpa_supplicant` y `AERA_ENABLE_WLAN`.
- Aceleración GPU para LVGL: se usa renderizado por software.
- Audio y redes móviles: fuera de alcance.
- Plugins (SSH/SFTP, MCP Bridge, AI Diagnostics): etapa 2, no se implementan.

## Entorno de build

- El volumen NTFS `/mnt/2E6421A46421702F` tiene una entrada corrupta (`aera_source/aera.ext4`) que dejó un `fallocate` fallido de ntfs3. Se repara con `chkdsk /f` desde Windows.
- Ethernet `enp129s0` (host): a veces NetworkManager no instala las rutas IPv4 aunque el DHCP sí entrega la puerta de enlace (`routers = 192.168.100.1`). Ocurre cuando la concesión llega después de que la conexión ya figura como activada (`acd pending`). Sin ruta por defecto ni ruta `/24` en `enp129s0`, el IPv4 sale por Wi-Fi; el IPv6 no se ve afectado. Se comprueba con `ip route get 1.1.1.1`. `nmcli device reapply` no basta; se corrige reactivando la conexión con `nmcli con up "Conexión cableada 1"`. Puede repetirse tras reiniciar o reconectar el cable (verificado el 2026-11-20).
