# terraform-aws-opnsense-cloud-image-builder
# ============================================================================

# Copyright (c) 2018 Nicholas de Jong <contact[at]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# required variables - no defaults
# ===

variable "aws_region" {
  description = "The AWS region to start this aws-instance within"
}

variable "aws_access_key_id" {
  description = "Your AWS API key."
}

variable "aws_secret_access_key" {
  description = "Your AWS API secret key."
}

variable "opnsense_release" {
  description = "The OPNsense release to target for this image build"
}

# variables - with defined defaults
# ===

variable "root_passwd" {
  description = "The initial root password for OPNsense once the image is built."
  default = "opnsense"
}

variable "hostname" {
  description = "The hostname applied to this instance within the image build process only."
  default = "opnsense-cloud-image-builder"
}

variable "aws_ami_name_filter" {
  description = "Filter by name attribute to use to identify the most recent FreeBSD AMI"
  default = "FreeBSD 11.2-STABLE-amd64-*"   # this will require updates as OPNsense evolves with new versions
}

variable "aws_ami_virtualization_filter" {
  description = "Filter by virtualization-type attribute to use to identify the most recent FreeBSD AMI"
  default = "hvm"
}

variable "aws_ami_owners_filter" {
  description = "Filter by owners attribute to use to identify the most recent FreeBSD AMI"
  default = "118940168514" # NB: 118940168514 = FreeBSD
}

variable "aws_instance_type" {
  description = "The instance type to use for the aws-instance used on this build."
  default = "t2.medium"
}

variable "do_opnsense_install" {
  description = "Cause OPNsense to be installed once the instance is reachable."
  default = 1
}

variable "do_cleanup_shutdown" {
  description = "Cause the system to perform cleanup operations and then shutdown."
  default = 1
}

variable "do_image" {
  description = "Cause a Digital Ocean Droplet image to be taken of the Droplet while powered off."
  default = 1
}

variable "do_self_destruct" {
  description = "Cause the Droplet that was used to create the snapshot image to delete itself itself once the image is done."
  default = 1
}
