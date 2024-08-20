#!/bin/sh

check_exists() { if ! hash "$1" 2>/dev/null ; then echo "$1" not found ; exit 1 ; fi ; }


if [ $(id -u) -ne 0 ] ; then echo "Must be run as root"; exit 1; fi

check_exists sfdisk
check_exists losetup
check_exists dd
check_exists mke2fs
check_exists mkfs.ext4
check_exists debootstrap


if [ "$#" -lt 3 ] ; then echo "Usage: $0 output.img imagesize packages ( $0 output.img 4G pyra-meta-mate )" ; exit 1; fi


#Update binfmt, this only needs to be done on non ARM platforms
update-binfmts --enable qemu-arm

IMAGENAME="$1"
IMAGESIZE="$2"

#Bullseye and beyond supported, we need the OS version to automate detection for testing and SID. OS version beyond 30 will trigger testing and unstable.
case $OS in 

bullseye)
OS_VERSION=11
;;
bookworm)
OS_VERSION=12
;;
trixie)
OS_VERSION=13
;;
forky)
echo "Not supported yet"
OS_VERSION=14
exit
;;
testing)
OS_VERSION=50
;;
sid)
##Sid generally has no version number so let's just go to 50
OS_VERSION=50
;;
default)
## Failsafe
OS=bookworm
OS_VERSION=12
exit
;;

esac

echo "OS Name: ${OS}"
echo "OS Version: ${OS_VERSION}. Note for sid and testing it is 50"



ARCHIVE_KEY="https://ftp-master.debian.org/keys/archive-key-$OS_VERSION.asc"
SECURITY_KEY="https://ftp-master.debian.org/keys/archive-key-$OS_VERSION-security.asc"

shift
shift
PACKAGES=$@
DATA=${PWD}/makeimg_data

if [ -f "${IMAGENAME}" ] ; then
    echo "${IMAGENAME}" exists.
    exit 1
fi

# Prepare Blank Image
dd if=/dev/zero bs=1 count=0 seek="${IMAGESIZE}" of="${IMAGENAME}"

sfdisk "${IMAGENAME}" <<-__EOF__
1M,256M,0x83,*
,,0x83, 
__EOF__

LOOPDEV=$(losetup -f -P --show "${IMAGENAME}")

PART_BOOT="${LOOPDEV}"p1
PART_ROOTFS="${LOOPDEV}"p2

#Append Uboot data to images at specific locations for boot
dd if="${DATA}"/uboot/MLO of="$LOOPDEV" count=1 seek=1 bs=128k conv=notrunc
dd if="${DATA}"/uboot/u-boot.img of="$LOOPDEV" count=2 seek=1 bs=384k conv=notrunc

# Setup the Filesystem on partitions and mount
mke2fs  -L boot "$PART_BOOT"
mkfs.ext4  -O encrypt -L rootfs "$PART_ROOTFS"

ROOTFS=/tmp/ROOTFS
mkdir -p "${ROOTFS}"
mount "${PART_ROOTFS}" "${ROOTFS}"

mkdir "${ROOTFS}"/boot
mount "${PART_BOOT}" "${ROOTFS}"/boot

mkdir -p "${DATA}/cache/debootstrap"
mkdir -p "${DATA}/cache/apt"
mkdir -p "${DATA}/keyrings"
mkdir -p "${ROOTFS}"/usr/share/keyrings

echo "Setup Keyrings and debootstrap"
if [ "$OS_VERSION" -le 30 ]; then
curl -ffSL https://ftp-master.debian.org/keys/archive-key-$OS_VERSION.asc | sudo gpg --dearmor -o "${DATA}/keyrings/debian-archive-keyring-$OS_VERSION.gpg"
debootstrap --cache-dir="${DATA}"/cache/debootstrap --arch=armhf --keyring="${DATA}"/keyrings/debian-archive-keyring-$OS_VERSION.gpg --include=eatmydata,ca-certificates  "${OS}" "${ROOTFS}" http://deb.debian.org/debian

else
debootstrap --cache-dir="${DATA}"/cache/debootstrap --arch=armhf --include=eatmydata,ca-certificates  "${OS}" "${ROOTFS}" http://deb.debian.org/debian
fi


#Fetch the Pyra key, convert it to gpg (see apt-key deprecation)
curl -fsSL https://packages.pyra-handheld.com/pyra-public.pgp | sudo gpg --dearmor -o "${ROOTFS}"/usr/share/keyrings/pyra-public.gpg

echo "Setup Source Repos"

cat << EOF > "${ROOTFS}"/etc/apt/sources.list
#Debian $OS
deb http://deb.debian.org/debian/ $OS main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ $OS main contrib non-free non-free-firmware
EOF
``

#No security repo in Testing or Unstable.
if [ "$OS_VERSION" -le 30 ]; then

cat << EOF >> "${ROOTFS}"/etc/apt/sources.list

# Security Repo
deb http://security.debian.org/debian-security $OS-security main contrib non-free
deb-src http://security.debian.org/debian-security $OS-security main
EOF
fi 

# Pyra Packages Repo
if [ "$OS_VERSION" -le 30 ]; then
cat << EOF >> "${ROOTFS}"/etc/apt/sources.list.d/pyra-packages.list
deb [arch=armhf signed-by=/usr/share/keyrings/pyra-public.gpg] http://slater.au bookworm/
# deb [arch=armhf trusted=yes] http://slater.au bookworm/
EOF
else
cat << EOF >> "${ROOTFS}"/etc/apt/sources.list.d/pyra-packages.list
deb [arch=armhf signed-by=/usr/share/keyrings/pyra-public.gpg] http://slater.au bookworm/
# deb [arch=armhf trusted=yes] http://slater.au bookworm/
EOF
fi 

echo "Copy config and settings to rootfs for execution later"
chmod +x "${DATA}"/config.sh
chmod +x "${DATA}"/settings.debconf

cp "${DATA}"/config.sh "${ROOTFS}"/
cp "${DATA}"/settings.debconf "${ROOTFS}"/settings.debconf


echo "Setup fstab"
ROOTPARTUUID=$(blkid -p "$PART_ROOTFS" -s PART_ENTRY_UUID -o value)
BOOTPARTUUID=$(blkid -p "$PART_BOOT" -s PART_ENTRY_UUID -o value)

cat > "${ROOTFS}"/etc/fstab << EOF
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# / was f2fs initially
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
PARTUUID=${ROOTPARTUUID}  /               ext4    defaults        0       1
PARTUUID=${BOOTPARTUUID}  /boot           ext4    defaults        0       1

EOF


rm "${ROOTFS}"/var/cache/apt/* -rf

echo "Run NSpawn"
# This step requires armHF so we use qemu-arm-static to build
systemd-nspawn  --bind="${DATA}"/installer:/installer --bind="${DATA}"/cache/apt:/var/cache/apt -D "${ROOTFS}" -a /config.sh "${PACKAGES}"

#######################################################
#Cleanup and Build Image

rm "${ROOTFS}"/config.sh
rm "${ROOTFS}"/settings.debconf

# Tar Image
tar cvf "${IMAGENAME}".installer.tar -C "${DATA}"/installer/out/ .

#Remove cached output.
rm "${DATA}"/installer/out -rf
rm "${ROOTFS}"/installer -rf

#Sync and unmount image
echo Sync...
sync

umount "${ROOTFS}/boot"
umount "${ROOTFS}"
rm "${ROOTFS}" -rf
losetup -d "${LOOPDEV}"
echo Done
