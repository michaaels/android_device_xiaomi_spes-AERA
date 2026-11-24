# Datos móviles en AERA para spes / spesn: cómo funcionan

Documento técnico del camino de datos móviles del port de AERA Recovery 16.0
para el Xiaomi Redmi Note 11 (spes / spesn, SM6225) con el kernel downstream
de stock (Linux 4.19.325-cip132-st16-Cherry, `BoardConfig.mk:44-56`). Está
pensado para comprobar qué parte de este trabajo sirve en postmarketOS.

Todo lo que sigue sale del código y de los registros del repositorio. Las
referencias `archivo:línea` apuntan al estado de la rama `port/spes-bringup` en
el commit `123f8d7`. Lo que no se ha probado se marca **[sin verificar]**.

Resumen del estado (`docs/TESTING.md:90-92`, `docs/KNOWN_ISSUES.md:69-71`):

- Funciona: SIM 1 de Claro Ecuador, 4G, APN `ba.amx` detectado automáticamente,
  IPv4 por `rmnet_aera`, ping a 8.8.8.8 3/3 (~99 ms), DNS del operador,
  HTTP/HTTPS y tienda de plugins con el Wi-Fi apagado. Nombre del operador
  "CLARO EC". Tres ciclos seguidos de conectar/desconectar. Disponible tras un
  arranque limpio (builds 30, 31 y 32).
- Dual SIM (dos SIM de Claro con datos): conecta por la SIM 1 y por la SIM 2,
  cada una con su IP privada, y cambia entre ellas sin reiniciar (build 40,
  pasos 6 y 6b de la sección 2).
- Solo internet: ni llamadas ni SMS.

---

## 1. Arquitectura de punta a punta

### 1.1 Piezas

| Pieza | Qué es | De dónde sale en AERA/spes |
|---|---|---|
| MPSS (subsistema `modem`) | DSP del módem; en SM6225 también ejecuta el firmware WLAN (`icnss`) | Imágenes `modem.*` de la partición `modem$SLOT`, montada en solo lectura en `/firmware` (`spes-wlan-up.sh:78-84`) |
| `ipa_fws` | Firmware del acelerador IPA/GSI (camino de datos AP↔módem) | `/mnt/vendor_stock/firmware/ipa_fws.*`, copiado a `/vendor/firmware` (RAM) y cargado con `echo 1 > /dev/ipa` (`spes-wlan-up.sh:63-76`) |
| `qrtr-ns` | Name service de QRTR (descubrimiento de servicios QMI) | Binario stock del vendor, ejecutado desde la copia en RAM (`init.recovery.wifi.rc:45-50`) |
| `pd-mapper` | Servidor de dominios de protección (PD), necesario para que arranquen `wlan_pd` y los PD del módem | Ídem (`init.recovery.wifi.rc:52-57`) |
| `rmt_storage` | Sirve al módem las particiones EFS (`modemst1`, `modemst2`, `fsg`, `fsc`) | Ídem (`init.recovery.wifi.rc:59-64`); las particiones son loops sobre copias en RAM (`spes-wlan-up.sh:89-101`) |
| `tftp_server` | Sirve al módem ficheros de `/vendor/rfs` → `persist/rfs`, `hlos_rfs`, firmware | Ídem (`init.recovery.wifi.rc:66-71`); `persist` en tmpfs (`spes-wlan-up.sh:103-129`) |
| `cnss-daemon` | Daemon de la plataforma WLAN | Ídem (`init.recovery.wifi.rc:79-84`). Para los datos móviles no se ha comprobado si hace falta **[sin verificar]** |
| `spes-modem-hold.sh` | Mantiene abierto `/dev/subsys_modem` (voto `subsystem_get`), lo que arranca el MPSS | `recovery/root/system/bin/spes-modem-hold.sh:8-11`, servicio en `init.recovery.wifi.rc:73-77` |
| `rmnet_ipa0` | Netdev del driver IPA downstream (`rmnet_ipa3`), aparece al cargar `ipa_fws` | Kernel de stock |
| `rmnet_aera` | Enlace `rmnet` (mux id 1) sobre `rmnet_ipa0`; lleva el tráfico IP | Lo crea el proveedor por netlink (`daemon.cpp:149-174`) |
| `aera-cellular-provider` | Daemon de control (QMI sobre QRTR, rmnet, IP, rutas, DNS) | `mobile_data/daemon.cpp`, compilado si `AERA_ENABLE_MOBILE_DATA=1` (`vendorsetup.sh:54-56`, `device.mk:41-44`, `mobile_data/Android.bp:8-19`) |

**Por qué los daemons corren desde la RAM.** AERA para todos los procesos que
usan particiones dinámicas antes de desmapear `super` (sideload, flasheo). Si
`qrtr-ns` o `pd-mapper` mueren, el root PD del módem se cae y se pierde el WLAN.
Por eso `spes-wlan-up.sh` copia los cinco binarios y sus 18 librerías a
`/tmp/spes_vendor` (`spes-wlan-up.sh:10-12`, `:37-61`). Es un problema propio
de AERA (`docs/KNOWN_ISSUES.md:46`).

**Sandbox.** Nada de lo que escribe el módem llega a una partición real
(`spes-wlan-up.sh:14-19`):

- EFS: los enlaces `by-name` de `modemst1/modemst2/fsg/fsc` (en `/dev`, que es
  tmpfs) se redirigen a loops sobre copias `dd` en `/tmp/spes_efs`
  (`spes-wlan-up.sh:89-101`).
- `persist/rfs` y `hlos_rfs`: copias en un tmpfs montado en
  `/mnt/vendor/persist` (`spes-wlan-up.sh:103-129`).
- `/data/vendor/{wifi,tombstones}`: tmpfs, o `/data/vendor` entero en tmpfs, y
  nunca se crean directorios en un `userdata` montado (`spes-wlan-up.sh:131-151`).

Verificado: el SHA-256 de `modemst1/2`, `fsg`, `fsc` y `persist` es idéntico
antes y después de una sesión en la que el módem escribió EFS
(`docs/evidence/hw-wifi.txt:42-56`, `docs/TESTING.md:96`).

### 1.2 Orden de arranque

El módem se comparte con el Wi-Fi: la misma preparación sirve para los dos y
el módem queda encendido hasta el reinicio. Desactivar los datos solo cierra
la sesión (`spes_platform.hpp:5-14`).

