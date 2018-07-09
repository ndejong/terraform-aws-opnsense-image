# terraform-digitalocean-opnsense-cloud-image-builder
# ============================================================================

# Copyright (c) 2018 Nicholas de Jong <contact[@]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# outputs
# ===

output "region" {
  description = "The compute provider region identifier."
  value = "${var.aws_region}"
}

output "build_id" {
  description = "The build identifier used to generate this image."
  value = "${random_string.build-id.result}"
}

output "image_id" {
  description = "The compute provider volume identifier assigned to the image generated."
  value = "${random_string.build-id.result}"
}

output "image_name" {
  description = "The image name given to this volume."
  value = "${null_resource.image-name.triggers.string}"
}

output "image_action_outfile" {
  description = "The output file from the image action call to the compute provider."
  value = "${null_resource.output-filename.triggers.string}"
}
