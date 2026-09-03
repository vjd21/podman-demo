#!/bin/bash
# Usage: ./update-service.sh <git-sha-tag>

if [ -z "$1" ]; then
  echo "Error: You must provide the new image tag."
  echo "Usage: $0 <image-tag>"
  exit 1
fi

NEW_TAG=$1
REGISTRY_URL="148737623247.dkr.ecr.us-east-2.amazonaws.com/podman-demo"

echo "Updating Podman Quadlet configuration to use tag: ${NEW_TAG}"

# 1. Update the image tag in the Quadlet file using sed
sudo sed -i "s|Image=.*|Image=${REGISTRY_URL}:${NEW_TAG}|g" /etc/containers/systemd/podman-demo.container

# 2. Reload systemd to pick up the file changes
sudo systemctl daemon-reload

# 3. Restart the service to pull the new image and apply the policy
sudo systemctl restart podman-demo

echo "Deployment successful! The service is now running ${NEW_TAG}"
