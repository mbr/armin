#!/bin/sh

set -e

# To ensure all files end up with the correct permissions, set the umask to the
# standard of 022
umask 022

# ensure we have a valid target directory
if [ "$#" -ne 1 ] || ! [ "$1" ]; then
  echo "usage: $(basenaem $0) TARGETDIR"
  exit 1;
fi;

TARGETDIR="$1"
CONFFILE=raspi.config
IN_CHROOT="sudo chroot ${TARGETDIR} /usr/bin/env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin DEBIAN_FRONTEND=noninteractive"
MACHINE_ID_FILE=${TARGETDIR}/etc/machine-id

# we need a
QEMU_STATIC=$(which qemu-arm-static)
QEMU_CHROOT=${TARGETDIR}/usr/bin/qemu-arm-static

#multistrap -f ${CONFFILE} -d ${TARGETDIR}

# copy qemu into chroot to make it possible to run stuff
cp ${QEMU_STATIC} ${QEMU_CHROOT}

# create an empty machine id, otherwise systemd.deb will try to generate one
# we erase it afterwards
echo '0123456789abcdef0123456789abcdef' > ${MACHINE_ID_FILE}

# FIXME: fakechroot would be nice here
sudo chown root.root ${TARGETDIR} -R

# prime dash for setup, otherwise it will fail
${IN_CHROOT} /var/lib/dpkg/info/dash.preinst install

${IN_CHROOT} /usr/bin/dpkg --configure -a

# files no longer required
sudo rm -f ${MACHINE_ID_FILE} ${QEMU_CHROOT}
