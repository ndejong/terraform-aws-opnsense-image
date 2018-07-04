# terraform-aws-opnsense-cloud-image-builder
# ============================================================================

# Copyright (c) 2018 Nicholas de Jong <contact[@]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# outputs
# ===

output "region" {
  description = "The AWS region-slug this aws-instance is running in."
  value = "${var.aws_region}"
}

output "image_name" {
  description = "The image name used for this Instance image."
  value = "${null_resource.image_name.triggers.string}"
}

output "action_status" {
  description = "The Instance image action response data received from the AWS API."
  value = "/tmp/opnsense-aws-${random_string.build-id.result}-snapshot-action.json"
}

