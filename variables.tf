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
  description = "The AWS region-slug to start this aws-instance within (nyc1, sgp1, lon1, nyc3, ams3, fra1, tor1, sfo2, blr1)"
}

variable "aws_token" {
  description = "Your AWS API token used to issue cURL API calls directly to AWS to create the required image"
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
  description = "The hostname applied to this aws-instance within the image build process only."
  default = "opnsense-cloud-image-builder"
}

variable "self_destruct" {
  description = "Cause the Instance used to create the snapshot image to self destruct itself once complete."
  default = 1
}

variable "aws_image" {
  description = "The AWS image to use as the base for this aws-instance."
  default = "freebsd-11-1-x64"
}

variable "aws_size" {
  description = "The size to use for this aws-instance."
  default = "s-1vcpu-1gb"
}

variable "aws_backups" {
  description = "Enable/disable backup functionality on this aws-instance - untested with OPNsense"
  default = false
}

variable "aws_monitoring" {
  description = "Enable/disable monitoring functionality on this aws-instance - untested with OPNsense"
  default = false
}

variable "aws_ipv6" {
  description = "Enable/disable getting a public IPv6 on this aws-instance."
  default = true
}

variable "aws_private_networking" {
  description = "Enable/disable private-networking functionality on this aws-instance."
  default = true
}