1. El proveedor arranca con el recovery. Comprueba `InRecovery()`
   (`daemon.cpp:634`, `spes_platform.hpp:92-94`) y publica `available` según
   `Capability()` (`daemon.cpp:646-647`). `Capability()` solo mira que exista
   el subsistema `modem` en `/sys/bus/msm_subsys/devices`, que se pueda leer
   `/dev/subsys_modem`, que el script de preparación sea ejecutable y que el
   kernel acepte un socket `AF_QIPCRTR` (42). **No** mira `rmnet_ipa0`
   (`spes_platform.hpp:100-112`).
2. El usuario pulsa conectar: `Connect()` → `spes::Start()` (`daemon.cpp:450-455`).
3. Si `spes.wlan.prep` no vale `1`, `Start()` lo vacía y pone
   `spes.modem.up=1` (`spes_platform.hpp:126-128`).
4. init reacciona a `spes.modem.up=1`: arranca `spes-wlan-prep` y vuelve a
   poner la propiedad a `0` (`init.recovery.wifi.rc:21-25`). A diferencia de
   `sys.aera.wlan.up`, no arranca `wpa_supplicant` (`init.recovery.wifi.rc:12-19`).
5. `spes-wlan-up.sh`, en este orden:
   1. monta `vendor$SLOT` en solo lectura en `/mnt/vendor_stock` (`:29-35`);
   2. copia los daemons y librerías a `/tmp/spes_vendor` (`:37-61`);
   3. carga `ipa_fws` si el subsistema `ipa_fws` no está `ONLINE` (`:63-76`).
      Aquí aparece `rmnet_ipa0`;
   4. monta la partición `modem$SLOT` (vfat, solo lectura) en `/firmware` y
      crea `/vendor/firmware_mnt` y `/vendor/rfs` (`:78-87`);
   5. sandbox de EFS (`:89-101`), de `persist` (`:103-129`) y de `/data` (`:131-151`);
   6. pone `spes.wlan.prep=1` (o `fail` si algo falla) (`:153-154`, `:22`).
6. `Start()` espera hasta 60 s a que `spes.wlan.prep` sea `1` o `fail`
   (`spes_platform.hpp:129-132`).
7. init reacciona a `spes.wlan.prep=1` arrancando `spes-qrtr-ns`,
   `spes-pd-mapper`, `spes-rmt-storage`, `spes-tftp-server`, `spes-cnss-daemon`
   y `spes-modem-hold` (`init.recovery.wifi.rc:27-36`).
8. `spes-modem-hold.sh` espera 2 s (para que `rmt_storage`/`tftp_server` se
   registren, porque el módem pide EFS nada más salir del reset), abre
   `/dev/subsys_modem` y lo mantiene abierto (`spes-modem-hold.sh:5-11`). El
   `pm-service` de stock no puede registrarse en el `vndservicemanager` del
   recovery; mantener el nodo abierto es lo que hace por dentro
   (`init.recovery.wifi.rc:33-35`, `docs/KNOWN_ISSUES.md:40`).
9. `Start()` espera hasta 60 s a `Running()`: subsistema `modem` en `ONLINE` e
   `init.svc.spes-modem-hold=running` (`spes_platform.hpp:96-98`, `:134`).
10. `Start()` espera hasta 10 s a que exista `rmnet_ipa0` (`spes_platform.hpp:135-136`).

Tiempos medidos con el Wi-Fi (misma preparación; `docs/evidence/hw-wifi.txt:4-24`):
preparación 0,82 s (IPA cargada en ~0,2 s), módem fuera de reset 2,6 s
después, `wlan_pd` arriba en ~1 s más. No hay una traza equivalente guardada
para los datos móviles.

---

## 2. Plano de control: QMI sobre QRTR

### 2.1 Transporte

- Socket `AF_QIPCRTR` (42), `SOCK_DGRAM` (`qmi.hpp:51-55`).
- Descubrimiento: se envía `QRTR_TYPE_NEW_LOOKUP` (10) al puerto de control
  `0xfffffffe` del nodo local y se recogen las respuestas `NEW_SERVER` (4)
  hasta la de fin, con todo a cero (`qmi.hpp:80-95`). Se descartan los
  servicios del nodo local, para no confundir un ayudante WLAN que anuncie DMS
  con el módem (`qmi.hpp:92-93`).
- `Find()` toma el servicio pedido con `instance >> 8 == 0` y, salvo NAS, en el
  mismo nodo que NAS (`daemon.cpp:341-344`). El descubrimiento se reintenta
  hasta 30 veces hasta que aparecen NAS, DMS y WDS (`daemon.cpp:459-464`).
- Trama QMI: `flags(0) txn(u16) msg(u16) len(u16) TLVs` y la respuesta se
  empareja por tipo 2, txn y mensaje. El TLV 0x02 es el resultado; si el
  código no es 0 se lanza `QmiError` (`qmi.hpp:100-130`).

### 2.2 Servicios usados

| Servicio | ID | Mensajes |
|---|---|---|
| WDS (datos) | 1 | 0x20 Start Network, 0x21 Stop Network, 0x22 Get Packet Service Status, 0x2D Get Runtime Settings, 0x4D Set IP Family, 0x85 Get LTE Attach Parameters, 0xA2 Bind Mux Data Port, 0xAF Bind Subscription, 0xB0 consulta de la suscripción vinculada |
| DMS | 2 | 0x2E Set Operating Mode |
| NAS | 3 | 0x24 Get Serving System, 0x45 vinculación de suscripción, 0x4D Get System Info, 0x4F Get Signal Info |
| UIM | 11 | 0x2F Get Card Status, 0x47 Get Slots Status (ICCID), 0x26 Verify PIN |
| WDA | 26 | 0x20 Set Data Format |
| DPM | 47 | 0x20 Open Port |

(Los IDs de servicio salen de las llamadas a `Find()` en `daemon.cpp:461`,
`:463-465`, `:482`, `:500`, `:503`.)

### 2.3 Secuencia exacta de `Connect()`

1. **Lease**: bloqueo compartido sobre el lease de AERA, para no conectar
   durante una operación de almacenamiento (`daemon.cpp:451-452`). Propio de AERA.
