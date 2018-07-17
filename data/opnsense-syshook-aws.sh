#!/bin/sh

# Copyright (c) 2018 Verb Networks Pty Ltd <contact [at] verbnetworks.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# configuration
CONFIG_FILE='/conf/config.xml'
XMLSTARLET_ERROR_FILES=1


# make sure required binaries are available on this system first
if [ $(which jq | wc -l | tr -d ' ') -lt 1 ]; then
    echo 'FATAL: missing required binary, "jq" - install "jq" package before using this tool'
    exit 1
fi

if [ $(which xml | wc -l | tr -d ' ') -lt 1 ]; then
    echo 'FATAL: missing required binary, "xml" - install "xmlstarlet" package before using this tool'
    exit 1
fi

if [ ! -e $CONFIG_FILE ]; then
    echo 'FATAL: unable to locate required config.xml file'
    exit 1
fi


aws_instancedata_sync()
{
    local local_path="$1"
    local aws_root="$2"

    # NB: defaults dealt with in long-hand because using {} approach causes Terraform to (attempt to) interpolate

    if [ -z "$local_path" ]; then
        local_path="/var/lib/cloud/instance/instance-data"
    fi

    if [ -z "$aws_root" ]; then
        aws_root="/"
    fi

    aws_instancedata_get()
    {
        local url
        local aws_path="$1"

        if [ "$aws_path" = "/meta-data/public-keys/" ]; then
            echo '0/openssh-key'
            return 0
        elif [ "$aws_path" = "/" ]; then
            printf "dynamic/\nmeta-data/\nuser-data"
            return 0
        else
            url="http://169.254.169.254/latest$aws_path"
        fi

        if [ $(uname | grep -i linux | wc -l) -gt 0 ]; then
            echo $(curl -s "$url" 2> /dev/null)
            return 0
        elif [ $(uname | grep -i freebsd | wc -l) -gt 0 ]; then
            echo $(fetch -q -o - "$url" 2> /dev/null)
            return 0
        fi

        return 1
    }

    aws_instancedata_walk()
    {
        local key
        local filename
        local local_path="$1"
        local aws_path="$2"

        for key in $(aws_instancedata_get "$aws_path"); do
            if [ $(echo -n $key | tail -c1) = "/" ]; then
                echo $(aws_instancedata_walk "$local_path" "$aws_path$key")
            else
                filename="$local_path$aws_path$key"
                mkdir -p $(dirname "$filename")
                echo $(aws_instancedata_get "$aws_path$key") > "$filename"
            fi
        done
    }

    if [ -z "$local_path" ] || [ "$local_path" = "/" ]; then
        echo "FATAL: bad $local_path value"
        exit 1
    fi
    rm -Rf "$local_path"
    mkdir -p "$local_path"

    aws_instancedata_walk "$local_path" "$aws_root"
}


