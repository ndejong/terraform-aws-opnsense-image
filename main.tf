# terraform-aws-opnsense-cloud-image-builder
# ============================================================================

# Copyright (c) 2018 Verb Networks Pty Ltd <contact [at] verbnetworks.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0

# establish the AWS provider
provider "aws" {
  access_key = "${var.aws_access_key_id}"
  secret_key = "${var.aws_secret_access_key}"
  region     = "${var.aws_region}"
}

# local test to confirm aws cli is installed and has operational AWS credentials
# ===
resource "null_resource" "local-tests" {
  provisioner "local-exec" {
    command = <<EOF
      if [ $(which jq | wc -l) -lt 1 ]; then
        echo 'jq tool not installed on this system'
        exit 1
      fi
      if [ $(which aws | wc -l) -lt 1 ]; then
        echo 'awscli tool not installed on this system'
        exit 1
      else
        export AWS_ACCESS_KEY_ID=${var.aws_access_key_id}
        export AWS_SECRET_ACCESS_KEY=${var.aws_secret_access_key}
        aws --region=${var.aws_region} ec2 describe-regions > /dev/null
      fi
      if [ $? -gt 0 ]; then
        echo 'problem using awscli tools to confirm access'
        exit 1
      fi
    EOF
  }
}

# create a unique build-id value for this image build process
# ===
resource "random_string" "build-id" {
  length = 6
  lower = false
  upper = true
  number = true
  special = false

  depends_on = [ "null_resource.local-tests" ]
}

# Generate a temporary ssh keypair to bootstrap this instance
# ===
resource "tls_private_key" "terraform-bootstrap-sshkey" {
  algorithm = "RSA"
  rsa_bits = "4096"

  depends_on = ["null_resource.local-tests"]
}

# attach the temporary sshkey to the provider account for this image build
# ===
# !!!  NB: this ssh key remains in CLEAR TEXT in the terraform.tfstate file and can be extracted using:-
# !!!  $ cat terraform.tfstate | jq --raw-output '.modules[1].resources["tls_private_key.terraform-bootstrap-sshkey"].primary.attributes.private_key_pem'
# ===
resource "aws_key_pair" "terraform-bootstrap-sshkey" {
  key_name = "terraform-bootstrap-sshkey-${random_string.build-id.result}"
  public_key = "${tls_private_key.terraform-bootstrap-sshkey.public_key_openssh}"

  depends_on = [ "random_string.build-id", "tls_private_key.terraform-bootstrap-sshkey" ]
}

# FreeBSD uses configinit (not cloud-init) which interprets the user-data based on the first few bytes
# http://www.daemonology.net/blog/2013-12-09-FreeBSD-EC2-configinit.html
# ===
data "template_file" "instance-userdata" {
  template = "#!/bin/sh\necho -n '${base64gzip(file("${path.module}/data/user-data-aws.sh"))}' | b64decode -r | gunzip | /bin/sh"
  vars = { }

  depends_on = ["null_resource.local-tests"]
}

# create a VPC with all the required networking arrangements, we cannot rely on a "default" VPC being appropriate
# ===
resource "aws_vpc" "opnsense-cloud-builder" {
  cidr_block       = "192.168.42.0/24"
  enable_dns_support = true

  tags {
    Name = "opnsense-cloud-builder-${random_string.build-id.result}"
    Terraform = "true"
  }
  depends_on = ["null_resource.local-tests"]
}

resource "aws_subnet" "opnsense-cloud-builder-subnet" {
  vpc_id     = "${aws_vpc.opnsense-cloud-builder.id}"
  cidr_block = "192.168.42.0/28"
  map_public_ip_on_launch = true

  tags {
    Name = "opnsense-cloud-builder-${random_string.build-id.result}"
    Terraform = "true"
  }
  depends_on = ["aws_vpc.opnsense-cloud-builder"]
}

resource "aws_internet_gateway" "opnsense-cloud-builder-gw" {
  vpc_id     = "${aws_vpc.opnsense-cloud-builder.id}"

  tags {
    Name = "opnsense-cloud-builder-${random_string.build-id.result}"
    Terraform = "true"
  }
  depends_on = ["aws_vpc.opnsense-cloud-builder"]
}

