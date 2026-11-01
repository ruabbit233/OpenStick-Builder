#!/bin/sh -e

DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true

# Speed up the (possibly emulated) install. dpkg's fsync calls are pure
# overhead on a throwaway build filesystem -- the same trick as eatmydata --
# and translation indexes are never used inside the image.
mkdir -p /etc/dpkg/dpkg.cfg.d /etc/apt/apt.conf.d
echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/99-openstick
echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99-openstick

echo 'tzdata tzdata/Areas select Etc' | debconf-set-selections
echo 'tzdata tzdata/Zones/Etc select UTC' | debconf-set-selections
echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
rm -f "/etc/locale.gen"

apt update -qqy
apt upgrade -qqy
apt autoremove -qqy
apt install -qqy --no-install-recommends \
    bridge-utils \
    dnsmasq \
    hostapd \
    iptables \
    libconfig9 \
    libconfig-dev \
    locales \
    modemmanager \
    netcat-traditional \
    net-tools \
    network-manager \
    openssh-server \
    qrtr-tools \
    rmtfs \
    sudo \
    systemd-timesyncd \
    tzdata \
    wireguard-tools \
    wpasupplicant
apt clean
rm -rf /var/lib/apt/lists/*

# Drop the build-only dpkg speedup: the shipped image should fsync normally,
# otherwise a power cut during a later "apt upgrade" can corrupt the eMMC.
rm -f /etc/dpkg/dpkg.cfg.d/99-openstick

passwd -d root

echo user:1::::/home/user:/bin/bash | newusers
echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/user
