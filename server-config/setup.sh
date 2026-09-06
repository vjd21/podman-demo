#!/bin/bash
set -e

echo "Installing podman and utilities..."
# Assuming Ubuntu/Debian-based
sudo apt-get update && sudo apt-get install -y podman wget

echo "Applying Podman policies and registry config..."
sudo mkdir -p /etc/pki/containers/
sudo mkdir -p /etc/containers/registries.d/
sudo cp policy.json /etc/containers/policy.json
sudo cp registries.yaml /etc/containers/registries.d/podman-demo.yaml

echo "Setting up Quadlet directory..."
sudo mkdir -p /etc/containers/systemd/

echo "Reloading systemd..."
sudo systemctl daemon-reload

echo "================================================================"
echo "Host bootstrap complete!"
echo "The podman-demo.container quadlet unit and cosign.pub signing key"
echo "are not installed by this script -- they are rendered and"
echo "deployed by the Ansible playbook (ansible/deploy.yml) on every"
echo "pipeline run, pinned to the image digest that was just built,"
echo "signed (via AWS KMS), and verified."
echo "Run the GitHub Actions 'Build and Deploy' workflow next to deploy."
echo "================================================================"