opnsense_config_interface()
{
    local configfile="$CONFIG_FILE"
    local tempfile="/tmp/config-xmlstarlet-edit-$(date -u +%Y%m%dZ%H%M%S)-$(head /dev/urandom | md5 | head -c4)"

    local method="$1"
    local xpath="$2"
    local value="$3"
    local name
    local xpath_sub

    # create-insert - even if item at xpath exists
    if [ $method = "create" ]; then
        name=$(echo "$xpath" | rev | cut -f1 -d'/' | rev)
        xpath_sub=$(echo "$xpath" | rev | cut -f2- -d'/' | rev)
        xml ed -P -s "$xpath_sub" -t "elem" -n "$name" -v "$value" "$configfile" > "$tempfile"
        if [ "$(xml sel --template --value-of "$xpath" "$tempfile" | tail -n1)" = "$value" ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # read - only if xpath exists
    elif [ $method = "read" ]; then
        if [ ! -z "$(xml sel --template --copy-of "$xpath" "$configfile")" ]; then
            echo "$(xml sel --template --value-of "$xpath" "$configfile")"
            return 0
        fi

    # update - only if xpath exists
    elif [ $method = "update" ]; then
        if [ ! -z "$(xml sel --template --copy-of "$xpath" "$configfile")" ]; then
            xml ed -P -u "$xpath" -v "$value" "$configfile" > "$tempfile"
            if [ "$(xml sel --template --value-of "$xpath" "$tempfile")" = "$value" ]; then
                mv "$tempfile" "$configfile"
                return 0
            fi
        fi

    # delete - only if xpath exists
    elif [ $method = "delete" ]; then
        xml ed -P -d "$xpath" "$configfile" > "$tempfile"
        if [ -z "$(xml sel --template --value-of "$xpath" "$tempfile")" ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # upsert - update if xpath exists, insert-create if xpath not exist
    elif [ $method = "upsert" ]; then
        if [ ! -z "$(xml sel --template --copy-of "$xpath" "$configfile")" ]; then
            # update (up-)
            return $(opnsense_config_interface 'update' "$xpath" "$value")
        else
            # create-insert (-sert)
            return $(opnsense_config_interface 'create' "$xpath" "$value")
        fi
    fi

    # if we get this far we did not return above
    if [ -z "$XMLSTARLET_ERROR_FILES" ] || [ "$XMLSTARLET_ERROR_FILES" -eq 0 ]; then
        rm -f "$tempfile"
    else
        echo "opnsense_config_interface() fail" > "$tempfile.err"
        echo "method: $method" >> "$tempfile.err"
        echo "xpath: $xpath" >> "$tempfile.err"
        echo "value: $value" >> "$tempfile.err"
        echo "tempfile: $tempfile" >> "$tempfile.err"
    fi

    return 1
}

opnsense_syshook()
{
        # =====================================================================

        # interfaces
        public_interface=$(opnsense_config_interface read "//interfaces/public/if")
        private_interface=$(opnsense_config_interface read "//interfaces/private/if")

        # mac addresses - public interface
        if [ ! -z "$public_interface" ] && [ $(ifconfig | grep "^$public_interface" | wc -l | tr -d ' ') -gt 0 ]; then
            public_interface_mac=$(ifconfig "$public_interface" | grep hwaddr | cut -d' ' -f2)
        fi

        # mac addresses - private interface
        if [ ! -z "$private_interface" ] && [ $(ifconfig | grep "^$private_interface" | wc -l | tr -d ' ') -gt 0 ]; then
            private_interface_mac=$(ifconfig "$private_interface" | grep hwaddr | cut -d' ' -f2)
        fi

        # =====================================================================

        # meta_data
        aws_local_path="/var/lib/cloud/instance/instance-data"
        aws_instancedata_sync "$aws_local_path"

        # =====================================================================

        # instance user_data
        user_data=$(cat "$aws_local_path/user-data")
        user_data_script="/var/lib/cloud/instance/user-data.sh"

        # pull in the instance user_data and run only at the first boot
        if [ $(echo "$user_data" | wc -c | tr -d ' ') -gt 4 ] && [ ! -f "$user_data_script" ]; then
            mkdir -p $(dirname "$user_data_script")
            echo -n "$user_data" > "$user_data_script"
            chmod 700 "$user_data_script"

            echo "OPNsense Syshook: $user_data_script starting"
            echo $("$user_data_script")
            echo "OPNsense Syshook: $user_data_script finished"
        fi

        # =====================================================================

        echo "OPNsense Syshook: acquiring instance configuration attributes"

        # root_sshkey_data - NB: must be base64 encoded
        root_sshkey_data=$(cat "$aws_local_path/meta-data/public-keys/0/openssh-key" | b64encode -r - | tr -d '\n')

        # public_interface
        if [ ! -z $public_interface_mac ]; then
            # public.ipv4.ip_address
            public_ip4_addr=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$public_interface_mac/local-ipv4s" | head -n1)
            public_ip4_subnet=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$public_interface_mac/vpc-ipv4-cidr-blocks" | head -n1 | cut -d'/' -f2)
            public_ip4_gateway=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$public_interface_mac/vpc-ipv4-cidr-blocks" | head -n1 | rev | cut -d'.' -f2- | rev).1
            public_ip4_nameserver1=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$public_interface_mac/vpc-ipv4-cidr-blocks" | head -n1 | rev | cut -d'.' -f2- | rev).2
            public_ip4_nameserver2="169.254.169.253"  # https://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/vpc-dns.html#vpc-dns-support

            # public.ipv6.ip_address
            # TODO: this requires testing and confirmation !!
            public_ip6_addr=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$public_interface_mac/local-ipv6s" | head -n1)
            public_ip6_subnet=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$public_interface_mac/vpc-ipv6-cidr-blocks" | head -n1 | cut -d'/' -f2)
            public_ip6_gateway=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$public_interface_mac/vpc-ipv6-cidr-blocks" | head -n1 | rev | cut -d'.' -f2- | rev).1
        fi

        # private interface
        if [ ! -z $private_interface_mac ]; then
            # private.ipv4.ip_address
            private_ip4_addr=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$private_interface_mac/local-ipv4s" | head -n1)
            private_ip4_subnet=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$private_interface_mac/vpc-ipv4-cidr-blocks" | head -n1 | cut -d'/' -f2)

            # private.ipv6.ip_address
            # TODO: this requires testing and confirmation !!
            private_ip6_addr=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$private_interface_mac/local-ipv6s" | head -n1)
            private_ip6_subnet=$(cat "$aws_local_path/meta-data/network/interfaces/macs/$private_interface_mac/vpc-ipv6-cidr-blocks" | head -n1 | cut -d'/' -f2)
        fi

        # =====================================================================

        echo "OPNsense Syshook: applying ssh-key to root account in $CONFIG_FILE"

        # root user ssh key
        xpath="//system/user[contains(name,'root')]/authorizedkeys"
        opnsense_config_interface upsert "$xpath" "$root_sshkey_data"           || echo "OPNsense Syshook: failed to upsert $xpath"

        # =====================================================================

        echo "OPNsense Syshook: applying Instance IP address configuration data to $CONFIG_FILE"

        # inject AWS provided nameservers if none are set
        if [ -z $(opnsense_config_interface read "//system/dnsserver[1]") ]; then

            xpath="//system/dnsserver"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

            xpath="//system/dnsserver"
            opnsense_config_interface create "$xpath" "$public_ip4_nameserver1" || echo "OPNsense Syshook: failed to create $xpath[1]"

            xpath="//system/dnsserver"
            opnsense_config_interface create "$xpath" "$public_ip4_nameserver2" || echo "OPNsense Syshook: failed to create $xpath[2]"
        fi

        # public_ip4 address data if $public_ip4_addr is available
        echo "OPNsense Syshook: IPv4 to $public_interface"
        if [ ! -z "$public_ip4_addr" ] && [ "$public_ip4_addr" != "null" ]; then

            echo "OPNsense Syshook: Applying IPv4 on $public_interface"

            xpath="//interfaces/public/ipaddr"
            opnsense_config_interface upsert "$xpath" "$public_ip4_addr"        || echo "OPNsense Syshook: failed to upsert $xpath"

            xpath="//interfaces/public/subnet"
            opnsense_config_interface upsert "$xpath" "$public_ip4_subnet"      || echo "OPNsense Syshook: failed to upsert $xpath"

            xpath="//gateways/gateway_item[contains(name,'public4gw')]/gateway"
            opnsense_config_interface upsert "$xpath" "$public_ip4_gateway"     || echo "OPNsense Syshook: failed to upsert $xpath"

            xpath="//gateways/gateway_item[contains(name,'public4gw')]/disabled"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

        else

            echo "OPNsense Syshook: Removing IPv4 on $public_interface"

            xpath="//interfaces/public/ipaddr"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

            xpath="//interfaces/public/subnet"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

            xpath="//gateways/gateway_item[contains(name,'public4gw')]/gateway"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

            xpath="//gateways/gateway_item[contains(name,'public4gw')]/disabled"
            opnsense_config_interface upsert "$xpath" "1"                       || echo "OPNsense Syshook: failed to upsert $xpath"

        fi

        # public_ip6 address data if $public_ip6_addr is available
        echo "OPNsense Syshook: IPv6 to $public_interface"
        if [ ! -z "$public_ip6_addr" ] && [ "$public_ip6_addr" != "null" ]; then

            echo "OPNsense Syshook: Applying IPv6 on $public_interface"

            xpath="//interfaces/public/ipaddrv6"
            opnsense_config_interface upsert "$xpath" "$public_ip6_addr"        || echo "OPNsense Syshook: failed to upsert $xpath"

            xpath="//interfaces/public/subnetv6"
            opnsense_config_interface upsert "$xpath" "$public_ip6_subnet"      || echo "OPNsense Syshook: failed to upsert $xpath"

            xpath="//gateways/gateway_item[contains(name,'public6gw')]/gateway"
            opnsense_config_interface upsert "$xpath" "$public_ip6_gateway"     || echo "OPNsense Syshook: failed to upsert $xpath"

            xpath="//gateways/gateway_item[contains(name,'public6gw')]/disabled"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

        else

            echo "OPNsense Syshook: Removing IPv6 on $public_interface"

            xpath="//interfaces/public/ipaddrv6"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

            xpath="//interfaces/public/subnetv6"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

            xpath="//gateways/gateway_item[contains(name,'public6gw')]/gateway"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

            xpath="//gateways/gateway_item[contains(name,'public6gw')]/disabled"
            opnsense_config_interface upsert "$xpath" "1"                       || echo "OPNsense Syshook: failed to upsert $xpath"

        fi

        if [ -z "$public_interface_mac" ]; then
            xpath="//interfaces/public/enable"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"
        fi

        # private_ip4 address data if $private_ip4_addr is available
        echo "OPNsense Syshook: IPv4 to $private_interface"
        if [ ! -z "$private_ip4_addr" ] && [ "$private_ip4_addr" != "null" ]; then

            echo "OPNsense Syshook: Applying IPv4 on $private_interface"

            xpath="//interfaces/private/ipaddr"
            opnsense_config_interface upsert "$xpath" "$private_ip4_addr"       || echo "OPNsense Syshook: failed to upsert $xpath"

            xpath="//interfaces/private/subnet"
            opnsense_config_interface upsert "$xpath" "$private_ip4_subnet"     || echo "OPNsense Syshook: failed to upsert $xpath"

        else

            echo "OPNsense Syshook: Removing IPv4 on $private_interface"

            xpath="//interfaces/private/ipaddr"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

            xpath="//interfaces/private/subnet"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

        fi

        # private_ip6 address data if $private_ip6_addr is available
        echo "OPNsense Syshook: IPv6 to $private_interface"
        if [ ! -z "$private_ip6_addr" ] && [ "$private_ip6_addr" != "null" ]; then

            echo "OPNsense Syshook: Applying IPv6 on $private_interface"

            xpath="//interfaces/private/ipaddrv6"
            opnsense_config_interface upsert "$xpath" "$private_ip6_addr"       || echo "OPNsense Syshook: failed to upsert $xpath"

            xpath="//interfaces/private/subnetv6"
            opnsense_config_interface upsert "$xpath" "$private_ip6_subnet"     || echo "OPNsense Syshook: failed to upsert $xpath"

        else

            echo "OPNsense Syshook: Removing IPv6 on $private_interface"

            xpath="//interfaces/private/ipaddrv6"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

            xpath="//interfaces/private/subnetv6"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"

        fi

        if [ -z "$private_interface_mac" ]; then
            xpath="//interfaces/private/enable"
            opnsense_config_interface delete "$xpath"                           || echo "OPNsense Syshook: failed to delete $xpath"
        fi

        # =====================================================================

        echo "OPNsense Syshook: reloading full configuration"
        /usr/local/etc/rc.reload_all

        if [ ! -z "$public_interface_mac" ]; then
            /usr/local/opnsense/service/configd_ctl.py interface newip "$public_interface"
            /usr/local/opnsense/service/configd_ctl.py interface newipv6 "$public_interface"
        fi

        if [ ! -z "$private_interface_mac" ]; then
            /usr/local/opnsense/service/configd_ctl.py interface newip "$private_interface"
            /usr/local/opnsense/service/configd_ctl.py interface newipv6 "$private_interface"
        fi

        # =====================================================================

        echo "OPNsense Syshook: finished instance configuration"
}

opnsense_syshook
exit 0
