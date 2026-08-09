#!/usr/bin/env bash
# Prepares the builder virtual machine for capture into the compute
# gallery: patches the OS and installs the organisation's baseline
# tooling. Runs on the machine through the Azure Run Command service.
#
# After this completes, capture the image with:
#   az vm deallocate / az vm generalize / az sig image-version create
# (having run `waagent -deprovision+user` for a generalised image).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Patch the operating system.
apt-get update
apt-get upgrade -y

# Baseline tooling every image ships with.
apt-get install -y \
  ca-certificates \
  curl \
  jq \
  unattended-upgrades

# Enable automatic security updates in the image.
systemctl enable unattended-upgrades

# Trim the image before capture.
apt-get autoremove -y
apt-get clean

echo "Image preparation complete."