2. **Módem arriba**: `spes::Start()` (sección 1.2) (`daemon.cpp:455`).
3. **Descubrimiento QRTR** de NAS (3), DMS (2) y WDS (1) (`daemon.cpp:457-464`).
4. **DMS 0x2E Set Operating Mode**, TLV 0x01 = `0` (online) (`daemon.cpp:465`). Un módem recién arrancado anuncia DMS antes de aceptar esta orden y responde `QMI_ERR_DEVICE_NOT_READY` (52) durante unos segundos; el proveedor la reintenta cada 0,5 s, hasta unos 20 s, solo con ese error (`daemon.cpp:465-472`).
5. **Selección de la SIM de datos** (solo si la UI pide la SIM 1 o 2; `0` = la
   que ya tenga el módem) (`daemon.cpp:475-490`):
   - WDS 0xAF con TLV 0x01 = suscripción (u32);
   - WDS 0xB0 y se comprueba que el TLV 0x10 devuelva la misma suscripción;
   - NAS 0x45 con TLV 0x01 = suscripción − 1 (u8), porque la vinculación es
     por cliente y debe coincidir con la de WDS.
   - Con suscripción `0` solo se lee 0xB0 para saber cuál está activa.
6. **Esperar a la SIM** (`WaitForSim`, `daemon.cpp:253-335`):
   - antes, **rellenar las sesiones de aprovisionamiento vacías**
     (`ProvisionSims`, `daemon.cpp:222-234`; `sim_session.hpp`). El módem solo
     mete una aplicación SIM/USIM en una sesión (GW primaria o secundaria)
     cuando el *stack* de radio de Android se lo pide con UIM 0x38 *Change
     Provisioning Session*, y recuerda lo último que pidió Android. Sin ese
     *stack*, la SIM 2 (o una ranura que Android dejó inactiva) queda
     `detected` sin sesión. Si la sesión primaria está vacía, el módem no se
     registra en **ninguna** red (las dos SIM salen sin servicio). El
     proveedor lee UIM 0x2F (índices de sesión en los bytes 0-1 y 4-5 del TLV
     0x10 y el AID de cada aplicación) y, si hace falta, manda UIM 0x38 con
     TLV 0x01 = {tipo de sesión: 0 primaria, 2 secundaria; 1 = activar} y TLV
     0x10 = {ranura, longitud del AID, AID}. La primaria va a la ranura 1 y la
     secundaria a la 2, salvo que la otra sesión ya use esa ranura. La
     secundaria solo se rellena si se pidió la suscripción 2. Verificado en
     hardware (build 40). El cambio vive en la RAM del módem (EFS en RAM, sección 1).
   - UIM 0x47 → ICCID por ranura; se guarda solo su SHA-256 (`daemon.cpp:59-65`,
     `:212-217`, `sim.hpp:51-64`);
   - UIM 0x2F cada 500 ms → estado de tarjeta y de aplicación (`sim.hpp:14-38`),
     traducido a `ready`, `pin_required`, `puk_required`, `blocked`, `absent`
     o `initializing` (`sim.hpp:39-47`);
   - con `pin_required`, la UI puede mandar un PIN (`daemon.cpp:660-678`) y se
     verifica con UIM 0x26 una sola vez, sin reenviarlo nunca tras un timeout
     (`daemon.cpp:309-332`). **[sin verificar en hardware]**
6b. **SIM de datos del módem (DDS)** (`SelectDataSubscription`,
   `daemon.cpp:236-252`), solo si la UI pide la SIM 1 o 2. Los datos salen
   siempre por la *default data subscription* del módem, esté WDS vinculado a
   la suscripción que esté: sin esto, con la SIM 2 elegida, la llamada salía
   por la SIM 1 (misma IP privada). Android la cambia con **DSD 0x4E *Switch
   DDS***, TLV 0x01 = suscripción (u32: 1 o 2), como hace qcril para
   `setPreferredDataModem` (`libril-qc-hal-qmi.so`,
   `DSDModemEndPointModule::qmiDDSSwitchRequest`). El cambio es asíncrono y
   una llamada iniciada antes de que termine sale por la SIM anterior, así
   que se espera a que **DSD 0x4F *Get Current DDS*** (TLV 0x10, u32) dé la
   suscripción pedida (hasta 10 s). Si el módem no tiene DSD (un solo SIM),
   se omite. Verificado: SIM 2 → `100.72.198.81`, SIM 1 → `10.91.199.180`,
   SIM 2 → `100.72.198.81`, con ping en cada cambio (build 40).
7. **Registro**: NAS 0x24 Get Serving System hasta 60 veces cada 750 ms. Se da
   por registrado cuando el TLV 0x01 tiene `registration_state == 1` y
   `ps_attach_state == 1` (bytes 0 y 2). El error 74 (`INFO_UNAVAILABLE`) se
   tolera, porque NAS puede publicarse antes de tener la suscripción
   (`daemon.cpp:493-507`).
8. **IPA: endpoint y tuberías** (ioctl, sección 3.2): `GET_EPID` (3) y
   `GET_EP_PAIR` (0x10) sobre `rmnet_ipa0` (`daemon.cpp:508`).
9. **DPM 0x20 Open Port**, TLV 0x11 (hardware data ports): cuenta 1,
   `ep_type=4` (embedded), `iface_id` = EPID, y las dos tuberías de
   `GET_EP_PAIR` (`daemon.cpp:509-511`).
10. **WDA 0x20 Set Data Format** (sección 3.3) y comprobación de lo negociado
    (`daemon.cpp:512-522`).
11. **WDS 0xA2 Bind Mux Data Port**: TLV 0x10 = `{ep_type 4, iface_id}`,
    TLV 0x11 = mux id `1` (`daemon.cpp:523`).
12. **WDS 0x4D Set IP Family**: `4` (IPv4) (`daemon.cpp:524`).
13. **APN**: si la UI no da ninguno, WDS 0x85 Get LTE Attach Parameters y se usa
    el TLV 0x10 si solo tiene `[A-Za-z0-9.-_]` y ≤ 100 bytes. Con Claro EC
    devuelve `ba.amx` (`daemon.cpp:525-538`, `docs/TESTING.md:92`).
14. **WDS 0x20 Start Network**: TLV 0x14 = APN, TLV 0x19 = `4` (IPv4), timeout
    45 s. El TLV 0x01 de la respuesta es el *packet data handle*
    (`daemon.cpp:539-542`). Si falla, el error incluye el TLV 0x11
    (*call end reason*) (`qmi.hpp:123-126`).