resource "aws_route_table" "opnsense-cloud-builder-route" {
  vpc_id = "${aws_vpc.opnsense-cloud-builder.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.opnsense-cloud-builder-gw.id}"
  }

  tags {
    Name = "opnsense-cloud-builder-${random_string.build-id.result}"
    Terraform = "true"
  }
  depends_on = ["aws_internet_gateway.opnsense-cloud-builder-gw"]
}

resource "aws_route_table_association" "opnsense-cloud-builder-route-association" {
  subnet_id      = "${aws_subnet.opnsense-cloud-builder-subnet.id}"
  route_table_id = "${aws_route_table.opnsense-cloud-builder-route.id}"

  depends_on = ["aws_route_table.opnsense-cloud-builder-route", "aws_subnet.opnsense-cloud-builder-subnet"]
}

resource "aws_security_group" "opnsense-cloud-builder-allow" {
  name        = "opnsense-cloud-builder-allow-all"
  description = "opnsense-cloud-builder-allow-all"
  vpc_id      = "${aws_vpc.opnsense-cloud-builder.id}"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags {
    Name = "opnsense-cloud-builder-${random_string.build-id.result}"
    Terraform = "true"
  }
}

data "aws_ami" "ami-search" {
  most_recent = true
  filter {
    name   = "name"
    values = ["${var.aws_ami_name_filter}"]
  }
  filter {
    name   = "virtualization-type"
    values = ["${var.aws_ami_virtualization_filter}"]
  }
  owners = ["${var.aws_ami_owners_filter}"]
}

# start this temporary build instance
# ===
resource "aws_instance" "build-instance" {
  ami = "${data.aws_ami.ami-search.id}"
  instance_type = "${var.aws_instance_type}"
  subnet_id = "${aws_subnet.opnsense-cloud-builder-subnet.id}"
  vpc_security_group_ids = [ "${aws_security_group.opnsense-cloud-builder-allow.id}" ]
  key_name = "${aws_key_pair.terraform-bootstrap-sshkey.key_name}"
  source_dest_check = false

  user_data = "${data.template_file.instance-userdata.rendered}"

  connection {
    type = "ssh"
    user = "root"
    timeout = "600"
    agent = false
    private_key = "${tls_private_key.terraform-bootstrap-sshkey.private_key_pem}"
  }

  provisioner "remote-exec" {
    inline = [
      # wait until the aws package is installed which is an indication the firstboot is close to being finished
      "while [ $(which aws | wc -l | tr -d ' ') -lt 1 ]; do echo '===tail -n3 /var/log/messages==='; tail -n3 /var/log/messages; sleep 3; done",
      "sleep 5"
    ]
  }

  depends_on = [ "aws_route_table_association.opnsense-cloud-builder-route-association" ]

  tags {
    Name = "opnsense-cloud-image-builder-${random_string.build-id.result}"
    Terraform = "true"
  }
}

# render the config.xml with an (optionally different from default: opnsense) root passwd of the image builders choice
# ===
data "template_file" "opnsense-config-xml" {
  template = "${file("${path.module}/data/config-aws.xml")}"
  vars {
    opnsense_root_passwd_data = "${bcrypt(var.root_passwd, 10)}"
  }
}

# render the opnsense-syshook script, which implements the OPNsense <> Cloud-Provider functionality required
# ===
data "template_file" "opnsense-syshook-sh" {
  template = "${file("${path.module}/data/opnsense-syshook-aws.sh")}"
  vars = { }
}

# render the (one time) cloudinit-bootstrap script used to bring this instance to life for the opnsense-bootstrap build
# ===
data "template_file" "opnsense-install-sh" {
  template = "${file("${path.module}/data/opnsense-install.sh")}"
  vars {
    opnsense_release = "${var.opnsense_release}"
    opnsense_config_data = "${base64gzip(data.template_file.opnsense-config-xml.rendered)}"
    opnsense_syshook_data = "${base64gzip(data.template_file.opnsense-syshook-sh.rendered)}"
  }
}

# install opnsense via a remote ssh call
resource "null_resource" "opnsense-install-action" {
  count = "${var.do_opnsense_install}"

  connection {
    host = "${aws_instance.build-instance.public_ip}"
    type = "ssh"
    user = "root"
    timeout = "600"
    agent = false
    private_key = "${tls_private_key.terraform-bootstrap-sshkey.private_key_pem}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo -n '${base64gzip(data.template_file.opnsense-install-sh.rendered)}' | b64decode -r | gunzip | /bin/sh",
    ]
  }

  depends_on = [ "aws_instance.build-instance" ]
}

