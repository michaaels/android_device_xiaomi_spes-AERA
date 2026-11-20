# Problemas conocidos y pendientes

## Bloqueos resueltos (2026-11-20)

- **Kernel**: se extrajo del `boot.img` del firmware instalado (EvolutionX 16.0 11.10, Linux 4.19.325-cip132-st16-Cherry). La trazabilidad está en `prebuilt/kernel.info`.
- **Blobs**: los 33 ficheros salen de la partición `vendor` de ese mismo firmware (`vendor.img` extraído de `payload.bin`, con el hash verificado). Los checksums están en `tools/blobs.sha256`.

## Pendientes

1. **Sin hardware conectado**: quedan sin confirmar los puntos [PEND] de `HARDWARE.md` y toda la matriz de pruebas en dispositivo.
2. **Build sin ejecutar**: espera a que termine `repo sync`.

## Riesgos técnicos

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
- La ethernet `enp129s0` no recibe puerta de enlace por DHCP, así que el tráfico sale por Wi-Fi.
