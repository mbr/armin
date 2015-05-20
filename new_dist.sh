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
HOSTNAME=raspberrypi


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
ROOT_PASSWORD=raspberry


# destination for firmware
FIRMWARE_DIR=${TARGETDIR}/boot/firmware

# 1.1: multistrap
multistrap -f "${CONFFILE}" -d "${TARGETDIR}"

# 1.2: extract firmware
mkdir -p "${FIRMWARE_DIR}"/boot/firmware
unzip -o -j -d "${FIRMWARE_DIR}" "${FW_ZIP}" "${FW_PATH}/boot/*.bin" "${FW_PATH}/boot/*.dat" "${FW_PATH}/boot/*.elf"

# 1.3: firmware configuration
# copy over config.txt
cp config.txt "${FIRMWARE_DIR}/config.txt"
cat >> "${FIRMWARE_DIR}"/cmdline.txt <<EOF
dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait
EOF

# 1.4 setup firmware script
install "install-firmware-kernel" -D "${TARGETDIR}/etc/initramfs/post-update.d/install-firmware-kernel"

# 1.5 add an fstab
cat >> "${TARGETDIR}/etc/fstab" <<EOF
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot/firmware  vfat    defaults,rw,noatime,nodiratime,errors=remount-ro  0   2
/dev/mmcblk0p2  /               ext4    defaults,rw,noatime,nodiratime,errors=remount-ro  0   1
EOF

# 1.6 create /dev/null
# (otherwise scripts writin to /dev/null will create it for us)
mknod "${TARGETDIR}/dev/null" c 1 3



### STEP 2: chroot stage-two

QEMU_STATIC=$(which qemu-arm-static)
QEMU_CHROOT="${TARGETDIR}/usr/bin/qemu-arm-static"
IN_CHROOT="sudo chroot ${TARGETDIR} /usr/bin/env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin DEBIAN_FRONTEND=noninteractive"
SSH_HOST_KEYS="ssh_host_rsa_key ssh_host_dsa_key ssh_host_ecdsa_key ssh_host_ed25519_key"

# 2.1 copy qemu into chroot to make it possible to run stuff
cp "${QEMU_STATIC}" "${QEMU_CHROOT}"

# 2.2 create an empty machine id, otherwise systemd.deb will try to generate
# one. we erase it afterwards
echo '0123456789abcdef0123456789abcdef' > "${MACHINE_ID_FILE}"

# 2.3 work as root
sudo chown root.root "${TARGETDIR}" -R

# 2.4 setup networking
cat >> "${TARGETDIR}/etc/hosts" <<EOF
127.0.0.1  localhost
127.0.1.1  ${HOSTNAME}

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

echo "${HOSTNAME}" > "${TARGETDIR}/etc/hostname"

cat >> "${TARGETDIR}/etc/network/interfaces" <<EOF
auto lo

iface lo inet loopback
iface eth0 inet dhcp

allow-hotplug wlan0
iface wlan0 inet manual
wpa-roam /etc/wpa_supplicant/wpa_supplicant.conf
iface default inet dhcp
EOF

# 2.5 we need to fake some openssh-server keys, because /dev/urandom is not
# available
mkdir -p "${TARGETDIR}/etc/ssh"
for key in ${SSH_HOST_KEYS}; do
  touch "${TARGETDIR}/etc/ssh/$key"
done;

# 2.6 prime dash for setup, otherwise postinst will fail
${IN_CHROOT} /var/lib/dpkg/info/dash.preinst install

# 2.7 disable daemon autostart
cat > "${TARGETDIR}/usr/sbin/policy-rc.d" <<EOF
#!/bin/sh
exit 101
EOF
chmod a+x "${TARGETDIR}/usr/sbin/policy-rc.d"

# 2.8 configure all packages
${IN_CHROOT} /usr/bin/dpkg --configure -a

# 2.9 set root password
echo "root:${ROOT_PASSWORD}" | ${IN_CHROOT} /usr/sbin/chpasswd -c SHA512

# 2.10 cleanup files no longer required
sudo rm -f "${MACHINE_ID_FILE}" "${QEMU_CHROOT}" "${TARGETDIR}/usr/sbin/policy-rc.d"
for key in ${SSH_HOST_KEYS}; do
  rm "${TARGETDIR}/etc/ssh/$key"
done;


### STEP 3: create image file

# sizes are in megabytes
IMG_SIZE=512
BOOT_PART_SIZE=32
IMG="$(basename ${TARGETDIR}).img"
BOOT_TMP_IMG="${IMG}.tmp.vfat"

# 3.1 using a sparse file to save space, create two partitions
truncate -s${IMG_SIZE}M "${IMG}"
parted --script -- "${IMG}" mktable msdos mkpart primary fat32 4M $((4+${BOOT_PART_SIZE}))M mkpart primary ext4 $((4+${BOOT_PART_SIZE}))M -0

PARTS=$(kpartx -av "${IMG}" | cut -d ' ' -f 3)
DEV_FW=/dev/mapper/$(echo $PARTS | cut -d ' ' -f 1)
DEV_ROOT=/dev/mapper/$(echo $PARTS | cut -d ' ' -f 2)
MOUNT_FW=$IMG-mount-firmware/
MOUNT_ROOT=$IMG-mount-root/

# 3.2 create filesystems
mkfs.vfat ${DEV_FW}
mkfs.ext4 ${DEV_ROOT}

# 3.3 mount
mkdir -p "$MOUNT_FW" "$MOUNT_ROOT"
mount "$DEV_FW" "$MOUNT_FW"
mount "$DEV_ROOT" "$MOUNT_ROOT"

# 3.4 copy over files
rsync -rav "${TARGETDIR}/boot/firmware/" "$MOUNT_FW"
rsync -rav --exclude="boot/firmware/" "${TARGETDIR}/" "$MOUNT_ROOT"
mkdir -p "$MOUNT_ROOT"/boot/firmware

# 3.5 cleanup
umount "$DEV_ROOT"
umount "$DEV_FW"
rmdir "$MOUNT_FW" "$MOUNT_ROOT"
kpartx -d "${IMG}"
