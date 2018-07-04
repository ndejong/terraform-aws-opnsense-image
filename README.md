# Terraform + AWS + OPNsense :: AMI Builder

Terraform module to create a AWS Instance snapshot-image that can subsequently be used to start 
an OPNsense instance within AWS.
 * [OPNsense](https://www.opnsense.org/)
 * [AWS](https://www.aws.com/)

Of particular note is the support for the AWS (OpenStack based) approach to providing Instances 
their seed data, including public-IPv4, public-IPv6, private-IPv4, root-sshkey and user-data which is all
be parsed and injected into the OPNsense `/conf/config.xml` file at Instance boot.  This allows the resulting 
OPNsense image to be used in Terraform devops automation situations.

Users of the resulting OPNsense image may additionally wish to implement user_data that fetches an external
`confg.xml` file and places it in the usual `/conf/config.xml` location, which will be loaded at startup.

```bash
#!/bin/sh
fetch -o "/conf/config.xml" "https://your-awesome-hosting/opnsense-backups/latest.xml"
```


## Usage
This module is mildly unusual in that the final result does not provide a running Instance.  The correct behaviour
of this module will result in a AWS Instance image while the Instance used in the process of creating the 
image will self destruct.  The self destruct behaviour can be optionally disabled by toggling the `self_destruct` 
variable which can be useful in situations that require debugging.

The example below shows an example setup - note that the **root_passwd** variable is optional and by default will
use the same default password that OPNsense uses, that is "opnsense" - be smart, change this as your OPNsense 
instance will be publicly accessible to begin with.

```hcl
variable "do_token" {}

module "opnsense-cloud-image-builder" {
  source  = "ndejong/opnsense-cloud-image-builder/aws"

  aws_region = "sgp1"
  aws_token = "${var.do_token}"
  opnsense_release = "18.1"

  root_passwd = "honeyPot.."
}

output "image_name" { value = "${module.opnsense-cloud-image-builder.image_name}"}
output "action_status" { value = "${module.opnsense-cloud-image-builder.action_status}"}
```


## Warning!
The default rules used in this arrangement differ from the default OPNsense rules in that they **allow** access to the 
OPNsense control interfaces via TCP22 (SSH) and TCP443 (HTTPS) to facilitate your initial connection(s) to the 
system for setup etc.

Leaving the system in this arrangement is **NOT** recommended and you should take steps to restrict the source 
addresses that can connect to your OPNsense control interfaces.


## Notes and Observations
 * The image "build" process leverages the OPNsense provided `opnsense-bootstrap.sh` tool to "convert" a FreeBSD 
   Instance into an OPNsense one, check it out here - https://github.com/opnsense/update
 * Builds generally take around 10 minutes when using a small-sized AWS Instance size - you will see a lot
   of output as the process continues.
 * Builds can fail for many reasons, external packages may not download, kernel-panics have been observed and 
   the AWS API can act mysteriously at times. 


## Input Variables - Required

### aws_region
The AWS region-slug to start this aws-instance within (nyc1, sgp1, lon1, nyc3, ams3, fra1, tor1, sfo2, blr1)

### aws_token
Your AWS API token used to issue cURL API calls directly to AWS to create the required image

### opnsense_release
The OPNsense release to target for this image build


## Input Variables - Optional

### root_passwd
The initial root password for OPNsense once the image is built.
* default = "opnsense"


### hostname
The hostname applied to this aws-instance within the image build process only.
* default = "opnsense-cloud-image-builder"

### self_destruct
Cause the Instance used to create the snapshot image to self destruct itself once complete.
* default = 1

### aws_image
The AWS image to use as the base for this aws-instance.
* default = "freebsd-11-1-x64"

### aws_size
The size to use for this aws-instance.
* default = "s-1vcpu-1gb"

### aws_backups
Enable/disable backup functionality on this aws-instance - untested with OPNsense
* default = false

### aws_monitoring
Enable/disable monitoring functionality on this aws-instance - untested with OPNsense
* default = false

### aws_ipv6
Enable/disable getting a public IPv6 on this aws-instance.
* default = true

### aws_private_networking
Enable/disable private-networking functionality on this aws-instance.
* default = true


## Outputs

### region
The AWS region-slug this aws-instance is running in.

### image_name
The image name used for this Instance image.

### action_status
The Instance image action response data received from the AWS API.


## Authors
Module managed by [Nicholas de Jong](https://github.com/ndejong).

## License
Apache 2 Licensed. See LICENSE file for full details.
