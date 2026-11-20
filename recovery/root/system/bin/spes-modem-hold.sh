#!/system/bin/sh
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# Keeps the modem subsystem powered (subsystem_get) for Wi-Fi while this
# process lives. Give rmt_storage/tftp_server a moment to register first, as
# the modem requests its EFS and files immediately after reset.
sleep 2
exec 3</dev/subsys_modem || { echo "spes-wlan: cannot open /dev/subsys_modem" > /dev/kmsg; exit 1; }
echo "spes-wlan: modem vote held" > /dev/kmsg
while :; do sleep 3600; done
