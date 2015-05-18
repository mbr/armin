#!/bin/sh

set -e

# To ensure all files end up with the correct permissions, set the umask to the
# standard of 022
umask 022

BASENAME=$(basename $0)

if [ "$#" -ne 1 ] || ! [ "$1" ]; then
  echo "usage: ${BASENAME} TARGETDIR"
  exit 1;
fi;

TARGETDIR="$1"
CONFFILE=raspi.config
IN_CHROOT="sudo chroot ${TARGETDIR} /usr/bin/env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin DEBIAN_FRONTEND=noninteractive"

multistrap -f ${CONFFILE} -d ${TARGETDIR}

# copy qemu into chroot to make it possible to run stuff
cp $(which qemu-arm-static) ${TARGETDIR}/usr/bin

# create an empty machine id, otherwise systemd.deb will try to generate one
# we erase it afterwards
echo '0123456789abcdef0123456789abcdef' > ${TARGETDIR}/etc/machine-id

# FIXME: fakechroot would be nice here
sudo chown root.root ${TARGETDIR} -R

# prime dash for setup, otherwise it will fail
${IN_CHROOT} /var/lib/dpkg/info/dash.preinst install

${IN_CHROOT} /usr/bin/dpkg --configure -a

# remove machine id
rm ${TARGETDIR}/etc/machine-id
