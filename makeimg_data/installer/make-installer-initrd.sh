#!/bin/sh

OUTDIR=${PWD}/out
mkdir -p ${OUTDIR}

LINUXVERSION=$(linux-version list | sort -r -V | head -1)

echo $LINUXVERSION
OUTIMG=initrd.img-${LINUXVERSION}-install
OUTRESIMG=initrd.img-${LINUXVERSION}-resize

echo $OUTIMG

mkinitramfs -v -d install-config -o ${OUTDIR}/${OUTIMG} ${LINUXVERSION}
#mkinitramfs -v -d resize-config -o ${OUTDIR}/${OUTRESIMG}  ${LINUXVERSION}


mkdir -p ${OUTDIR}/extlinux
cat > ${OUTDIR}/extlinux/extlinux.conf << EOF

## /boot/extlinux/extlinux.conf

menu title Pyra Installer
timeout 10
default install

label install
	menu label Pyra Installer ${LINUXVERSION}
	linux /vmlinuz-${LINUXVERSION}
	append console=tty0 vram=12M omapfb.vram=0:8M,1:4M omapfb.rotate_type=0 omapdss.def_disp=lcd rootwait twl4030_charger.allow_usb=1 musb_hdrc.preserve_vbus=1 log_buf_len=8M ignore_loglevel earlyprintk drm_kms_helper.fbdev_rotation=8 drm.force_hw_rotation fastboot
    fdtdir /dtb/linux-image-${LINUXVERSION}
	initrd /${OUTIMG}

EOF
cp -v /boot/vmlinuz-${LINUXVERSION} ${OUTDIR}
mkdir -p ${OUTDIR}/dtb
cp -rv /boot/dtb/linux-image-${LINUXVERSION} ${OUTDIR}/dtb/


 






