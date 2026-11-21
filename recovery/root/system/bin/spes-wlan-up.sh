#!/system/bin/sh
# Copyright (C) 2026 AERA Recovery Project contributors
# SPDX-License-Identifier: Apache-2.0
#
# On-demand Wi-Fi bring-up for spes (SM6225). The WLAN firmware runs on the
# modem DSP (icnss), so the modem must boot, which needs the stock QMI
# daemons. They come from the installed vendor partition (mounted read-only)
# and run from a RAM copy in $RUN (official AERA trees for devices with
# dynamic partitions ship them in the ramdisk; spes has no ramdisk room).
# Running them from the vendor mount is not enough: AERA stops every process
# that uses a dynamic partition before unmapping super (sideload, flashing),
# and killing qrtr-ns/pd-mapper crashes the modem root PD, so WLAN is lost.
#
# Nothing the modem writes may reach real partitions from recovery:
#   - EFS (modemst1/modemst2/fsg/fsc) is served by rmt_storage from RAM copies
#     on loop devices (the by-name links in /dev, a tmpfs, are repointed);
#   - persist/rfs and hlos_rfs (tftp_server) are RAM copies on a tmpfs;
#   - /data/vendor/wifi and /data/vendor/tombstones get a tmpfs if /data is up.
# A reboot discards all of it. Sets spes.wlan.prep=1 on success, =fail otherwise.

log() { echo "spes-wlan: $*" > /dev/kmsg; echo "spes-wlan: $*" >> /tmp/recovery.log; }
fail() { log "ERROR: $*"; setprop spes.wlan.prep fail; exit 1; }

[ "$(getprop spes.wlan.prep)" = "1" ] && { log "already prepared"; exit 0; }

SLOT="$(getprop ro.boot.slot_suffix)"
BYNAME=/dev/block/bootdevice/by-name

# 1. Installed vendor, read-only
mkdir -p /mnt/vendor_stock
if ! grep -q " /mnt/vendor_stock " /proc/mounts; then
    mount -t ext4 -o ro "/dev/block/mapper/vendor$SLOT" /mnt/vendor_stock \
        || fail "cannot mount vendor$SLOT read-only"
fi
[ -x /mnt/vendor_stock/bin/rmt_storage ] || fail "stock vendor has no rmt_storage"