15. **WDS 0x2D Get Runtime Settings**, máscara `0x2310` (DNS, IP, gateway, MTU).
    TLVs leídos: 0x1E IPv4, 0x20 gateway, 0x21 máscara, 0x15/0x16 DNS 1/2,
    0x29 MTU. Faltan IP, gateway o DNS 1 → error; sin DNS 2 → se repite el
    DNS 1; MTU por defecto 1500, válida entre 576 y 9000 (`daemon.cpp:543-549`).
16. Plano de datos e IP (sección 3) (`daemon.cpp:550-559`).
17. **Bucle conectado** cada ~2,5 s (`daemon.cpp:565-572`): WDS 0x22 (si el
    TLV 0x01 no es `2` = conectado → "The mobile network disconnected") y
    `Signal()`: NAS 0x24 (registro, RAT y operador), NAS 0x4D (TLV 0x4A, NR
    disponible) y NAS 0x4F (dBm: 0x14 RSRP en LTE, 0x17 en NR, 0x13 WCDMA,
    0x12 GSM) (`daemon.cpp:406-449`).

### 2.4 Desconexión (`Stop()`, `daemon.cpp:574-585`)

1. Para el hilo de rutas/DNS.
2. **WDS 0x21 Stop Network** con TLV 0x01 = handle.
3. Restaura `/etc/resolv.conf` y `net.dns1/2` (solo si siguen siendo los suyos)
   (`daemon.cpp:380-391`).
4. `ip link del rmnet_aera` (al borrar el enlace se va su ruta).
5. Cierra los clientes QMI y el lease.

El módem **no** se apaga (sigue compartido con el Wi-Fi) y las tuberías IPA no
se desmontan (sección 3.4). Si la sesión ya había llegado a conectarse y se
cae, `Worker()` reintenta con espera exponencial de 5 a 60 s
(`daemon.cpp:588-604`).

### 2.5 Nombre del operador: TLV 0x12 de NAS y GSM 7 bits

`Signal()` toma el TLV 0x12 (*current PLMN*) de NAS 0x24
(`daemon.cpp:446-447`). Formato: `mcc(u16) mnc(u16) len(u8) descripción`
(`plmn_name.hpp:51-53`). El TLV no trae indicador de codificación: unos módems
mandan ASCII y otros texto GSM 03.38 de 7 bits empaquetado. El SM6225 con
Claro EC manda `43 66 50 fa 04 15 87` (`plmn_name.hpp:4-8`).

`PlmnName()` deja el ASCII imprimible tal cual y, si no lo es, desempaqueta
septetos LSB primero (`plmn_name.hpp:32-47`), los pasa por el alfabeto básico
GSM (`plmn_name.hpp:22-30`) y quita el relleno final (`@` = septeto 0, o CR).
Si queda algún carácter sin equivalente, no muestra nombre en vez de basura
(`plmn_name.hpp:55-58`).

Comprobación a mano: `0x43 = 1000011` → `C`; `(0x43>>7)|(0x66<<1)&0x7f =
0x4C` → `L`; … el resultado es `CLARO EC` (8 septetos en 7 bytes). Antes salía
"CFP◆◆" (`docs/KNOWN_ISSUES.md:70`).

---

## 3. Plano de datos

### 3.1 Topología

```
  app ──► rmnet_aera (IPv4, MTU de WDS)      enlace rmnet, mux_id 1, flags 0x1
              │  QMAP v1 (cabecera MAP de 4 bytes, sin trailer de checksum)
              ▼
          rmnet_ipa0                          netdev del driver IPA downstream (rmnet_ipa3)
              │  tuberías WAN de IPA/GSI (EPID + par de tuberías)
              ▼
          IPA (firmware ipa_fws) ◄──► MPSS ◄──► red 4G
```

### 3.2 Ioctls de `rmnet_ipa0` (`RMNET_IOCTL_EXTENDED` = `0x89FD`)

`Ipa()` envía un `std::array<uint32_t,6>` por `ifr_data` (`daemon.cpp:133-142`).
Comandos usados:

| Cmd | Nombre (msm_rmnet.h) | Uso |
|---|---|---|
| 3 | `GET_EPID` | ID del endpoint para DPM, WDA y WDS 0xA2 (`daemon.cpp:508`) |
| 0x10 | `GET_EP_PAIR` | Tuberías consumidor/productor para DPM (`daemon.cpp:508-511`) |
| 6 | `SET_EGRESS_DATA_FORMAT` | `0x0e` = MAP \| AGGREGATION \| MUXING (`daemon.cpp:554`) |
| 7 | `SET_INGRESS_DATA_FORMAT` | `0x2e` = MAP \| DEAGGREGATION \| DEMUXING \| AGG_DATA, con 16384 bytes y 32 datagramas (`daemon.cpp:554`) |
| 5 | `ADD_MUX_CHANNEL` | mux id 1 → `rmnet_aera` (`daemon.cpp:557`) |

Los errores nombran el comando y el `errno` (`daemon.cpp:138-140`).

### 3.3 Formato de datos (WDA) y `DataFormat{5, 0x1, 0x0e, 0x2e}`

`spes::kDataFormat` (`spes_platform.hpp:37-47`):

| Campo | Valor | Dónde se usa |
|---|---|---|
| `aggregation` | `5` = QMAP | TLV 0x12 (UL) y 0x13 (DL) de WDA 0x20 |
| `rmnet_flags` | `0x00000001` = `RMNET_FLAGS_INGRESS_DEAGGREGATION` | `IFLA_RMNET_FLAGS` del enlace (`daemon.cpp:156`) |
| `ipa_egress` | `0x0e` | ioctl 6 |
| `ipa_ingress` | `0x2e` | ioctl 7 |

Petición WDA 0x20 (`daemon.cpp:513-516`):

| TLV | Valor | Significado |
|---|---|---|
| 0x10 | `0` (u8) | formato QoS: sin cabecera QoS |
| 0x11 | `2` | protocolo de enlace: raw IP |
| 0x12 | `5` | agregación UL: QMAP |
| 0x13 | `5` | agregación DL: QMAP |
| 0x15 | `32` | DL: máx. datagramas por agregado |
| 0x16 | `16384` | DL: tamaño máx. del agregado |
| 0x17 | `{4, EPID}` | endpoint: embedded + interfaz |
| 0x1B | `32` | UL: máx. datagramas |
| 0x1C | `16384` | UL: tamaño máx. |

