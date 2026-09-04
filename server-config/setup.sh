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

echo "Setting up initial Environment File..."
sudo mkdir -p /etc/podman-demo
echo "APP_IMAGE=148737623247.dkr.ecr.us-east-2.amazonaws.com/podman-demo:latest" | sudo tee /etc/podman-demo/image.env

echo "Setting up Quadlet..."
sudo mkdir -p /etc/containers/systemd/
sudo cp podman-demo.container /etc/containers/systemd/

echo "Setting up Sigstore Keys Update Timer..."
sudo cp update-sigstore-keys.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/update-sigstore-keys.sh
sudo cp sigstore-keys-update.service /etc/systemd/system/
sudo cp sigstore-keys-update.timer /etc/systemd/system/

echo "Reloading systemd and starting services..."
sudo systemctl daemon-reload
# Quadlet automatically generates the .service file from the .container file
sudo systemctl enable --now podman-demo.service
sudo systemctl enable --now sigstore-keys-update.timer

echo "================================================================"
echo "Setup complete! "
echo "Podman will pull the image, verify its keyless signature"
echo "against the GitHub Actions OIDC identity, and run it via Quadlet."
echo "You can check the status with: sudo systemctl status podman-demo"
echo "================================================================"
