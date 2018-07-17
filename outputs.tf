# terraform-aws-opnsense-cloud-image-builder
# ============================================================================

# Copyright (c) 2018 Verb Networks Pty Ltd <contact [at] verbnetworks.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# outputs
# ===

output "provider" {
  description = "The compute provider name."
  value = "aws"
}

output "region" {
  description = "The compute provider region identifier."
  value = "${var.aws_region}"
}

output "build_id" {
  description = "The build identifier used to generate this image."
  value = "${local.build_id}"
}

output "image_name" {
  description = "The image name given to this volume."
  value = "${local.image_name}"
}

output "image_action_outfile" {
  description = "The output file from the image action call to the compute provider."
  value = "${local.image_action_outfile}"
}
