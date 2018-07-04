#!/bin/sh

# Copyright (c) 2018 Nicholas de Jong <contact[at]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0

# cloudinit-bootstrap
# - this script is used to bootstrap our way from a FreeBSD instance into an OPNsense one that gets "converted" by the
#   opnsense-bootstrap.sh tool that we patch ever so slightly to prevent the default reboot behaviour - this script will
#   not get run again in subsequent boots of the OPNsense image created

# Set some required resource source locations
opnsense_bootstrap_uri="https://raw.githubusercontent.com/opnsense/update/${opnsense_release}/bootstrap/opnsense-bootstrap.sh"

# install recent certificate root authority certs so we can more-safely fetch from the bootstrap source
pkg install -y ca_root_nss

# fetch the OPNsense bootstrap script
fetch -o /tmp/opnsense-bootstrap.sh "$opnsense_bootstrap_uri"

# patch the OPNsense bootstrap script to suit our install requirement
echo -n '${opnsense_bootstrap_patch_data}' | b64decode -r | gunzip > /tmp/opnsense-bootstrap.patch
patch /tmp/opnsense-bootstrap.sh /tmp/opnsense-bootstrap.patch
chmod 755 /tmp/opnsense-bootstrap.sh

# call the patched OPNsense bootstrap script
/tmp/opnsense-bootstrap.sh -y

# Replace the alternate initial config.xml from $path.module/data/config.xml
echo -n '${opnsense_config_data}' | b64decode -r | gunzip > /usr/local/etc/config.xml

# Insert an OPNsense style syshook that injects address data into the config.xml from AWS instance meta data source
echo -n '${opnsenseaws_rc_data}' | b64decode -r | gunzip > /usr/local/etc/rc.syshook.d/12-opnsenseaws.early
chmod 755 /usr/local/etc/rc.syshook.d/12-opnsenseaws.early

# Add FreeBSD packages manually rather than enabling the full FreeBSD repo here /usr/local/etc/pkg/repos/FreeBSD.conf
__freebsd_static_package_install()
{
    fetch -o /tmp/__static_package_install.txz "$1"
    pkg-static add /tmp/__static_package_install.txz
    rm -f /tmp/__static_package_install.txz
}

# a release is static so version numbers can be used below
freebsd_package_base="https://pkg.freebsd.org/FreeBSD:11:`uname -m`/release_2/All"

__freebsd_static_package_install "$freebsd_package_base/oniguruma-6.8.1.txz"
__freebsd_static_package_install "$freebsd_package_base/jq-1.5_3.txz"
__freebsd_static_package_install "$freebsd_package_base/libgpg-error-1.28.txz"
__freebsd_static_package_install "$freebsd_package_base/libgcrypt-1.8.2.txz"
__freebsd_static_package_install "$freebsd_package_base/libxslt-1.1.32.txz"
__freebsd_static_package_install "$freebsd_package_base/xmlstarlet-1.6.1.txz"

# Remove things that do not belong under OPNsense and that we will not want in an image
rm -f /etc/rc.conf
rm -Rf /usr/home/freebsd/.ssh

rm -Rf /var/log/*

exit 0
