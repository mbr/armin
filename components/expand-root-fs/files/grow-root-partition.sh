#!/bin/sh

set -e

DEVICE="mmcblk0"
ROOT_PART="mmcblk0p2"
PART_NUM=

START=$(cat /sys/block/${DEVICE}/${ROOT_PART}/start)
PART_NUM=$(cat /sys/block/${DEVICE}/${ROOT_PART}/partition)

# parted will exit with error due to the fact the partition is in use
parted --script -- /dev/${DEVICE} rm ${PART_NUM} mkpart p ext4 ${START}s -0 || true

# refresh kernel partition info
partprobe

# resize filesystem
resize2fs /dev/${ROOT_PART}