Después se exige que la respuesta repita 0x11 = 2, 0x12 = 5 y 0x13 = 5; si no,
falla con `Unsupported modem data format (field N=valor)`, donde N va en
decimal (18 = TLV 0x12, UL) (`daemon.cpp:517-522`).

**Por qué no QMAPv5.** El proveedor oficial (SM8850) usa QMAPv5 (agregación
`9`) con offload de checksum. El módem del SM6225 solo negocia QMAP v1: si se
pide 9, contesta 5, el chequeo falla en el campo 18 y, además, QMAP v1 no lleva
el trailer de checksum MAPv5, así que los flags de rmnet e IPA de v5 tampoco
valen (`spes_platform.hpp:37-40`, `docs/KNOWN_ISSUES.md:69`). En la depuración
también se vio el campo 18 = 0 (agregación UL desactivada) con otras
combinaciones, pero de eso no hay registro en `docs/evidence`. El valor válido
es el que está en `kDataFormat`, confirmado en hardware (`spes_platform.hpp:40`).

### 3.4 Las tuberías IPA se configuran una vez por arranque

`rmnet_ipa3` de este 4.19 monta las tuberías WAN en el primer
`SET_EGRESS/INGRESS_DATA_FORMAT` y rechaza cualquier llamada posterior con
`EINVAL`. Las tuberías no se desmontan al desconectar. Por eso la segunda
conexión fallaba con "command 6, errno 22" (`spes_platform.hpp:49-53`,
commit `8732bc8`).

Solución: los ioctls 6 y 7 solo se envían si no existe
`/tmp/aera-cellular/ipa-format-configured`, y después se crea esa marca
(`daemon.cpp:553-556`, `spes_platform.hpp:53-58`). Está en RAM, así que
desaparece al reiniciar, igual que las tuberías. `ADD_MUX_CHANNEL` (5) sí se
envía en cada conexión (`daemon.cpp:557`). Verificado: tres ciclos seguidos
(`docs/TESTING.md:91`).

### 3.5 Enlace rmnet, IP, rutas y DNS (`daemon.cpp:550-559`)

1. `CreateLink()`: `RTM_NEWLINK` con `IFLA_LINK = rmnet_ipa0`,
   `IFLA_IFNAME = rmnet_aera`, `IFLA_LINKINFO{kind "rmnet", data{IFLA_RMNET_MUX_ID=1,
   IFLA_RMNET_FLAGS={0x1, 0xffffffff}}}` (`daemon.cpp:149-174`). Equivale a
   `ip link add link rmnet_ipa0 name rmnet_aera type rmnet mux_id 1`.
2. `ip link set rmnet_ipa0 up`; `ip link set rmnet_aera mtu <MTU> up`.
3. `ip addr add <IP>/<prefijo de la máscara> dev rmnet_aera` (`daemon.cpp:180-185`).
4. Ioctls 6/7 (solo la primera vez) y 5 (sección 3.4).
5. `ip route add default via <gateway> dev rmnet_aera metric 900`
   (`daemon.cpp:558`). La métrica alta deja preferida la ruta del Wi-Fi.
6. DNS (`daemon.cpp:345-379`): si `wlan0` tiene portadora, IP y ruta por
   defecto, se usan los DNS del Wi-Fi. Si no, se borra cualquier ruta por
   defecto de un `wlan0` sin portadora, se escribe `/etc/resolv.conf` con los
   DNS del operador (solo si está en tmpfs/ramfs) y `net.dns1/2`. Un hilo lo
   vuelve a evaluar cada 250 ms (`daemon.cpp:392-405`).

Todo es IPv4: la familia es 4 en WDS 0x4D y en Start Network
(`daemon.cpp:524`, `:531`). **No hay IPv6.**

---

## 4. Problemas encontrados y cómo se resolvieron

| # | Síntoma | Causa | Solución | Dónde |
|---|---|---|---|---|
| 1 | El proveedor oficial nunca arrancaba | Exige `ro.bootmode=recovery`, pero en spes el recovery va en `boot` y el bootloader deja `ro.bootmode=unknown` | `InRecovery()` acepta también `init.svc.recovery=running`, que solo existe en la ramdisk del recovery | `spes_platform.hpp:88-94`, `daemon.cpp:8-9` |
| 2 | El oficial arranca el módem con remoteproc y sus propios ayudantes de RAM | En spes el MPSS ya lo levanta la pila Wi-Fi (el firmware WLAN corre en el módem) | Reutilizar esa preparación con `spes.modem.up`; el módem queda compartido | `spes_platform.hpp:5-14`, `init.recovery.wifi.rc:21-25` |
| 3 | `Unsupported modem data format (field 18=…)` | El SM6225 solo negocia QMAP v1 | `kDataFormat{5, 0x1, 0x0e, 0x2e}` | `spes_platform.hpp:37-47` |
| 4 | Nombre del operador ilegible ("CFP◆◆") | El TLV 0x12 de NAS viene en GSM 7 bits empaquetado | `plmn_name.hpp` | commit `8732bc8`, `docs/KNOWN_ISSUES.md:70` |
| 5 | La segunda conexión fallaba (ioctl 6, EINVAL) | `rmnet_ipa3` acepta los formatos IPA una sola vez por arranque | Marca en RAM `ipa-format-configured` | `spes_platform.hpp:49-58`, `daemon.cpp:553-556` |
| 6 | "No disponible" tras cada reinicio | `Capability()` exigía `rmnet_ipa0`, que solo aparece al cargar `ipa_fws`, después de arrancar el proveedor | El chequeo de `rmnet_ipa0` pasa a `Start()`, tras preparar el módem | `spes_platform.hpp:100-103`, `:135-136`, commit `123f8d7` |
| 7 | Textos sin traducir | La pantalla de datos no estaba en el catálogo de AERA | Parche `0007` (57 entradas en/es/zh) | commit `123f8d7` |
| 8 | Daemons parados por AERA tras sideload/flasheo → "Root PD crashed" | Corrían desde el `vendor` montado (partición dinámica) | Copia en RAM `/tmp/spes_vendor` | `spes-wlan-up.sh:10-12`, `docs/KNOWN_ISSUES.md:46` |
| 9 | El WLAN no probaba (`-EFAULT`, `ipa3_uc_reg_rdyCB bad parm`) | IPA sin firmware | Cargar `ipa_fws` con `echo 1 > /dev/ipa` | `spes-wlan-up.sh:63-76` |
| 10 | `pm-service` no se registra en recovery | No hay contextos de servicio del vendor en el `vndservicemanager` | Mantener abierto `/dev/subsys_modem` | `spes-modem-hold.sh`, `docs/KNOWN_ISSUES.md:40` |
| 11 | No se puede mostrar el número de teléfono | DMS Get MSISDN responde error 16 `NOT_PROVISIONED`; la SIM de Claro no lo guarda | Ninguna (es la SIM) | `docs/KNOWN_ISSUES.md:71` |
| 12 | Con los datos activados antes que el Wi-Fi: "QMI error 52 (request 46) [service 2]" | El módem lo arranca el proveedor y DMS aún no acepta *Set Operating Mode* (`DEVICE_NOT_READY`); con el Wi-Fi antes, el módem ya estaba listo | Reintento de DMS 0x2E solo con el error 52 | `daemon.cpp:465-472`, commit `978f985` |
| 13 | SIM 2: "The selected data SIM has no provisioning application"; luego, sin red en ninguna SIM | Sin el *stack* de radio de Android nadie rellena las sesiones de aprovisionamiento del módem | UIM 0x38 en las sesiones vacías (`ProvisionSims`) | `daemon.cpp:222-234`, `sim_session.hpp` |
| 14 | Con la SIM 2 elegida, los datos salían por la SIM 1 (misma IP privada) | Los datos siguen la DDS del módem, no la vinculación de WDS | DSD 0x4E *Switch DDS* y espera a DSD 0x4F (`SelectDataSubscription`) | `daemon.cpp:236-252` |

