#!/system/bin/sh
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# init's wpa_supplicant service for spes. It is "running" immediately (AERA
# waits only 20 s for that) while the modem boots. Once the modem is online it
# asks the built-in WLAN host driver to start (as the vendor Wi-Fi HAL does,
# "ON" to /dev/wlan), waits for wlan0 and execs the real supplicant.
modem_state() {
    for d in /sys/bus/msm_subsys/devices/*; do
        [ "$(cat "$d/name" 2>/dev/null)" = modem ] && cat "$d/state"
    done
}
i=0
until [ "$(modem_state)" = ONLINE ] || [ "$i" -ge 60 ]; do
    [ "$(getprop spes.wlan.prep)" = fail ] && break
    sleep 1; i=$((i + 1))
done
if [ ! -e /sys/class/net/wlan0 ]; then
    # The WLAN firmware announces itself a few seconds after the modem.
    sleep 5
    echo ON > /dev/wlan 2>/dev/null
    echo "spes-wlan: requested WLAN driver start (modem $(modem_state) after ${i}s)" > /dev/kmsg
fi
j=0
while [ ! -e /sys/class/net/wlan0 ] && [ "$j" -lt 60 ]; do sleep 1; j=$((j + 1)); done
if [ ! -e /sys/class/net/wlan0 ]; then
    echo "spes-wlan: wlan0 did not appear (modem $(modem_state), prep=$(getprop spes.wlan.prep))" > /dev/kmsg
    exit 1
fi
echo "spes-wlan: wlan0 up, starting wpa_supplicant" > /dev/kmsg
exec /system/bin/wpa_supplicant -Dnl80211 -iwlan0 -dd -O/tmp/recovery/sockets \
    -c/vendor/etc/wifi/wpa_supplicant.conf
