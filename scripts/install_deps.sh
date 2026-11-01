#!/bin/sh -e

apt update
apt install -y \
    android-sdk-libsparse-utils \
    autoconf \
    automake \
    cmake \
    debian-archive-keyring \
    debootstrap \
    device-tree-compiler \
    fdisk \
    g++-aarch64-linux-gnu \
    gcc-aarch64-linux-gnu \
    gcc-arm-none-eabi \
    libtool \
    make \
    pkg-config \
    python3-cryptography \
    python3-pyasn1-modules \
    python3-pycryptodome \
    unzip \
    wget

# QEMU/binfmt are only needed when the target arch differs from the host;
# native arm64 hosts (e.g. ubuntu-24.04-arm runners) run the chroot directly.
if [ "$(dpkg --print-architecture)" != "arm64" ]; then
    apt install -y binfmt-support qemu-user-static
fi
