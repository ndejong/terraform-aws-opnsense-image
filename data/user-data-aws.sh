#!/bin/sh

# Copyright (c) 2018 Nicholas de Jong <contact[at]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0

# Cause the instance to allow root sshkey based console access for this build
mkdir -p /root/.ssh
fetch -o /root/.ssh/authorized_keys "http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key"

chown -R root /root/.ssh
chmod 700 /root/.ssh
chmod 600 /root/.ssh/*

sed -i -e '/.*PasswordAuthentication/s/^.*$/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i -e '/.*PubkeyAuthentication/s/^.*$/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i -e '/.*PermitRootLogin/s/^.*$/PermitRootLogin yes/' /etc/ssh/sshd_config

service sshd reload

# that's all to do here
exit 0