# do a final cleanup just before the instance does a shutdown-poweroff
# ===
resource "null_resource" "cleanup-shutdown-action" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown}"

  connection {
    host = "${aws_instance.build-instance.public_ip}"
    type = "ssh"
    user = "root"
    timeout = "60"
    agent = false
    private_key = "${tls_private_key.terraform-bootstrap-sshkey.private_key_pem}"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -f /etc/rc.conf",
      "rm -Rf /usr/home/ec2-user",  # aws
      "rm -Rf /usr/home/freebsd",   # digitalocean
      "rm -Rf /var/log/*",
      "rm -Rf /root/.ssh",
      "shutdown -p +20s"
    ]
  }

  depends_on = [ "null_resource.opnsense-install-action" ]
}

# query the provider API until this instance is no longer active
# ===
resource "null_resource" "instance-wait-poweroff" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown}"

  provisioner "local-exec" {
    command = <<EOF
      export AWS_ACCESS_KEY_ID=${var.aws_access_key_id}
      export AWS_SECRET_ACCESS_KEY=${var.aws_secret_access_key}
      while [ $(aws --region=${var.aws_region} ec2 describe-instance-status --instance-ids ${aws_instance.build-instance.id} | jq -r .InstanceStatuses[0].InstanceState.Name) = 'running' ]; do
          echo 'Waiting for instance ${aws_instance.build-instance.id} to stop running...'
          sleep 3
      done
    EOF
  }

  depends_on = [ "null_resource.cleanup-shutdown-action" ]
}

# establish local var values
# ===
locals {
  build_id = "${random_string.build-id.result}"
  image_name = "OPNsense ${var.opnsense_release} - ${replace(replace(replace(replace(timestamp(), ":", ""),"-",""),"Z",""),"T","Z")}"
  image_action_outfile = "/tmp/opnsense-${local.build_id}-image-action.json"
  image_action_idfile = "/tmp/opnsense-${local.build_id}-image-action.id"
}

# take a image of this instance via the AWS API so that it occurs outside Terraform and will not later be destroyed
# ===
resource "null_resource" "instance-snapshot-action" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown * var.do_image}"

  provisioner "local-exec" {
    command = <<EOF
      sleep 5
      export AWS_ACCESS_KEY_ID=${var.aws_access_key_id}
      export AWS_SECRET_ACCESS_KEY=${var.aws_secret_access_key}
      aws --region=${var.aws_region} ec2 create-image \
          --instance-id ${aws_instance.build-instance.id} \
          --no-reboot \
          --name "${local.image_name}" \
            > ${local.image_action_outfile}
      echo -n $(jq -r ".ImageId" ${local.image_action_outfile}) > ${local.image_action_idfile}
    EOF
  }

  depends_on = [ "null_resource.instance-wait-poweroff" ]
}

# Tag the AMI with a name
# ===
resource "null_resource" "instance-snapshot-tag" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown * var.do_image}"

  provisioner "local-exec" {
    command = <<EOF
      export AWS_ACCESS_KEY_ID=${var.aws_access_key_id}
      export AWS_SECRET_ACCESS_KEY=${var.aws_secret_access_key}
      aws --region=${var.aws_region} ec2 create-tags \
          --resources ${file(local.image_action_idfile)} \
          --tags Key=Name,Value="${local.image_name}"
    EOF
  }

  depends_on = [ "null_resource.instance-snapshot-action" ]
}


# force some Terraform log output so it is a little easier to immediately observe the final status
# ===
resource "null_resource" "action-status" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown * var.do_image}"

  provisioner "local-exec" {
    command = <<EOF
      echo ""
      echo "!!!! "
      echo "!!!! build_id: ${random_string.build-id.result}"
      echo "!!!! image_name: ${local.image_name}"
      echo "!!!! image_action_outfile: ${local.image_action_outfile}"
      echo "!!!! "
      echo "!!!! Remember to terraform destroy resources once image action is complete"
      echo "!!!! "
      echo ""
    EOF
  }
  depends_on = [ "null_resource.instance-snapshot-action" ]
}
