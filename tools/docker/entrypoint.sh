#!/bin/bash
# Runs as root inside the --privileged container. It mounts ONLY the ext4
# image file passed in AERA_IMAGE (loop device) at /src and bind-mounts the
# device tree into the AOSP layout. Nothing else on the host is touched.
set -euo pipefail

: "${AERA_IMAGE:=/store/aera_src.ext4}"
: "${DEVTREE:=/devtree}"

if [ ! -f "$AERA_IMAGE" ]; then
    echo "entrypoint: image $AERA_IMAGE not found" >&2
    exit 1
fi

mkdir -p /src
LOOPDEV=""
if ! mountpoint -q /src; then
    # `mount -o loop` cannot create loop nodes inside a container's /dev;
    # losetup goes through /dev/loop-control and prints the node it bound.
    LOOPDEV="$(losetup -f --show "$AERA_IMAGE")"
    [ -b "$LOOPDEV" ] || mknod "$LOOPDEV" b 7 "${LOOPDEV#/dev/loop}"
    mount -o noatime "$LOOPDEV" /src
fi
chown builder:builder /src

if [ -d "$DEVTREE" ]; then
    mkdir -p /src/device/xiaomi/spes
    chown -R builder:builder /src/device
    mountpoint -q /src/device/xiaomi/spes || mount --bind "$DEVTREE" /src/device/xiaomi/spes
fi

cleanup() {
    umount /src/device/xiaomi/spes 2>/dev/null || true
    umount /src 2>/dev/null || true
    [ -n "$LOOPDEV" ] && losetup -d "$LOOPDEV" 2>/dev/null || true
}
trap cleanup EXIT TERM INT

echo "entrypoint: /src mounted from $AERA_IMAGE"
# Stay alive; work is done through `docker exec -u builder`.
sleep infinity &
wait $!
