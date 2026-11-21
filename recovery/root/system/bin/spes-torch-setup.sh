#!/system/bin/sh
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flashlight for spes / spesn without kernel changes.
#
# The rear flash is CAM_FLASH_TYPE_GPIO (DT qcom,camera-flash@0): the
# low-power torch mode is TLMM GPIO85 (pinctrl cam_flash_torch). The
# EvolutionX kernel exposes no LED class device for it, so AERA's flashlight
# (which writes <AERA_FL_PATH1>/brightness) is pointed at a RAM directory
# whose "brightness" is the GPIO's sysfs value. Without max_brightness AERA
# writes 1 / 0. GPIO93 (high-current flash pulse) is never touched.
# Verified first on the user's OrangeFox spes tree (GPIO85 only).

TORCH_LINE=85
DIR=/tmp/spes-torch

log() { echo "spes-torch: $*" > /dev/kmsg; }

base=""
for c in /sys/class/gpio/gpiochip*; do
    [ "$(cat "$c/label" 2>/dev/null)" = "400000.pinctrl" ] && base="$(cat "$c/base")" && break
done
[ -n "$base" ] || { log "TLMM gpiochip not found; flashlight unavailable"; exit 0; }

gpio=$((base + TORCH_LINE))
g=/sys/class/gpio/gpio$gpio
[ -d "$g" ] || echo "$gpio" > /sys/class/gpio/export 2>/dev/null
[ -d "$g" ] || { log "cannot export GPIO$TORCH_LINE ($gpio)"; exit 0; }
echo low > "$g/direction"

mkdir -p "$DIR"
ln -sf "$g/value" "$DIR/brightness"
log "torch on GPIO$TORCH_LINE (sysfs $gpio) via $DIR/brightness"
