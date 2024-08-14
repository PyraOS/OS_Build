#!/bin/sh

if [ "$#" -lt 1 ] ; then echo "Usage: $0 input.img" ; exit 1; fi
if [ $(id -u) -ne 0 ] ; then echo "Must be run as root"; exit 1; fi

IMAGENAME=$1

if [ ! -f ${IMAGENAME} ] ; then
    echo ${IMAGENAME} not found.
    exit 1
fi


LOOPDEV=$(losetup -f -P --show "${IMAGENAME}")
PART_BOOT=${LOOPDEV}p1
PART_ROOTFS=${LOOPDEV}p2
ROOTFS=$(mktemp -d)
mount ${PART_ROOTFS} ${ROOTFS}
mount ${PART_BOOT} ${ROOTFS}/boot
ROOTPARTUUID=$(blkid -p $PART_ROOTFS -s PART_ENTRY_UUID -o value) 
BOOTPARTUUID=$(blkid -p $PART_BOOT -s PART_ENTRY_UUID -o value)

DATA=${PWD}/makeimg_data

echo boot:${BOOTPARTUUID}
echo root:${ROOTPARTUUID}

tar --numeric-owner -cvf ${IMAGENAME}.tar -C ${ROOTFS} .
echo sync
#systemd-nspawn --bind=${PWD}/bind:/bind --bind=${DATA}/cache/installer:/installer --bind=${DATA}/cache/apt:/cache -D ${ROOTFS} 
#systemd-nspawn --bind=${DATA}/cache/installer:/installer --bind=${DATA}/cache/apt:/cache -D ${ROOTFS}
sync

umount ${ROOTFS}/boot
umount ${ROOTFS}
rm ${ROOTFS} -rf
losetup -d ${LOOPDEV}

