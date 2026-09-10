#!/bin/bash
set -e

echo "Installing podman and utilities..."
# Assuming Ubuntu/Debian-based
sudo apt-get update && sudo apt-get install -y podman wget curl unzip

echo "Installing AWS CLI..."
if ! command -v aws &> /dev/null; then
  cd /tmp
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
  unzip -q awscliv2.zip
  sudo ./aws/install
  rm -rf awscliv2.zip aws
  cd -
fi

echo "Installing cosign..."
# Must match the pin in .github/workflows/3-application.yml and deploy/ansible/site.yml.
# cosign v3 writes OCI 1.1 referrers that containers/image cannot read, so a host
# baked with v3 cannot verify what this pipeline signs.
COSIGN_VERSION="v2.6.5"
if ! command -v cosign &> /dev/null || ! cosign version 2>/dev/null | grep -q "$COSIGN_VERSION"; then
  cd /tmp
  curl -fsSL -O "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
  curl -fsSL -O "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign_checksums.txt"
  sha256sum --ignore-missing -c cosign_checksums.txt
  sudo install -m 0755 cosign-linux-amd64 /usr/local/bin/cosign
  rm -f cosign-linux-amd64 cosign_checksums.txt
  cd -
fi

echo "Applying Podman policy..."
sudo cp policy.json /etc/containers/policy.json

echo "Setting up Quadlet directory..."
sudo mkdir -p /etc/containers/systemd/

echo "Reloading systemd..."
sudo systemctl daemon-reload

echo "================================================================"
echo "Host bootstrap complete!"
echo "The podman-demo.container quadlet unit is not installed by this"
echo "script -- it is rendered and deployed by the Ansible playbook"
echo "(deploy/ansible/site.yml) on every pipeline run, pinned to the image"
echo "digest that was just built, signed (cosign keyless), and verified."
echo "Run the GitHub Actions 'Build and Deploy' workflow next to deploy."
echo "================================================================"
