#!/bin/sh


ROOT_PASS="root"

DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND DEBCONF_NONINTERACTIVE_SEEN

debconf-set-selections /settings.debconf

echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/02apt-speedup
modprobe f2fs 

eatmydata apt update -y
eatmydata apt -o APT::Keep-Downloaded-Packages="true" upgrade -y 
#eatmydata apt -o APT::Install-Recommends="false" -o APT::Keep-Downloaded-Packages="true" install -y $@
eatmydata apt -o APT::Keep-Downloaded-Packages="true" install -y $@

mkdir -p /boot/dtb

linux-version list | while read -r version
do
    update-initramfs -c -k ${version}
    cp -u -r /usr/lib/linux-image-${version} /boot/dtb/
done

pyra-extlinux-update

passwd "root" <<EOF
$ROOT_PASS
$ROOT_PASS
EOF

echo pyra > /etc/hostname
rm /etc/resolv.conf

echo 'FONT="Lat15-Terminus24x12.psf.gz"' >> /etc/default/console-setup

#Temporary patch for Zenity, will move to YAD eventually
ln -s /usr/lib/arm-linux-gnueabihf/libffi.so.7 /usr/lib/arm-linux-gnueabihf/libffi.so.6

cd /installer
./make-installer-initrd.sh

systemctl enable serial-getty@ttyO2.service
rm /var/lib/pyra/first-run.done

rm /etc/dpkg/dpkg.cfg.d/02apt-speedup
sync
sleep 5
sync

