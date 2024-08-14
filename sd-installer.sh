#!/bin/sh

if [ "$#" -lt  1 ] ; then echo "Usage : $0 rootfs.img " ; exit 1 ; fi
if [ $(id -u) -ne 0 ] ; then echo "Must be run as root"; exit 1; fi

IMAGENAME=$1
INSTALLIMG=$(basename $1 .img)-install.img


if [ ! -f ${IMAGENAME} ] ; then
    echo ${IMAGENAME} not found.
    exit 1
fi

DATA=${PWD}/makeimg_data

if [ -f ${INSTALLIMG} ] ; then
    echo ${INSTALLIMG} exists.
    exit 1
fi

if [ ! -f ${IMAGENAME}.tar.zst ] ; then
    if [ ! -f ${IMAGENAME}.tar ] ; then
        echo Creating ${IMAGENAME}.tar.zst
        LOOPDEV=$(losetup -f -P --show "${IMAGENAME}")
        PART_BOOT=${LOOPDEV}p1
        PART_ROOTFS=${LOOPDEV}p2
        ROOTFS=$(mktemp -d)
        mount ${PART_ROOTFS} ${ROOTFS}
        mount ${PART_BOOT} ${ROOTFS}/boot

        SIZE=$(du -sb ${ROOTFS} | awk '{print $1}')
        tar cf - --numeric-owner -C ${ROOTFS} .   | pv -s ${SIZE} | zstd --no-progress --size-hint=${SIZE} -T0 -19 -o ${IMAGENAME}.tar.zst
        
        sync
        umount ${ROOTFS}/boot
        umount ${ROOTFS}
        rm ${ROOTFS} -rf
        losetup -d ${LOOPDEV}
    else
        echo Creating  ${IMAGENAME}.tar.zst
        zstd -T0 -19 ${IMAGENAME}.tar -o ${IMAGENAME}.tar.zst
    fi
fi



dd if=/dev/zero bs=1 count=0 seek=1G of=${INSTALLIMG}

echo "1M,,0x83,*" | sfdisk ${INSTALLIMG}

LOOPDEV=$(losetup -f -P --show "${INSTALLIMG}")

dd if="${DATA}/uboot/MLO" of=$LOOPDEV count=1 seek=1 bs=128k conv=notrunc
dd if="${DATA}/uboot/u-boot.img" of=$LOOPDEV count=2 seek=1 bs=384k conv=notrunc

PART=${LOOPDEV}p1 
mkfs.vfat -n PYRAINSTALL ${PART} 
 
ROOTFS=$(mktemp -d)
mount ${PART} ${ROOTFS}
echo $ROOTFS

tar xf ${IMAGENAME}.installer.tar -C ${ROOTFS}
cp  ${IMAGENAME}.tar.zst ${ROOTFS}/
cp -rL ${DATA}/uboot ${ROOTFS}/

echo "Sync"
sync

umount ${ROOTFS}
rm ${ROOTFS} -rf
losetup -d ${LOOPDEV}