---

## 5. Aplicabilidad a postmarketOS

El port de pmOS para spes trabaja con dos kernels: el downstream Cherry
4.19.325 (el mismo que usa AERA) y mainline 7.2.9. Hay que leer cada fila
según el kernel.

Leyenda: **Tal cual** = se reutiliza sin cambios · **Equivalente** = en pmOS
hay otra pieza que hace lo mismo · **Referencia** = no se copia, pero el valor
medido sirve para validar · **No aplica**.

### 5.1 Arranque del módem

| Pieza AERA | Downstream 4.19 en pmOS | Mainline en pmOS |
|---|---|---|
| Firmware MPSS de `modem$SLOT` (vfat, ro) | Tal cual (el firmware lo carga PIL desde la ruta de firmware) | Equivalente: `remoteproc` `qcom_q6v5_mss`/`pas` con `firmware-name` en el DT (paquete de firmware o la partición montada) |
| `ipa_fws` + `echo 1 > /dev/ipa` | Tal cual. **Imprescindible**: sin él no hay `rmnet_ipa0` ni WLAN | Equivalente: driver `ipa`. Con `qcom,gsi-loader = "self"` el AP carga `ipa_fws.mdt` (se necesita en `/lib/firmware`); con `"modem"` lo carga el módem. Comprobar cuál corresponde a SM6225 en el DT del port |
| `/dev/subsys_modem` abierto (`spes-modem-hold.sh`) | Tal cual (el `spes-radio.sh` de pmOS ya lo hace) | Equivalente: `echo start > /sys/class/remoteproc/remoteprocN/state` (o automático al probar) |
| `qrtr-ns` (stock) | Equivalente: `qrtr-ns` de linux-msm/`qrtr` (en 4.19 el name service está en espacio de usuario) | Normalmente no hace falta: el name service está en el kernel desde 5.7 |
| `pd-mapper` (stock) | Equivalente: `pd-mapper` de linux-msm | Equivalente: `pd-mapper` en espacio de usuario o `qcom_pd_mapper` en el kernel (6.11+) |
| `rmt_storage` + EFS en loops de RAM | Equivalente: `rmtfs` (`-r -o <dir>`) con copias de EFS en RAM; el `spes-radio.sh` de pmOS ya lo hace así | Igual: `rmtfs` + `qcom,rmtfs-mem` |
| `tftp_server` + `persist` en tmpfs | Equivalente: `tqftpserv` | Igual |
| `cnss-daemon` | No aplica a los datos (es del WLAN). No se ha probado si los datos funcionan sin él **[sin verificar]** | No aplica (el WLAN mainline es `ath10k_snoc` y no lo usa) |
| Sandbox en RAM de EFS/`persist`/`/data` | Recomendable mientras se depura (no tocar EFS real); en un sistema instalado lo normal es que `rmtfs` escriba las particiones reales | Igual |
| Copia de daemons a `/tmp/spes_vendor` | No aplica: es solo por `QuiesceDynamicPartitionUsers` de AERA | No aplica |
| `spes.modem.up` / `spes.wlan.prep` | No aplica (propiedades de init de Android); el orden sí sirve de guía | No aplica |

### 5.2 Plano de control

| Pieza AERA | Downstream 4.19 | Mainline |
|---|---|---|
| QMI sobre `AF_QIPCRTR` (`qmi.hpp`) | Tal cual: `qmicli -d qrtr://0` y libqmi con QRTR hablan con los mismos servicios | Tal cual. pmOS ya usó `qmicli -d qrtr://0 --dms-get-mac-address` en 7.2.9 |
| Secuencia DMS online → SIM → NAS registro → DPM → WDA → WDS bind → Start Network → Runtime Settings | Referencia: con ModemManager la hace MM; a mano se replica con `qmicli` (sección 6.2) | Referencia: lo hace ModemManager (driver de puerto `ipa`) u oFono. Ojo al error 52 de DMS 0x2E nada más arrancar el módem (sección 4, fila 12) |
| `daemon.cpp` como programa | No aplica tal cual: depende de AERA (`aera_mobile/client.hpp`, propiedades de Android, `/sbin/busybox ip`, lease). La lógica sí se puede portar | No aplica (ModemManager) |
| Decodificación GSM 7 bits (`plmn_name.hpp`) | Referencia: ModemManager/libqmi deberían decodificar el TLV 0x12. Si `mmcli -m 0` muestra el operador como basura, este es el caso y la solución | Igual. El fichero es genérico y sin dependencias |
| `sim.hpp` (estados UIM, PIN) | Referencia; MM lo resuelve | Referencia |
| Dual SIM: sesiones UIM y DDS (`sim_session.hpp`, pasos 6 y 6b) | Útil sin el *stack* de radio de Android: con dos SIM, la segunda (o la que Android dejó inactiva) queda sin sesión y los datos siguen la DDS. Las sesiones se activan con `qmicli -d qrtr://0 --uim-change-provisioning-session=...`; el cambio de DDS es DSD 0x4E/0x4F, que libqmi no expone **[sin verificar en pmOS]** | Igual: depende del módem, no del kernel |

