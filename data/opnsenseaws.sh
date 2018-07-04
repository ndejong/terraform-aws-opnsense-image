#!/bin/sh

# Copyright (c) 2018 Nicholas de Jong <contact[at]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0

__opnsenseaws_ipv4_mask_to_subnet()
{
    case $1 in

        "255.255.0.0")
            subnet=16
            ;;
        "255.255.128.0")
            subnet=17
            ;;
        "255.255.192.0")
            subnet=18
            ;;
        "255.255.224.0")
            subnet=19
            ;;
        "255.255.240.0")
            subnet=20
            ;;
        "255.255.248.0")
            subnet=21
            ;;
        "255.255.252.0")
            subnet=22
            ;;
        "255.255.254.0")
            subnet=23
            ;;
        "255.255.255.0")
            subnet=24
            ;;
        "255.255.255.128")
            subnet=25
            ;;
        "255.255.255.192")
            subnet=26
            ;;
        "255.255.255.224")
            subnet=27
            ;;
        "255.255.255.240")
            subnet=28
            ;;
        "255.255.255.248")
            subnet=29
            ;;
        "255.255.255.252")
            subnet=30
            ;;
        *)
            subnet=32
            ;;
    esac
    echo $subnet
}

__opnsenseaws_config()
{
    configfile="/conf/config.xml"
    tempfile="/tmp/config-xmlstarlet-edit-`date -u +%Y%m%dZ%H%M%S`-`head /dev/urandom | md5 | head -c4`.tmp"

    method="$1"
    xpath="$2"
    value="$3"

    # CRUD - create
    if [ $method == "create" ]; then
        name=$(echo "$xpath" | rev | cut -f1 -d'/' | rev)
        xpath_sub=$(echo "$xpath" | rev | cut -f2- -d'/' | rev)
        xml ed -P -s "$xpath_sub" -t "elem" -n "$name" -v "$value" "$configfile" > "$tempfile"
        if [ $(xml sel -t -v "$xpath" "$tempfile" | tail -n1) == "$value" ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # CRUD - read
    elif [ $method == "read" ]; then
        echo "$(xml sel -t -v "$xpath" "$configfile")"
        return 0

    # CRUD - update
    elif [ $method == "update" ]; then
        xml ed -P -u "$xpath" -v "$value" "$configfile" > "$tempfile"
        if [ $(xml sel -t -v "$xpath" "$tempfile") == "$value" ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # CRUD - delete
    elif [ $method == "delete" ]; then
        xml ed -P -d "$xpath" "$configfile" > "$tempfile"
        if [ -z $(xml sel -t -v "$xpath" "$tempfile") ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # CRUD - upsert
    elif [ $method == "upsert" ]; then
        # update (up-)
        if [ ! -z $(xml sel -t -v "$xpath" "$configfile") ]; then
            xml ed -P -u "$xpath" -v "$value" "$configfile" > "$tempfile"
            if [ $(xml sel -t -v "$xpath" "$tempfile") == "$value" ]; then
                mv "$tempfile" "$configfile"
                return 0
            fi
        # create (-sert)
        else
            name=$(echo "$xpath" | rev | cut -f1 -d'/' | rev)
            xpath_sub=$(echo "$xpath" | rev | cut -f2- -d'/' | rev)
            xml ed -P -s "$xpath_sub" -t "elem" -n "$name" -v "$value" "$configfile" > "$tempfile"
            if [ $(xml sel -t -v "$xpath" "$tempfile") == "$value" ]; then
                mv "$tempfile" "$configfile"
                return 0
            fi
        fi
    fi

    return 1
}

opnsenseaws_start()
{
        meta_data="http://169.254.169.254/latest/meta-data/"

        # Mount the AWS config_drive if not already
        if [ $(mount | grep '/dev/vtbd1' | wc -l | tr -d ' ') -lt 1 ]; then
            echo "OPNsense AWS: mount config_drive"
            mkdir -p /var/lib/cloud/seed/config_drive
            mount_cd9660  -o ro -v /dev/vtbd1 /var/lib/cloud/seed/config_drive || echo "OPNsense AWS: failed to mount config drive"
        else
            echo "OPNsense AWS: config_drive already mounted"
        fi

        # =====================================================================

        # instance user_data
        user_data=$(jq -r -M '.user_data' $meta)

        if [ ! -z "$user_data" ] && [ ! -f "/var/lib/cloud/instance/user_data.sh" ]; then
            echo "OPNsense AWS: sending b64decode+gunzip(user_data) to /bin/sh"
            mkdir -p /var/lib/cloud/instance
            echo -n "$user_data" > /var/lib/cloud/instance/user_data
            cat /var/lib/cloud/instance/user_data | b64decode -r | gunzip > /var/lib/cloud/instance/user_data.sh
            if [ $(cat /var/lib/cloud/instance/user_data | wc -c | tr -d ' ') -gt 0 ]; then
                chmod 700 /var/lib/cloud/instance/user_data.sh
                /bin/sh /var/lib/cloud/instance/user_data.sh
            else
                rm -f /var/lib/cloud/instance/user_data.sh
                echo "OPNsense AWS: ERROR unable to decode b64decode+gunzip(user_data) to pass to /bin/sh"
            fi
        fi

        # =====================================================================

        # root_sshkey_data
        root_sshkey_data=$(jq -r -M '.public_keys[0]' $meta | b64encode -r - | tr -d '\n')

        echo "OPNsense AWS: applying ssh-key to root account in /conf/config.xml"

        __opnsenseaws_config upsert "//system/user[contains(name,'root')]/authorizedkeys" "$root_sshkey_data" \
            || echo "OPNsense AWS: failed to create //system/user[contains(name,'root')]/authorizedkeys"

        # =====================================================================

        echo "OPNsense AWS: acquiring Instance IP address configuration attributes"

        # interfaces
        public_interface=$(__opnsenseaws_config read "//interfaces/public/if")
        private_interface=$(__opnsenseaws_config read "//interfaces/private/if")

        # public.ipv4.ip_address
        public_ip4_addr=$(jq -r -M '.interfaces.public[0].ipv4.ip_address' $meta)
        public_ip4_mask=$(jq -r -M '.interfaces.public[0].ipv4.netmask' $meta)
        public_ip4_gateway=$(jq -r -M '.interfaces.public[0].ipv4.gateway' $meta)
        public_ip4_nameserver1=$(cat /var/lib/cloud/seed/config_drive/openstack/content/000r | grep nameserver | cut -d' ' -f2 | head -n1)
        public_ip4_nameserver2=$(cat /var/lib/cloud/seed/config_drive/openstack/content/000r | grep nameserver | cut -d' ' -f2 | tail -n1)

        # public.ipv6.ip_address
        public_ip6_addr=$(jq -r -M '.interfaces.public[0].ipv6.ip_address' $meta)
        public_ip6_cidr=$(jq -r -M '.interfaces.public[0].ipv6.cidr' $meta)
        public_ip6_gateway=$(jq -r -M '.interfaces.public[0].ipv6.gateway' $meta)

        # private.ipv4.ip_address
        private_ip4_addr=$(jq -r -M '.interfaces.private[0].ipv4.ip_address' $meta)
        private_ip4_mask=$(jq -r -M '.interfaces.private[0].ipv4.netmask' $meta)

        # =====================================================================

        echo "OPNsense AWS: applying Instance IP address configuration data to /conf/config.xml"

        # inject AWS provided nameservers if none have been set
        if [ -z $(__opnsenseaws_config read "//system/dnsserver[1]") ]; then
            __opnsenseaws_config create "//system/dnsserver" "$public_ip4_nameserver1" \
                || echo "OPNsense AWS: failed to create //system/dnsserver[1]"
            __opnsenseaws_config create "//system/dnsserver" "$public_ip4_nameserver2" \
                || echo "OPNsense AWS: failed to create //system/dnsserver[2]"
        fi

        # inject private_ip4 address data if offered
        if [ ! -z $private_ip4_addr ] && [ $private_ip4_addr != "null" ]; then

            __opnsenseaws_config update "//interfaces/private/ipaddr" "$private_ip4_addr" \
                || echo "OPNsense AWS: failed to set //interfaces/private/ipaddr"

            __opnsenseaws_config update "//interfaces/private/subnet" $(__opnsenseaws_ipv4_mask_to_subnet "$private_ip4_mask") \
                || echo "OPNsense AWS: failed to set //interfaces/private/subnet"

            __opnsenseaws_config upsert "//interfaces/private/enable" "1" \
                || echo "OPNsense AWS: failed to set //interfaces/private/enable"

            echo -n "OPNsense AWS: Applying private IPv4 to $private_interface: "

        else
            __opnsenseaws_config update "//interfaces/private/ipaddr" "null" \
                || echo "OPNsense AWS: failed to upsert //interfaces/private/ipaddr"

            __opnsenseaws_config update "//interfaces/private/subnet" "32" \
                || echo "OPNsense AWS: failed to upsert //interfaces/private/subnet"

            __opnsenseaws_config delete "//interfaces/private/enable" \
                || echo "OPNsense AWS: failed to remove //interfaces/private/enable"

            echo -n "OPNsense AWS: Removing private IPv4 on $private_interface: "
        fi
        /usr/local/opnsense/service/configd_ctl.py interface newip $private_interface

        #echo -n "OPNsense AWS: Reconfiguring $private_interface: "
        #/usr/local/opnsense/service/configd_ctl.py interface reconfigure $private_interface

        # inject public_ip4 address data if offered
        if [ ! -z $public_ip4_addr ] && [ $public_ip4_addr != "null" ]; then

            __opnsenseaws_config update "//interfaces/public/ipaddr" "$public_ip4_addr" \
                || echo "OPNsense AWS: failed to set //interfaces/public/ipaddr"

            __opnsenseaws_config update "//interfaces/public/subnet" $(__opnsenseaws_ipv4_mask_to_subnet "$public_ip4_mask") \
                || echo "OPNsense AWS: failed to set //interfaces/public/subnet"

            __opnsenseaws_config update "//gateways/gateway_item[contains(name,'public4gw')]/gateway" "$public_ip4_gateway" \
                || echo "OPNsense AWS: failed to set //gateways/gateway_item[contains(name,'public4gw')]/gateway"

            __opnsenseaws_config delete "//gateways/gateway_item[contains(name,'public4gw')]/disabled" \
                || echo "OPNsense AWS: failed to remove //gateways/gateway_item[contains(name,'public4gw')]/disabled"

            echo -n "OPNsense AWS: Applying public IPv4 to $public_interface: "

        else
            __opnsenseaws_config update "//interfaces/public/ipaddr" "null" \
                || echo "OPNsense AWS: failed to set //interfaces/public/ipaddr"

            __opnsenseaws_config update "//interfaces/public/subnet" "32" \
                || echo "OPNsense AWS: failed to set //interfaces/public/subnet"

            __opnsenseaws_config update "//gateways/gateway_item[contains(name,'public4gw')]/gateway" "null" \
                || echo "OPNsense AWS: failed to set //gateways/gateway_item[contains(name,'public4gw')]/gateway"

            __opnsenseaws_config create "//gateways/gateway_item[contains(name,'public4gw')]/disabled" "1" \
                || echo "OPNsense AWS: failed to set //gateways/gateway_item[contains(name,'public4gw')]/disabled"

            echo -n "OPNsense AWS: Removing public IPv4 on $public_interface: "
        fi
        /usr/local/opnsense/service/configd_ctl.py interface newip $public_interface

        # inject public_ip6 address data if offered
        if [ ! -z $public_ip6_addr ] && [ $public_ip6_addr != "null" ]; then

             __opnsenseaws_config update "//interfaces/public/ipaddrv6" "$public_ip6_addr" \
                || echo "OPNsense AWS: failed to set //interfaces/public/ipaddrv6"

            __opnsenseaws_config update "//interfaces/public/subnetv6" "$public_ip6_cidr" \
                || echo "OPNsense AWS: failed to set //interfaces/public/subnetv6"

            __opnsenseaws_config update "//gateways/gateway_item[contains(name,'public6gw')]/gateway" "$public_ip6_gateway" \
                || echo "OPNsense AWS: failed to set //gateways/gateway_item[contains(name,'public6gw')]/gateway"

            __opnsenseaws_config delete "//gateways/gateway_item[contains(name,'public6gw')]/disabled" \
                || echo "OPNsense AWS: failed to remove //gateways/gateway_item[contains(name,'public6gw')]/disabled"

            echo -n "OPNsense AWS: Applying public IPv6 to $public_interface: "

        else
            __opnsenseaws_config update "//interfaces/public/ipaddrv6" "null" \
                || echo "OPNsense AWS: failed to set //interfaces/public/ipaddrv6"

            __opnsenseaws_config update "//interfaces/public/subnetv6" "32" \
                || echo "OPNsense AWS: failed to set //interfaces/public/subnetv6"

            __opnsenseaws_config update "//gateways/gateway_item[contains(name,'public6gw')]/gateway" "null" \
                || echo "OPNsense AWS: failed to set //gateways/gateway_item[contains(name,'public6gw')]/gateway"

            __opnsenseaws_config create "//gateways/gateway_item[contains(name,'public6gw')]/disabled" "1" \
                || echo "OPNsense AWS: failed to set //gateways/gateway_item[contains(name,'public6gw')]/disabled"

            echo -n "OPNsense AWS: Removing public IPv6 on $public_interface: "
        fi
       /usr/local/opnsense/service/configd_ctl.py interface newipv6 $public_interface

        #echo -n "OPNsense AWS: Reconfiguring $public_interface: "
        #/usr/local/opnsense/service/configd_ctl.py interface reconfigure $public_interface

        echo "OPNsense AWS: finished instance configuration"
}

opnsenseaws_start
exit 0
