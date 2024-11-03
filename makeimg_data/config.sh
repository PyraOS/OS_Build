#!/bin/sh


ROOT_PASS="root"

DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND DEBCONF_NONINTERACTIVE_SEEN

debconf-set-selections /settings.debconf

echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/02apt-speedup

eatmydata apt update -y
eatmydata apt -o APT::Keep-Downloaded-Packages="true" upgrade -y 
#eatmydata apt -o APT::Install-Recommends="false" -o APT::Keep-Downloaded-Packages="true" install -y $@
eatmydata apt -o APT::Keep-Downloaded-Packages="true" install -y $@


#Install Community Patches 

echo "Applying Community Patches" 

git clone "https://github.com/PyraOS/Additional_Scripts"

target_dir="Additional_Scripts"

# Check if the target directory exists
if [ -d "$target_dir" ]; then
    # Unzip all zip files inside the target directory, ignoring __MACOSX
    for zip in "$target_dir"/*.zip; do
        if [ -f "$zip" ]; then
            unzip "$zip" -d "$target_dir"
            # Remove any __MACOSX directory if it exists
            rm -rf "$target_dir"/__MACOSX
        else
            echo "No zip files found in $target_dir."
        fi
    done

    # Find and execute all .sh scripts in the target directory and its subdirectories, ignoring __MACOSX
    find "$target_dir" -type f -name "*.sh" | while read -r script; do
        if [ -f "$script" ]; then
            echo "Running $script..."
            bash "$script"  # Execute the script
        else
            echo "No .sh files found."
        fi
    done
else
    echo "Directory $target_dir does not exist."
fi

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