# RAM copy of the daemons and of every vendor library they map (measured in
# /proc/<pid>/maps on EvolutionX 11.10). The services in init.recovery.wifi.rc
# run from here, so they keep no file open on the vendor mount.
RUN=/tmp/spes_vendor
BINS="qrtr-ns pd-mapper rmt_storage tftp_server cnss-daemon"
LIBS="libbase.so libbinder.so libc++.so libcld80211.so libcutils.so libidl.so
libjson.so libmdmdetect.so libnl.so libperipheral_client.so libqmi_cci.so
libqmi_common_so.so libqmi_csi.so libqmi_encdec.so libqmiservices.so libqrtr.so
libqsocket.so libutils.so"
if [ ! -x "$RUN/bin/cnss-daemon" ]; then
    mkdir -p "$RUN/bin" "$RUN/lib64"
    for b in $BINS; do
        cp -p "/mnt/vendor_stock/bin/$b" "$RUN/bin/" || fail "cannot copy vendor bin/$b"
    done
    for l in $LIBS; do
        cp -p "/mnt/vendor_stock/lib64/$l" "$RUN/lib64/" || fail "cannot copy vendor lib64/$l"
    done
    # rfs holds only symlinks into the sandboxed paths below and /vendor/firmware*
    cp -a /mnt/vendor_stock/rfs "$RUN/" || fail "cannot copy vendor rfs"
    # init services run with umask 077; pd-mapper (system) and tftp_server
    # (oem_2903) drop root and must still traverse and read the copy.
    chmod 0755 "$RUN" "$RUN/bin" "$RUN/lib64"
    chmod 0644 "$RUN"/lib64/*
    log "vendor daemons copied to RAM ($RUN)"
fi

# IPA firmware: the WLAN host driver registers its uC offload with IPA and
# fails to probe (-EFAULT, "ipa3_uc_reg_rdyCB bad parm") while IPA is down.
# Android loads it at early-boot (ipa_fws.rc: write /dev/ipa 1). ueventd serves
# /vendor/firmware, which is the ramdisk (RAM) here.
subsys_state() {
    for d in /sys/bus/msm_subsys/devices/*; do
        [ "$(cat "$d/name" 2>/dev/null)" = "$1" ] && cat "$d/state"
    done
}
if [ "$(subsys_state ipa_fws)" != ONLINE ]; then
    cp /mnt/vendor_stock/firmware/ipa_fws.* /vendor/firmware/ 2>/dev/null || fail "no ipa_fws firmware in vendor"
    echo 1 > /dev/ipa || fail "cannot load IPA firmware"
    log "IPA firmware loaded"
fi

# 2. Modem firmware partition, read-only (ueventd serves /firmware/image)
mkdir -p /firmware
if ! grep -q " /firmware " /proc/mounts; then
    mount -t vfat -o ro,shortname=lower,uid=1000,gid=1000,dmask=227,fmask=337 \
        "$BYNAME/modem$SLOT" /firmware || fail "cannot mount modem$SLOT"
fi
[ -e /vendor/firmware_mnt ] || ln -s /firmware /vendor/firmware_mnt
# tftp_server serves the modem's files through /vendor/rfs (RAM copy of the
# vendor tree, which only holds symlinks into the sandboxed paths below).
[ -e /vendor/rfs ] || ln -s "$RUN/rfs" /vendor/rfs

# 3. EFS sandbox: rmt_storage gets loop devices backed by RAM copies
mkdir -p /tmp/spes_efs
for p in modemst1 modemst2 fsg fsc; do
    real="$(readlink -f "$BYNAME/$p")"
    case "$real" in /dev/block/loop*) continue ;; esac
    [ -b "$real" ] || fail "no $p partition"
    dd if="$real" of="/tmp/spes_efs/$p.img" bs=1M 2>/dev/null || fail "cannot copy $p"
    loop="$(losetup -f --show "/tmp/spes_efs/$p.img")" || fail "no loop device for $p"
    echo "$real" > "/tmp/spes_efs/$p.real"
    ln -sf "$loop" "$BYNAME/$p" || fail "cannot repoint $p"
    [ "$(readlink -f "$BYNAME/$p")" = "$loop" ] || fail "$p still points to $(readlink -f "$BYNAME/$p")"
    log "$p ($real) -> $loop (RAM copy)"
done

# 4. persist sandbox for tftp_server
if ! grep -q " /mnt/vendor/persist tmpfs" /proc/mounts; then
    mkdir -p /mnt/vendor/persist
    # AERA keeps its settings in /persist (AERA_SETTINGS_ROOT_DIRECTORY), so
    # the partition is usually mounted read-write already and a second ext4
    # mount of it with "ro" is refused. Read the copy from that mount then;
    # otherwise mount it read-only just for the copy.
    PERSIST_SRC=""
    PERSIST_TMP=""
    real_persist="$(readlink -f "$BYNAME/persist")"
    while read -r dev mnt fstype _; do
        [ "$fstype" = ext4 ] || continue
        [ "$(readlink -f "$dev")" = "$real_persist" ] && { PERSIST_SRC="$mnt"; break; }
    done < /proc/mounts
    if [ -z "$PERSIST_SRC" ]; then
        PERSIST_TMP=/tmp/spes_persist_ro
        mkdir -p "$PERSIST_TMP"
        mount -t ext4 -o ro "$BYNAME/persist" "$PERSIST_TMP" || fail "cannot mount persist read-only"
        PERSIST_SRC="$PERSIST_TMP"
    fi
    mount -t tmpfs -o mode=0777 tmpfs /mnt/vendor/persist || fail "cannot mount persist tmpfs"
    for d in rfs hlos_rfs; do
        [ -d "$PERSIST_SRC/$d" ] && cp -a "$PERSIST_SRC/$d" /mnt/vendor/persist/
    done
    [ -n "$PERSIST_TMP" ] && umount "$PERSIST_TMP"
    log "persist rfs/hlos_rfs copied to RAM"
fi

# 5. /data paths written by cnss-daemon and tftp_server
# tftp_server drops privileges, so the RAM-only sandbox is world-writable.
# Never create directories on a mounted userdata: if a path is missing there,
# put the whole /data/vendor on a tmpfs instead.
if grep -q " /data " /proc/mounts; then
    if [ -d /data/vendor/wifi ] && [ -d /data/vendor/tombstones ]; then
        for d in /data/vendor/wifi /data/vendor/tombstones; do
            grep -q " $d tmpfs" /proc/mounts || mount -t tmpfs -o mode=0777 tmpfs "$d"
        done
    elif [ -d /data/vendor ]; then
        grep -q " /data/vendor tmpfs" /proc/mounts || mount -t tmpfs -o mode=0777 tmpfs /data/vendor
    else
        fail "/data is mounted without /data/vendor; refusing to create it"
    fi
else
    mkdir -p /data/vendor/wifi /data/vendor/tombstones
fi
for d in /data/vendor/wifi/sockets /data/vendor/tombstones/rfs/modem /data/vendor/tombstones/rfs/wpss \
         /data/vendor/tombstones/rfs/lpass /data/vendor/tombstones/rfs/cdsp; do
    mkdir -p "$d" && chmod 0777 "$d"
done

log "prepared (slot $SLOT)"
setprop spes.wlan.prep 1
exit 0
