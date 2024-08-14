#!/bin/sh

check_exists() { if ! hash "$1" 2>/dev/null ; then echo "$1" not found ; exit 1 ; fi ; }


if [ $(id -u) -ne 0 ] ; then echo "Must be run as root"; exit 1; fi

check_exists sfdisk
check_exists losetup
check_exists dd
check_exists mke2fs
# check_exists mkfs.f2fs
check_exists debootstrap


if [ "$#" -lt 3 ] ; then echo "Usage: $0 output.img imagesize packages ( $0 output.img 4G pyra-meta-mate )" ; exit 1; fi

#modprobe f2fs as it'll error out when mounting
# modprobe f2fs

#Update binfmt, this only needs to be done on non ARM platforms
update-binfmts --enable qemu-arm

IMAGENAME="$1"
IMAGESIZE="$2"
# IMAGENAME="Pyra"
# IMAGESIZE="4G"

OS=bookworm


# We only support buster and beyond, cover a few newer OSes
case $OS in 
buster)
OS_VERSION=10

;;
bullseye)
OS_VERSION=11
PYRA_ARCHIVE=bullseye
;;
bookworm)
OS_VERSION=12
PYRA_ARCHIVE=bookworm
;;
trixie)
echo "Not supported yet"
OS_VERSION=13
exit
;;
forky)
echo "Not supported yet"
OS_VERSION=14
exit
;;
sid)
##Sid generally has no version number so let's just go to 50
OS_VERSION=50
PYRA_ARCHIVE=unstable # probably needs to be bookworm for now
;;
default)
echo "Select a current OS"
exit
;;

esac

ARCHIVE_KEY="https://ftp-master.debian.org/keys/archive-key-$OS_VERSION.asc"
SECURITY_KEY="https://ftp-master.debian.org/keys/archive-key-$OS_VERSION-security.asc"
echo OS VERSION IS: $OS_VERSION
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
mkfs.ext2  -O encrypt -L rootfs "$PART_ROOTFS"

ROOTFS=$(mktemp -d)
mkdir -p "${ROOTFS}"
mount "${PART_ROOTFS}" "${ROOTFS}"

mkdir "${ROOTFS}"/boot
mount "${PART_BOOT}" "${ROOTFS}"/boot

mkdir -p "${DATA}/cache/debootstrap"
mkdir -p "${DATA}/cache/apt"
mkdir -p "${DATA}/keyrings"
curl -ffSL https://ftp-master.debian.org/keys/archive-key-$OS_VERSION.asc | sudo gpg --dearmor -o "${DATA}/keyrings/debian-archive-keyring-$OS_VERSION.gpg"

#Build image 
debootstrap --cache-dir="${DATA}"/cache/debootstrap --arch=armhf --keyring="${DATA}"/keyrings/debian-archive-keyring-$OS_VERSION.gpg --include=eatmydata,ca-certificates  "${OS}" "${ROOTFS}" http://deb.debian.org/debian
 
#Fetch the Pyra key, convert it to gpg (see apt-key deprecation)
 curl -fsSL https://packages.pyra-handheld.com/pyra-public.pgp | sudo gpg --dearmor -o "${ROOTFS}"/usr/share/keyrings/pyra-public.gpg

#Check if OS Version is greater than 11 or if sid mentioned in release file.
# When bullseye goes out of support we can descope this 
if [ "$OS_VERSION" -gt 11 ]; then
cat << EOF > "${ROOTFS}"/etc/apt/sources.list

#Debian Main
deb http://deb.debian.org/debian/ $OS main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ $OS main contrib non-free non-free-firmware
EOF

else
cat << EOF > "${ROOTFS}"/etc/apt/sources.list

#Debian Main
deb http://deb.debian.org/debian/ $OS main contrib non-free 
deb-src http://deb.debian.org/debian/ $OS main contrib non-free
EOF

fi

# Security Repo has changed in Bullseye and beyond. Security repo not used in sid or testing
if [ "$OS_VERSION" -gt 10 ]; then

cat << EOF >> "${ROOTFS}"/etc/apt/sources.list

# Security Repo
deb http://security.debian.org/debian-security $OS-security main contrib non-free
deb-src http://security.debian.org/debian-security $OS-security main
EOF
elif [ "$OS_VERSION" -lt 10 ]; then
cat << EOF >> "${ROOTFS}"/etc/apt/sources.list

# Security Repo
deb http://security.debian.org/ $OS/updates main non-free contrib
deb-src http://security.debian.org/ $OS/updates main non-free contrib
EOF
fi 

cat << EOF >> "${ROOTFS}"/etc/apt/sources.list.d/pyra-packages.list
deb [arch=armhf signed-by=/usr/share/keyrings/pyra-public.gpg] http://packages.pyra-handheld.com/ ${PYRA_ARCHIVE}/
EOF

chmod +x "${DATA}"/config.sh
chmod +x "${DATA}"/settings.debconf
cp "${DATA}"/config.sh "${ROOTFS}"/
cp "${DATA}"/settings.debconf "${ROOTFS}"/settings.debconf

ROOTPARTUUID=$(blkid -p "$PART_ROOTFS" -s PART_ENTRY_UUID -o value)
BOOTPARTUUID=$(blkid -p "$PART_BOOT" -s PART_ENTRY_UUID -o value)

cat > "${ROOTFS}"/etc/fstab << EOF
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
PARTUUID=${ROOTPARTUUID}  /               ext2    defaults        0       1
PARTUUID=${BOOTPARTUUID}  /boot           ext4    defaults        0       1

EOF


rm "${ROOTFS}"/var/cache/apt/* -rf
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
