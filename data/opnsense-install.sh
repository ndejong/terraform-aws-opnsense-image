#!/bin/sh

# Copyright (c) 2018 Nicholas de Jong <contact[at]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0

# opnsense-install
# - this script is used to bootstrap our way from a FreeBSD instance into an OPNsense one that gets "converted" by the
#   opnsense-bootstrap.sh tool that we edit to prevent the default reboot behaviour at the end - this script will
#   not get run again in subsequent boots of the OPNsense image created

# Set some required resource source locations
opnsense_bootstrap_uri="https://raw.githubusercontent.com/opnsense/update/${opnsense_release}/bootstrap/opnsense-bootstrap.sh"

# install recent certificate root authority certs so we can more-safely fetch from the bootstrap source
pkg install -y ca_root_nss

# fetch the OPNsense bootstrap script
fetch -o /tmp/opnsense-bootstrap.sh "$opnsense_bootstrap_uri"

# remove the reboot at the end of the opnsense-bootstrap.sh script
sed -i -e '/.*reboot/s/^.*$/#opnsense-cloud-image-builder# reboot/' /tmp/opnsense-bootstrap.sh
chmod 755 /tmp/opnsense-bootstrap.sh

# call the patched OPNsense bootstrap script
/tmp/opnsense-bootstrap.sh -y

# Replace the alternate initial config.xml from $path.module/data/config.xml
echo -n '${opnsense_config_data}' | b64decode -r | gunzip > /usr/local/etc/config.xml

# Insert an OPNsense style syshook that injects address data into the config.xml from the meta data source
# NB: a change occurred between 18.1.10 and 18.1.11 where this path was > rc.syshook.d/50-opnsense-aws.start
echo -n '${opnsense_syshook_data}' | b64decode -r | gunzip > /usr/local/etc/rc.syshook.d/start/50-opnsense-aws
chmod 755 /usr/local/etc/rc.syshook.d/start/50-opnsense-aws

# Add FreeBSD packages manually rather than enabling the full FreeBSD repo here /usr/local/etc/pkg/repos/FreeBSD.conf
__freebsd_static_package_install()
{
    fetch -o /tmp/__static_package_install.txz "$1"
    pkg-static add /tmp/__static_package_install.txz
    rm -f /tmp/__static_package_install.txz
}

# The release is named statically so explicit version numbers can be safely used - OPNsense may upgrade them later
freebsd_package_base="https://pkg.freebsd.org/FreeBSD:11:`uname -m`/release_2/All"

__freebsd_static_package_install "$freebsd_package_base/oniguruma-6.8.1.txz"
__freebsd_static_package_install "$freebsd_package_base/jq-1.5_3.txz"
__freebsd_static_package_install "$freebsd_package_base/libgpg-error-1.28.txz"
__freebsd_static_package_install "$freebsd_package_base/libgcrypt-1.8.2.txz"
__freebsd_static_package_install "$freebsd_package_base/libxslt-1.1.32.txz"
__freebsd_static_package_install "$freebsd_package_base/xmlstarlet-1.6.1.txz"

exit 0