### 5.3 Plano de datos

| Pieza AERA | Downstream 4.19 | Mainline |
|---|---|---|
| `rmnet_ipa0` + ioctls `RMNET_IOCTL_EXTENDED` (3, 0x10, 5, 6, 7) | Tal cual, es la única forma con este driver. **ModemManager no conoce estos ioctls**, así que con 4.19 hace falta un ayudante propio (p. ej. portar `Connect()` sin la parte de AERA) | No aplica. El driver mainline `ipa` también crea `rmnet_ipa0`, pero configura las tuberías él mismo (y con su propio intercambio QMI con el módem); no hay ioctls |
| Formatos IPA una vez por arranque (marca `ipa-format-configured`, EINVAL al repetir el ioctl 6) | Tal cual: cualquier ayudante debe enviar 6/7 una sola vez por arranque | No aplica |
| DPM 0x20 Open Port (`ep_type 4`, EPID, tuberías) | Tal cual (los valores salen de los ioctls 3 y 0x10) | Referencia: comprobar si la versión de MM/libqmi lo hace para IPA; si la conexión no llega a pasar datos, es un sospechoso |
| WDA Set Data Format raw-IP + QMAP (5) UL/DL, 32 datagramas, 16384 bytes, endpoint embedded | Referencia directa | Referencia directa: es lo que debe negociar MM. **QMAP v1, no QMAPv5** |
| Enlace `rmnet` mux 1, `IFLA_RMNET_FLAGS = 0x1` (solo desagregación de entrada, sin checksum MAPv5) | Tal cual (`ip link add … type rmnet mux_id 1`) | Equivalente: lo crea MM (`rmnet` sobre `rmnet_ipa0`). Si se crea a mano, no activar flags de checksum v4/v5 |
| WDS Bind Mux Data Port (`{4, EPID}`, mux 1) | Tal cual | Referencia |
| IP, ruta y DNS por `ip`/`resolv.conf` | Equivalente: NetworkManager o el método `static` de MM | Igual |

### 5.4 Valores medidos en spes que sirven para validar

- **Formato WDA negociado**: link-layer `raw-ip` (2), UL y DL `qmap` (5),
  32 datagramas, 16384 bytes, endpoint `embedded` (4). Si el módem responde
  otra cosa (p. ej. 0 en UL), el formato pedido no es válido.
- **QMAP v1** y rmnet con solo `INGRESS_DEAGGREGATION` (0x1). QMAPv5 (9) lo
  rechaza (responde 5).
- **APN de Claro Ecuador**: `ba.amx`. El módem lo devuelve en WDS 0x85
  (LTE attach parameters, TLV 0x10), así que se puede conectar sin
  configurarlo a mano.
- **Operador**: TLV 0x12 = `43 66 50 fa 04 15 87` → "CLARO EC".
- **IPv4** con IP, gateway, máscara, dos DNS y MTU en Runtime Settings
  (los valores concretos de la sesión no están guardados en el repo).
- **Firmware IPA necesario**: sin `ipa_fws` no aparece `rmnet_ipa0` (y el WLAN
  falla con `ipa3_uc_reg_rdyCB bad parm`).
- **EINVAL** en el segundo `SET_EGRESS_DATA_FORMAT` (solo downstream).
- **DMS Get MSISDN** → `NOT_PROVISIONED` con esta SIM: no es un fallo del port.
- Latencia de referencia: ping a 8.8.8.8 ~99 ms por 4G.

### 5.5 Lo que **no** se ha verificado

- SIM con PIN (el código existe; no se probó con una SIM bloqueada).
- PUK, SIM bloqueada, ausencia de SIM.
- Conexión automática al arrancar (siempre se conectó desde la interfaz).
- IPv6 (no está implementado: solo IPv4).
- Roaming, otros operadores, 3G/2G y 5G (el SM6225 no tiene 5G; el código de
  NR viene del proveedor oficial).
- La variante spesn.
- Si `cnss-daemon` hace falta para los datos.
- Larga duración, suspensión, y pérdida y vuelta de cobertura (el reintento
  existe en `Worker()`, pero no se probó una caída real de red).
- **Nada en kernel mainline**: todo se midió con el 4.19 de stock. En pmOS con
  7.2.9, según sus propias notas, MPSS arranca y QRTR anuncia WDS, NAS y UIM,
  pero ModemManager aún no enumera el módem; la causa no se ha investigado
  aquí.
- La captura del caso "campo 18 = 0" (solo se conserva lo de QMAPv5 → 5).

---

## 6. Diagrama de secuencia y checklist para pmOS

### 6.1 Diagrama

```mermaid
sequenceDiagram
    autonumber
    participant UI as AERA UI
    participant P as aera-cellular-provider
    participant I as init
    participant S as spes-wlan-up.sh
    participant D as qrtr-ns / pd-mapper / rmt_storage / tftp_server / cnss / modem-hold
    participant K as kernel (rmnet_ipa0, rmnet)
    participant M as módem (QMI por QRTR)

    UI->>P: connect {apn, subscription}
    P->>I: spes.wlan.prep="" ; spes.modem.up=1
    I->>S: start spes-wlan-prep
    S->>K: echo 1 > /dev/ipa (ipa_fws) → rmnet_ipa0
    S->>S: monta vendor y modem (ro), EFS/persist en RAM
    S->>I: spes.wlan.prep=1
    I->>D: start (modem-hold abre /dev/subsys_modem)
    D->>M: MPSS fuera de reset, EFS por rmt_storage
    P->>K: espera modem ONLINE y rmnet_ipa0
    P->>M: QRTR NEW_LOOKUP → NAS, DMS, WDS, UIM, WDA, DPM
    P->>M: DMS 0x2E online
    P->>M: WDS 0xAF/0xB0 + NAS 0x45 (SIM de datos)
    P->>M: UIM 0x47 / 0x2F (hasta "ready")
    P->>M: NAS 0x24 (registrado y PS attach)
    P->>K: ioctl GET_EPID (3), GET_EP_PAIR (0x10)
    P->>M: DPM 0x20 open port {4, EPID, tuberías}
    P->>M: WDA 0x20 raw-ip, QMAP 5/5 → se exige 2/5/5
    P->>M: WDS 0xA2 bind mux {4, EPID} mux 1 ; WDS 0x4D IPv4
    P->>M: WDS 0x85 → APN "ba.amx"
    P->>M: WDS 0x20 start network (APN, IPv4) → handle
    P->>M: WDS 0x2D runtime settings → IP, gw, máscara, DNS, MTU
    P->>K: RTM_NEWLINK rmnet_aera (mux 1, flags 0x1), IP, MTU
    P->>K: ioctl 6/7 (solo 1.ª vez por arranque), ioctl 5 (mux 1)
    P->>K: default via gw dev rmnet_aera metric 900 ; resolv.conf
    loop cada ~2,5 s
        P->>M: WDS 0x22, NAS 0x24 / 0x4D / 0x4F
    end
    UI->>P: disconnect
    P->>M: WDS 0x21 stop network (handle)
    P->>K: restaura DNS, ip link del rmnet_aera (el módem sigue encendido)
```

