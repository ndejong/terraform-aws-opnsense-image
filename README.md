# Image Create :: OPNsense on AWS

Terraform module to create an AWS AMI snapshot-image that can subsequently be used to start an OPNsense instance 
within AWS.
 * [OPNsense](https://www.opnsense.org/)
 * [AWS](https://aws.amazon.com/)

This module provides an boot-time syshook for OPNsense that collects input parameters from the AWS meta-data service at 
http://169.254.169.254 and applies it as required to the OPNsense `config.xml` file at boot.  Config attributes that are
managed this way include:-
 - root user sshkey
 - Public and Private network interface cards
 - IPv4 address, subnet, gateway, dns
 - IPv6 address, subnet, gateway 

This allows the resulting OPNsense AMI to be used in regular Terraform devops automation situations.  Additionally, 
users of the resulting OPNsense instance can inject `user-data` scripts at initial instance boot, however the system
does not include cloudinit, so `user-data` scripts need to be contained `/bin/sh` scripts. 


## Usage
This module is mildly unusual in that the final result does **not** provide a running EC2 Instance.  The correct behaviour
of this module will result in an AWS AMI while the EV2 instance used in the process of creating the image will poweroff.

The example below shows an example setup - note that the **root_passwd** variable is optional and by default will
use the same default password that OPNsense uses, that is "opnsense" - be smart, change this because your OPNsense 
instance will be **publicly** accessible to begin with unless you take other measures to prevent inbound access to 
TCP22 (SSH) and TCP443 (HTTPS).

```hcl
variable "aws_access_key_id" {}       # set via environment value `TF_VAR_aws_access_key_id`
variable "aws_secret_access_key" {}   # set via environment value `TF_VAR_aws_secret_access_key`

module "opnsense-image" {
  source  = "verbnetworks/opnsense-image/aws"

  opnsense_release = "18.7"
  root_passwd = "honeyPot..."

  aws_region = "ap-southeast-1"
  aws_access_key_id = "${var.aws_access_key_id}"
  aws_secret_access_key = "${var.aws_secret_access_key}"

  do_opnsense_install = 1
  do_cleanup_shutdown = 1
  do_image = 1
  do_self_destruct = 1
}

output "provider" { value = "${module.opnsense-image.provider}"}
output "region" { value = "${module.opnsense-image.region}"}
output "build_id" { value = "${module.opnsense-image.build_id}"}
output "image_name" { value = "${module.opnsense-image.image_name}"}
output "image_action_outfile" { value = "${module.opnsense-image.image_action_outfile}"}
```

After the build process completes you should observe among the final Terraform log lines the following, thus indicating 
the build process is complete and the image is taking place on the Digital Ocean backend.
```text
action-status (local-exec): !!!!
action-status (local-exec): !!!! build_id: YDYAKA
action-status (local-exec): !!!! image_name: OPNsense 18.1 - 20180717Z102528
action-status (local-exec): !!!! image_action_outfile: /tmp/opnsense-YDYAKA-image-action.json
action-status (local-exec): !!!!
action-status (local-exec): !!!! Remember to terraform destroy resources once image action is complete
action-status (local-exec): !!!!
```

The user should perform a `terraform destroy` once complete to remove the resources that have allocated in the local 
`tfstate` - they can all safely be destroyed, the new AMI will not be removed in this destroy action because
the action to create the image is performed as a `local-exec` call via `awscli` thus preventing it from being a 
Terraform resource.

## Use your new AMI
You are now able to start a new AWS EC2 instance using the AMI that has been created for you.  Your new AMI will be
listed under the "My AMIs" section when you choose an Amazon Machine Image to start within the AWS console UI.

## Warning!
The default rules used in this arrangement differ from the default OPNsense rules in that they **allow** access to the 
OPNsense control interfaces via TCP22 (SSH) and TCP443 (HTTPS) to facilitate your initial connection(s) to the 
system for setup etc.

Leaving the system in this arrangement is **NOT** recommended and you should take steps to restrict the source 
addresses that can connect to your OPNsense control interfaces.


## Notes and Observations
 * The image "build" process leverages the OPNsense provided `opnsense-bootstrap.sh` tool to "convert" a FreeBSD 
   Droplet into an OPNsense one, check it out here - [https://github.com/opnsense/update](https://github.com/opnsense/update)
 * It is recommended that the user does not choose an instance size too small else the build will take a very long time,
   generally a t2.medium is appropriate for the build and will take approx 7 to 8 minutes.
 * You will see a **lot** of Terraform log output as the build process continues, keep in mind that builds can fail for 
   many surprising reasons, external packages may not download and kernel-panics have been observed, so it is worth
   keeping an eye on the Terraform logging output to make sure nothing really obvious is going wrong. 
 * Remember to issue the `terraform destroy` at the end, else you may become confused what state you are in the next
   time to come to roll another Droplet based OPNsense image.


## What about Packer?
Packer, also produced by Hashicorp is an awesome tool, but requires learning yet another tool-chain. Since the resulting 
Digital Ocean images are targeted at DevOps people that use Terraform, it just felt more natural to do the whole build
process in Terraform.


## Builds Confirmed
 * (v0.3.0) amazon-ami: **FreeBSD 11.2-STABLE-amd64-2018-07-09 (ami-36a0dedc)** > **OPNsense 18.1.12** (@ 2018-07-17T09:09:00Z)
 * (v0.3.1) amazon-ami: **FreeBSD 11.2-STABLE-amd64-2018-08-02 (ami-285012c2)** > **OPNsense 18.7.0** (@ 2018-08-05T15:12:13Z)


## Compute Providers Supported
 * [Amazon Web Services](https://github.com/verbnetworks/terraform-digitalocean-aws-image)
 * [Digital Ocean](https://github.com/verbnetworks/terraform-digitalocean-opnsense-image)


****


## Input Variables - Required

### opnsense_release
The OPNsense release to target for this image build

### digitalocean_region
The DigitalOcean region-slug to start this digitalocean-droplet within (nyc1, sgp1, lon1, nyc3, ams3, fra1, tor1, sfo2, blr1)

### digitalocean_token
Your DigitalOcean API token used to issue cURL API calls directly to DigitalOcean to create the required image


## Input Variables - Optional

### root_passwd
The initial root password for OPNsense once the image is built.
* default = "opnsense"

### hostname
The hostname applied to this digitalocean-droplet within the image build process only.
* default = "opnsense-image"

### digitalocean_image
The DigitalOcean image to use as the base for this digitalocean-droplet.
* default = "freebsd-11-1-x64"

### digitalocean_size
The size to use for this digitalocean-droplet.
* default = "s-1vcpu-1gb"

### digitalocean_ipv6
Enable/disable getting a public IPv6 on this digitalocean-droplet.
* default = true

### digitalocean_private_networking
Enable/disable private-networking functionality on this digitalocean-droplet.
* default = true

### do_opnsense_install
Cause OPNsense to be installed once the instance is reachable.
 - default = 1

### do_cleanup_shutdown
Cause the system to perform cleanup operations and then shutdown.
 - default = 1

### do_image
Cause a Digital Ocean Droplet image to be taken of the Droplet while powered off.
 - default = 1

### do_self_destruct
Cause the Droplet that was used to create the snapshot image to delete itself itself once the image is done.
 - default = 1


## Outputs

### provider
The compute provider name.

### region
The compute provider region identifier.

### build_id
The build identifier used to generate this image.

### image_name
The image name given to this volume.

### image_action_outfile
The output file from the image action call to the compute provider.


****


## Authors
Module managed by [Verb Networks](https://github.com/verbnetworks).

## License
Apache 2 Licensed. See LICENSE file for full details.
