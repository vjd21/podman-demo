#!/bin/bash
set -e

echo "Installing podman and utilities..."
# Assuming Ubuntu/Debian-based
sudo apt-get update && sudo apt-get install -y podman wget

echo "Setting up Sigstore trust root (Fulcio CA and Rekor Pub)..."
sudo mkdir -p /etc/pki/containers/
sudo wget -4 -O /etc/pki/containers/fulcio_v1.crt.pem https://fulcio.sigstore.dev/api/v1/rootCert
sudo wget -4 -O /etc/pki/containers/rekor.pub https://rekor.sigstore.dev/api/v1/log/publicKey

echo "Applying Podman policies and registry config..."
sudo mkdir -p /etc/containers/registries.d/
sudo cp policy.json /etc/containers/policy.json
sudo cp registries.yaml /etc/containers/registries.d/podman-demo.yaml

echo "Setting up Quadlet directory..."
sudo mkdir -p /etc/containers/systemd/

echo "Setting up Sigstore Keys Update Timer..."
sudo cp update-sigstore-keys.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/update-sigstore-keys.sh
sudo cp sigstore-keys-update.service /etc/systemd/system/
sudo cp sigstore-keys-update.timer /etc/systemd/system/

echo "Reloading systemd and enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable --now sigstore-keys-update.timer

echo "================================================================"
echo "Host bootstrap complete!"
echo "The podman-demo.container quadlet unit is not installed by this"
echo "script -- it is rendered and deployed by the Ansible playbook"
echo "(ansible/deploy.yml) on every pipeline run, pinned to the image"
echo "digest that was just built, signed, and verified."
echo "Run the GitHub Actions 'Build and Deploy' workflow next to deploy."
echo "================================================================"