### 6.2 Checklist de validación en pmOS

Usar copias de EFS en RAM (como ya hace `spes-radio.sh`) hasta tener claro el
proceso. Sustituir `qrtr://0` por el nodo del módem si no es el 0.

**A. Firmware y módem**

1. `dmesg | grep -iE 'ipa|gsi'`
   - Downstream: `IPA FW loaded successfully` (`docs/evidence/hw-wifi.txt:7`)
     y que exista `rmnet_ipa0` (`ip link show rmnet_ipa0`).
   - Mainline: que el driver `ipa` pruebe sin errores de firmware o GSI y que
     aparezca `rmnet_ipa0`.
2. `dmesg | grep -iE 'mss|modem|remoteproc'`
   - Downstream: `subsys-pil-tz 6080000.qcom,mss: modem: Brought out of reset`.
   - Mainline: `remoteproc…: remote processor … is now up`.
   - No debe haber `Root PD crashed` ni reinicios del subsistema (SSR).
3. Downstream: `cat /sys/bus/msm_subsys/devices/*/name` y `state` → `modem ONLINE`.
4. `rmtfs` y `tqftpserv` en marcha **antes** de arrancar el módem (en AERA se
   esperan 2 s, `spes-modem-hold.sh:5-8`).

**B. QRTR y servicios**

5. `qrtr-lookup` debe listar en el nodo del módem al menos: 1 (WDS), 2 (DMS),
   3 (NAS), 11 (UIM), 26 (WDA) y 47 (DPM).

**C. SIM y registro (qmicli)**

```bash
qmicli -d qrtr://0 --dms-set-operating-mode=online
```

Si responde `DeviceNotReady` (error 52) justo después de arrancar el módem, es normal en spes: repetir cada medio segundo hasta que acepte (en AERA tarda unos segundos). Un script o servicio de pmOS que haga esta llamada nada más arrancar el MPSS necesita el mismo reintento.

```bash
qmicli -d qrtr://0 --uim-get-card-status
```

Esperado: tarjeta presente, aplicación USIM `ready` (si pide PIN:
`--uim-verify-pin=PIN1,<pin>`; caso no probado en AERA).

```bash
qmicli -d qrtr://0 --nas-get-serving-system
```

Esperado: `Registration state: 'registered'`, `PS: 'attached'`, radio `lte`,
operador "CLARO EC" (si el nombre sale como basura, es el GSM 7 bits de la
sección 2.5). El MCC/MNC no quedó registrado en este repo; el público de Claro
Ecuador es 740/01.

```bash
qmicli -d qrtr://0 --wds-get-lte-attach-parameters
```

Esperado: APN `ba.amx`.

**D. Formato de datos**

```bash
qmicli -d qrtr://0 --wda-get-data-format
```

Al configurarlo (si lo hace uno mismo; con mainline lo debería hacer MM),
`--wda-set-data-format` con `link-layer-protocol=raw-ip`, `ul-protocol=qmap`,
`dl-protocol=qmap`, `dl-max-datagrams=32`, `dl-datagram-max-size=16384`,
`ep-type=embedded` y `ep-iface-number=<EPID>`. Esperado en la respuesta: lo
mismo (raw-ip, qmap, qmap). La sintaxis exacta depende de la versión de
libqmi: comprobar `qmicli --help-wda`.

**E. ModemManager (mainline)**

```bash
mmcli -L
```

```bash
mmcli -m any
```

Esperado: el módem aparece con un puerto de datos `rmnet_ipa0` (driver `ipa`),
SIM `ready`, estado `registered`, operador "CLARO EC", tecnología `lte`. Si
`mmcli -L` no muestra nada (como en las notas actuales de pmOS), revisar que la
versión de MM tenga soporte QRTR y que `rmnet_ipa0` exista cuando MM busca
puertos.

```bash
mmcli -m any --simple-connect="apn=ba.amx,ip-type=ipv4"
```

```bash
mmcli -m any --bearer=0
```

Esperado: bearer conectado, interfaz `rmnet` (p. ej. `qmapmux0.0` o similar)
con IPv4, gateway, DNS y MTU.

**F. Tráfico**

```bash
ip -4 addr show
```

```bash
ping -c 3 -I <interfaz rmnet> 8.8.8.8
```

Esperado: 3/3, latencia del orden de ~100 ms (4G Claro EC).

**G. Reconexión**

Desconectar (`mmcli -m any --simple-disconnect`) y volver a conectar al menos
tres veces. En downstream con un ayudante propio, el segundo
`SET_EGRESS_DATA_FORMAT` debe omitirse; si se ve `EINVAL` en el ioctl 6, es el
problema de la sección 3.4.

**H. Señales de fallo y qué significan**

| Síntoma | Causa probable |
|---|---|
| No existe `rmnet_ipa0` | Falta `ipa_fws` (downstream) o el driver `ipa`/GSI no probó (mainline) |
| WDA devuelve UL/DL ≠ qmap o 0 | Formato pedido no soportado: usar QMAP v1 (5), no QMAPv5 (9) |
| Start Network falla con *call end reason* | APN incorrecto, sin PS attach o SIM sin datos |
| Conecta pero no pasa tráfico | DPM/bind mux mal (EPID o mux id), o flags de checksum MAPv5 activados en rmnet |
| La segunda conexión falla con EINVAL (downstream) | Formatos IPA reenviados (sección 3.4) |
| Operador ilegible | TLV 0x12 en GSM 7 bits (sección 2.5) |
