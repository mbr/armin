#!/bin/sh

set -e

TARGET=target
SUITE=wheezy
MIRROR=http://http.debian.net/debian/
ARCH=armhf
VARIANT=minbase

# create new dir first
mkdir -p "${TARGET}/etc/apt/"

# setup apt mirrors
cat <<EOF > "${TARGET}/etc/apt/sources.list"
deb http://http.debian.net/debian/ jessie main contrib non-free
EOF

debootstrap --verbose --foreign --arch "${ARCH}" --variant="${VARIANT}" "${SUITE}" "${TARGET}" "${MIRROR}"
