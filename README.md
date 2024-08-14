# makeimg

To Build you need (at minimum on top of a debian / Ubuntu install)

git f2fs-tools debootstrap systemd-container pv qemu-user-static binfmt-support initramfs-tools-core curl zstd 

makeimg.sh      : build bootable pyra image
spawnimg.sh     : mount and nspawn .img for tests/edits 
sd-installer.sh : create bootable sd card image that will write rootfs.img to pyra emmc
make_all.sh     : runs makeimg.sh, followed by sd-installer.sh

`makeimg.sh <rootfs.img> <size of image> <list of packages to install...>`

makeing.sh will also create rootfs.img.installer.tar, which has the initramfs/uboot files needed by sd-installer.sh
(this way sd-installer.sh doesn't need to run on an arm cpu, and can take advantage of faster cpus for compression.
 With the proper qemu-arm-static and binfmt setup all tools do work on non arm platforms as well )

`spawnimg.sh <rootfs.img>`

Launches a systemd-nspawn into the image.

`sd-installer.sh <rootfs.img>`

This will create rootfs-install.img, and rootfs.img.tar.zst 

rootfs.img.tar.zst can be copied to an earlier created -install.img sd card, without having to rewrite the entire disk image.
the installer will write the first .img.tar.zst file it finds on the card

example:

create 4GB image with pyra-meta-mate package and all its dependencies

`sudo ./makeimg.sh pyra-mate.img 4G pyra-meta-mate`

create emmc installer sd card image

`sudo ./sd-installer.sh pyra-mate.img`

create all 

`sudo ./make_all pyra-mate.img 4G pyra-meta-mate`

write resulting .img to sd card directly, put in first sd card slot on pyra, and power on.
**warning:** the -install.img will immediately start overwriting anything on the emmc when booted. 
