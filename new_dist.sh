#!/bin/sh

set -e

# To ensure all files end up with the correct permissions, set the umask to the
# standard of 022
umask 022

BASENAME=`basename $0`

if [ "$#" -ne 1 ] || ! [ "$1" ]; then
  echo "usage: ${BASENAME} TARGETDIR"
  exit 1;
fi;

# Destination directory
TARGET="$1"
SUITE=wheezy
MIRROR=http://http.debian.net/debian/
ARCH=armh:%s/f
VARIANT=minbase

# create new dir first
mkdir -p "${TARGET}/etc/apt/"

# setup apt mirrors
cat <<EOF > "${TARGET}/etc/apt/sources.list"
deb http://http.debian.net/debian/ ${SUITE} main contrib non-free
EOF

debootstrap --verbose --foreign --arch "${ARCH}" --variant="${VARIANT}" "${SUITE}" "${TARGET}" "${MIRROR}"
