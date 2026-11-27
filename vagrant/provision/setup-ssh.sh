#!/usr/bin/env bash
# Create user "demo" authorized with the public key uploaded by Vagrant.
set -euo pipefail

DEMO_USER="demo"
PUBKEY_FILE="/home/vagrant/id_ed25519.pub"

if [[ ! -f "${PUBKEY_FILE}" ]]; then
  echo "ERROR: ${PUBKEY_FILE} not found. Generate keys/ first (see README)."
  exit 1
fi

if ! id -u "${DEMO_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${DEMO_USER}"
fi

install -d -m 700 -o "${DEMO_USER}" -g "${DEMO_USER}" "/home/${DEMO_USER}/.ssh"
install -m 600 -o "${DEMO_USER}" -g "${DEMO_USER}" "${PUBKEY_FILE}" \
  "/home/${DEMO_USER}/.ssh/authorized_keys"

echo "Provisioned user '${DEMO_USER}' with demo SSH public key."
