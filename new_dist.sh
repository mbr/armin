#!/bin/sh

set -e

# To ensure all files end up with the correct permissions, set the umask to the
# standard of 022
umask 022

# ensure we have a valid target directory
if [ "$#" -ne 1 ] || ! [ "$1" ]; then
  echo "usage: $(basename $0) TARGETDIR"
  exit 1;
fi;

TARGETDIR="$1"

### STEP 0: download firmware
FW_REV=$(git ls-remote https://github.com/raspberrypi/firmware master | cut -f1)
FW_SOURCE="https://github.com/raspberrypi/firmware/archive/${FW_REV}.zip"
FW_PATH="firmware-${FW_REV}"
FW_ZIP="${FW_PATH}.zip"

if ! [ -e "${FW_ZIP}" ]; then
  echo "Downloading latest firmware (master branch): $FW_ZIP"
  curl -L -o "${FW_ZIP}" "${FW_SOURCE}"
fi;


### STEP 1: bootstrapping with multistrap and adding files
CONFFILE=raspi.config
MACHINE_ID_FILE="${TARGETDIR}/etc/machine-id"

# we need qemu for chroot
QEMU_STATIC=$(which qemu-arm-static)
QEMU_CHROOT="${TARGETDIR}/usr/bin/qemu-arm-static"
IN_CHROOT="sudo chroot ${TARGETDIR} /usr/bin/env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin DEBIAN_FRONTEND=noninteractive"

# and extract firmware
FIRMWARE_DIR=${TARGETDIR}/boot/firmware

multistrap -f "${CONFFILE}" -d "${TARGETDIR}"

mkdir -p "${FIRMWARE_DIR}"

# extract firmware into /boot/firmware
unzip -o -j -d "${FIRMWARE_DIR}" "${FW_ZIP}" "${FW_PATH}/boot/*.bin" "${FW_PATH}/boot/*.dat" "${FW_PATH}/boot/*.elf"

# copy over config.txt
cp config.txt "${FIRMWARE_DIR}/config.txt"

# copy qemu into chroot to make it possible to run stuff
cp "${QEMU_STATIC}" "${QEMU_CHROOT}"

# create an empty machine id, otherwise systemd.deb will try to generate one
# we erase it afterwards
echo '0123456789abcdef0123456789abcdef' > "${MACHINE_ID_FILE}"

# add an fstab
cat >> "${TARGETDIR}/etc/fstab" <<EOF
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot/firmware  vfat    defaults,rw,noatime,nodiratime,errors=remount-ro  0   2
/dev/mmcblk0p2  /               ext4    defaults,rw,noatime,nodiratime,errors=remount-ro  0   1
EOF

# setup firmware script
install "install-firmware-kernel" -D "${TARGETDIR}/etc/initramfs/post-update.d/install-firmware-kernel"

# add kernel commandline
cat >> "${FIRMWARE_DIR}"/cmdline.txt <<EOF
dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait
EOF


### STEP 2: chroot stage-two

# FIXME: fakechroot would be nice here
sudo chown root.root "${TARGETDIR}" -R

# prime dash for setup, otherwise it will fail
${IN_CHROOT} /var/lib/dpkg/info/dash.preinst install

${IN_CHROOT} /usr/bin/dpkg --configure -a

# files no longer required
sudo rm -f "${MACHINE_ID_FILE}" "${QEMU_CHROOT}"



### STEP 3: create image file

# sizes are in megabytes
IMG_SIZE=512
BOOT_PART_SIZE=32
IMG="$(basename ${TARGETDIR}).img"
BOOT_TMP_IMG="${IMG}.tmp.vfat"

# using a sparse file to save space
truncate -s${IMG_SIZE}M "${IMG}"

# create two partitions
parted --script -- "${IMG}" mktable msdos mkpart primary fat32 4M $((4+${BOOT_PART_SIZE}))M mkpart primary ext4 $((4+${BOOT_PART_SIZE}))M -0

PARTS=$(kpartx -av "${IMG}" | cut -d ' ' -f 3)
DEV_FW=/dev/mapper/$(echo $PARTS | cut -d ' ' -f 1)
DEV_ROOT=/dev/mapper/$(echo $PARTS | cut -d ' ' -f 2)
MOUNT_FW=$IMG-mount-firmware/
MOUNT_ROOT=$IMG-mount-root/

# create filesystems
mkfs.vfat ${DEV_FW}
mkfs.ext4 ${DEV_ROOT}

# mount
mkdir -p "$MOUNT_FW" "$MOUNT_ROOT"
mount "$DEV_FW" "$MOUNT_FW"
mount "$DEV_ROOT" "$MOUNT_ROOT"

# copy over files
rsync -rav "${TARGETDIR}/boot/firmware/" "$MOUNT_FW"
rsync -rav --exclude="boot/firmware/" "${TARGETDIR}/" "$MOUNT_ROOT"
mkdir -p "$MOUNT_ROOT"/boot/firmware

# cleanup
umount "$DEV_ROOT"
umount "$DEV_FW"
rmdir "$MOUNT_FW" "$MOUNT_ROOT"
kpartx -d "${IMG}"
