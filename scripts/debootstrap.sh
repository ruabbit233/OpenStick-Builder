#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}
RELEASE=${RELEASE=stable}
HOST_NAME=${HOST_NAME=openstick-debian}

# Emulation is the dominant cost of this script: on x86_64 every maintainer
# script of the arm64 base system has to run through qemu-user, which is about
# an order of magnitude slower than native. GitHub's ubuntu-24.04-arm runners
# are native aarch64, so they can skip --foreign/--second-stage completely.
if [ "$(dpkg --print-architecture)" = "arm64" ]; then
    QEMU=
else
    QEMU=qemu-aarch64-static
fi

rm -rf ${CHROOT}

t0=$(date +%s)

if [ -n "${QEMU}" ]; then
    debootstrap --foreign --arch arm64 \
        --keyring /usr/share/keyrings/debian-archive-keyring.gpg ${RELEASE} ${CHROOT}

    cp "$(which qemu-aarch64-static)" ${CHROOT}/usr/bin
    chroot ${CHROOT} ${QEMU} /bin/bash /debootstrap/debootstrap --second-stage
else
    debootstrap --arch arm64 \
        --keyring /usr/share/keyrings/debian-archive-keyring.gpg ${RELEASE} ${CHROOT}
fi

echo "[timing] base system (${RELEASE}, host $(dpkg --print-architecture)): $(( $(date +%s) - t0 ))s"

cat << EOF > ${CHROOT}/etc/apt/sources.list
deb http://deb.debian.org/debian ${RELEASE} main contrib non-free-firmware
deb http://deb.debian.org/debian-security/ ${RELEASE}-security main contrib non-free-firmware
deb http://deb.debian.org/debian ${RELEASE}-updates main contrib non-free-firmware
EOF

mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/
mount -o bind /dev/pts/ ${CHROOT}/dev/pts/
mount -o bind /run ${CHROOT}/run/

cp scripts/setup.sh ${CHROOT}
t1=$(date +%s)
chroot ${CHROOT} ${QEMU} /bin/sh -c /setup.sh
echo "[timing] package install: $(( $(date +%s) - t1 ))s"

# cleanup
for a in proc sys dev/pts dev run; do
    umount ${CHROOT}/${a}
done;

rm -f ${CHROOT}/setup.sh
echo -n > ${CHROOT}/root/.bash_history

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup systemd services
cp -a configs/system/* ${CHROOT}/etc/systemd/system

# schedutil rate-limit workaround: cpufreq-dt reports an unknown transition
# latency on this DTB, which makes schedutil throttle frequency changes for
# several seconds. The unit writes the normal 10 ms value at boot.
ln -sf /etc/systemd/system/cpufreq-schedutil-tune.service \
    ${CHROOT}/etc/systemd/system/multi-user.target.wants/cpufreq-schedutil-tune.service

cp -a scripts/msm-firmware-loader.sh ${CHROOT}/usr/sbin

# setup NetworkManager
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*
sed -i '/\[main\]/a dns=dnsmasq' ${CHROOT}/etc/NetworkManager/NetworkManager.conf

# Disable WiFi power save.
#
# The kernel is built with CONFIG_CFG80211_DEFAULT_PS=y and NetworkManager
# defaults to wifi.powersave=3 as well, so the wcn36xx station sleeps between
# beacons. On this driver that produces 100-300 ms ping spikes and keeps the
# TX rate at MCS4-ish: every downlink frame waits for the next DTIM (100 ms
# here). This file is parsed after the distro default and turns PS off.
mkdir -p ${CHROOT}/etc/NetworkManager/conf.d
cat << EOF > ${CHROOT}/etc/NetworkManager/conf.d/99-wifi-powersave-off.conf
[connection]
wifi.powersave = 2
EOF

# enable autoconnect for usb0
cat << EOF > ${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# install kernel
#
# The kernel comes from postmarketOS. Default: v26.06 (6.12.1-r5).
# Override KERNEL_BRANCH / KERNEL_VERSION (or the full KERNEL_URL) to use
# another package, e.g. KERNEL_BRANCH=v24.06 KERNEL_VERSION=6.6-r5.
KERNEL_BRANCH=${KERNEL_BRANCH:-v26.06}
KERNEL_VERSION=${KERNEL_VERSION:-6.12.1-r5}
KERNEL_PKG=${KERNEL_PKG:-linux-postmarketos-qcom-msm8916}
KERNEL_URL=${KERNEL_URL:-}
if [ -z "${KERNEL_URL}" ]; then
    KERNEL_URL="https://mirror.postmarketos.org/postmarketos/${KERNEL_BRANCH}/aarch64/${KERNEL_PKG}-${KERNEL_VERSION}.apk"
fi

KERNEL_APK=$(mktemp /tmp/openstick-kernel-XXXXXX)
echo "Installing kernel: ${KERNEL_URL}"
wget --timeout=60 --tries=3 -O "${KERNEL_APK}" "${KERNEL_URL}"
tar xkzf "${KERNEL_APK}" -C ${CHROOT} --exclude=.PKGINFO --exclude=.SIGN*
rm -f "${KERNEL_APK}"

mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux

# copy custom dtb's
cp dtbs/* ${CHROOT}/boot/dtbs/qcom

# create missing directory
mkdir -p ${CHROOT}/lib/firmware/msm-firmware-loader

# update fstab
echo "PARTUUID=80780b1d-0fe1-27d3-23e4-9244e62f8c46\t/boot\text2\tdefaults\t0 2" > ${CHROOT}/etc/fstab

# backup rootfs
t2=$(date +%s)
tar cpzf rootfs.tgz --exclude="usr/bin/qemu-aarch64-static" -C rootfs .
echo "[timing] rootfs archive: $(( $(date +%s) - t2 ))s"
