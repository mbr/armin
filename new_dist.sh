#!/bin/sh

set -e

run_hooks() {
  for HOOKDIR in "${PROFILEDIR}"/*; do
    if [ -d "${HOOKDIR}" ]; then
      HOOKFN="${HOOKDIR}/$1"
      if [ -e "${HOOKFN}" ]; then
        echo "-> ${HOOKFN}"
        . "${HOOKFN}";
      fi;
    fi;
  done;
}

chroot_copy() {
  install -m 0644 -D "${HOOKDIR}/files/$1" "${CHROOTDIR}/$2/$1"
}

chroot_install() {
  install -m 0755 -D "${HOOKDIR}/files/$1" "${CHROOTDIR}/$2/$1"
}

# To ensure all files end up with the correct permissions, set the umask to the
# standard of 022
umask 022

# ensure we have a valid target directory
if [ "$#" -ne 2 ]; then
  echo "usage: $(basename $0) PROFILE TARGETDIR"
  exit 1;
fi;


# set global variables
TARGETDIR="$(readlink -f $2)"
BASEDIR="$(dirname $(readlink -f $0))"

HOSTNAME=raspberrypi
PROFILE="$1"
CHROOTDIR="${TARGETDIR}/fsroot"
PROFILEDIR="${BASEDIR}/profile/${PROFILE}"



### STEP 1: generate conffile and multistrap
CONFFILE="${TARGETDIR}/multistrap.conf"

mkdir -p "$(dirname "${CONFFILE}")"
cp "${PROFILEDIR}/multistrap.conf" "${CONFFILE}"


# 1.1 run hooks (can affect config)
run_hooks pre-multistrap

# 1.2 setup multistrap config
sed -i "s/##DEBIAN_PACKAGES##/${DEBIAN_PACKAGES}/g" "${CONFFILE}"
cat "${CONFFILE}"

# 1.3 run multistrap
mkdir -p "${CHROOTDIR}"
multistrap -f "${CONFFILE}" -d "${CHROOTDIR}"

# 1.4 create /dev/null (otherwise scripts writing to /dev/null will create it)
mknod "${CHROOTDIR}/dev/null" c 1 3 || true

# 1.5 run post-multistrap hooks
run_hooks post-multistrap


### STEP 2: chroot configuration
QEMU_STATIC=$(which qemu-arm-static)
QEMU_CHROOT="${CHROOTDIR}/usr/bin/qemu-arm-static"
IN_CHROOT="chroot ${CHROOTDIR} /usr/bin/env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin DEBIAN_FRONTEND=noninteractive"

# 2.1 copy qemu into chroot to make it possible to run stuff
cp "${QEMU_STATIC}" "${QEMU_CHROOT}"

# 2.2 disable automatic daemon startup
cat > "${CHROOTDIR}/usr/sbin/policy-rc.d" <<EOF
#!/bin/sh
exit 101
EOF
chmod a+x "${CHROOTDIR}/usr/sbin/policy-rc.d"

# 2.3 remove chfn suid (does not play well with fakeroot)
#chmod u-s "${CHROOTDIR}/usr/bin/chfn"

# 2.4 run preconfiguration hooks
run_hooks pre-configure-all

# 2.5 configure all packages
${IN_CHROOT} /usr/bin/dpkg --configure -a

# 2.6 run post configuration hooks
run_hooks post-configure-all

# 2.7 restore chfn
#chmod u+s "${CHROOTDIR}/usr/bin/chfn"

# 2.8 cleanup
rm -f "${QEMU_CHROOT}" "${CHROOTDIR}/usr/sbin/policy-rc.d"



### STEP 3: create image file

# sizes are in megabytes
IMG_SIZE=512
BOOT_PART_SIZE=32
IMG="${TARGETDIR}/${PROFILE}-$(date +'%Y-%m-%d').img"

# 3.1 using a sparse file to save space, create two partitions
truncate -s${IMG_SIZE}M "${IMG}"
parted --script -- "${IMG}" mktable msdos mkpart primary fat32 4M $((4+${BOOT_PART_SIZE}))M mkpart primary ext4 $((4+${BOOT_PART_SIZE}))M -0

PARTS=$(kpartx -av "${IMG}" | cut -d ' ' -f 3)
DEV_FW=/dev/mapper/$(echo $PARTS | cut -d ' ' -f 1)
DEV_ROOT=/dev/mapper/$(echo $PARTS | cut -d ' ' -f 2)
MOUNT_BASE="${TARGETDIR}/mounts"
MOUNT_FW="${TARGETDIR}/mounts/firmware"
MOUNT_ROOT="${TARGETDIR}/mounts/root"

# 3.2 create filesystems
mkfs.vfat ${DEV_FW}
mkfs.ext4 ${DEV_ROOT}

# 3.3 mount
mkdir -p "$MOUNT_FW" "$MOUNT_ROOT"
mount "$DEV_FW" "$MOUNT_FW"
mount "$DEV_ROOT" "$MOUNT_ROOT"

# 3.4 copy over files
rsync -ra "${CHROOTDIR}/boot/firmware/" "$MOUNT_FW"
rsync -ra --exclude="boot/firmware/" "${CHROOTDIR}/" "$MOUNT_ROOT"
mkdir -p "$MOUNT_ROOT"/boot/firmware

# 3.5 cleanup
umount "$DEV_ROOT"
umount "$DEV_FW"
rmdir "$MOUNT_FW" "$MOUNT_ROOT" "$MOUNT_BASE"
kpartx -d "${IMG}"

echo "wrote ${IMG}"
