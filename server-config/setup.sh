#!/bin/bash
set -e

echo "Installing podman and utilities..."
# Assuming Amazon Linux 2023 or RHEL-based
sudo dnf install -y podman wget

echo "Setting up Sigstore trust root (Fulcio CA and Rekor Pub)..."
sudo mkdir -p /etc/pki/containers/
sudo wget -qO /etc/pki/containers/fulcio_v1.crt.pem https://tuf-repo-cdn.sigstore.dev/targets/fulcio_v1.crt.pem
sudo wget -qO /etc/pki/containers/rekor.pub https://tuf-repo-cdn.sigstore.dev/targets/rekor.pub

echo "Applying Podman policies and registry config..."
sudo mkdir -p /etc/containers/registries.d/
sudo cp policy.json /etc/containers/policy.json
sudo cp registries.yaml /etc/containers/registries.d/podman-demo.yaml

echo "Setting up Quadlet..."
sudo mkdir -p /etc/containers/systemd/
sudo cp podman-demo.container /etc/containers/systemd/

echo "Reloading systemd and starting the service..."
sudo systemctl daemon-reload
# Quadlet automatically generates the .service file from the .container file
sudo systemctl enable --now podman-demo.service

echo "================================================================"
echo "Setup complete! "
echo "Podman will pull the image, verify its keyless signature"
echo "against the GitHub Actions OIDC identity, and run it via Quadlet."
echo "You can check the status with: sudo systemctl status podman-demo"
echo "================================================================"
