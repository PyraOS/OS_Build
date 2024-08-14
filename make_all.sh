#!/bin/sh

if [ "$#" -lt 3 ] ; then echo "Usage: $0 output.img imagesize packages ( $0 output.img 4G pyra-meta-mate )" ; exit 1; fi
if [ $(id -u) -ne 0 ] ; then echo "Must be run as root"; exit 1; fi

IMAGENAME=$1
./makeimg.sh $@
./sd-installer.sh ${IMAGENAME}

