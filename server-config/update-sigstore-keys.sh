#!/bin/bash
set -e

echo "Updating Sigstore trust root (Fulcio CA and Rekor Pub)..."
wget -4 -O /etc/pki/containers/fulcio_v1.crt.pem.new https://fulcio.sigstore.dev/api/v1/rootCert
wget -4 -O /etc/pki/containers/rekor.pub.new https://rekor.sigstore.dev/api/v1/log/publicKey

mv /etc/pki/containers/fulcio_v1.crt.pem.new /etc/pki/containers/fulcio_v1.crt.pem
mv /etc/pki/containers/rekor.pub.new /etc/pki/containers/rekor.pub

echo "Successfully updated Sigstore keys."
