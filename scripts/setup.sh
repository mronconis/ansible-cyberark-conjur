#!/usr/bin/env bash
# Lab bootstrap: Conjur + target VM + Automation Controller (AWX) + Conjur wiring.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/Applications/UTM.app/Contents/MacOS:${PATH}"
export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

cd "${ROOT}"

echo "==> Prerequisites"
command -v podman >/dev/null
command -v vagrant >/dev/null
command -v utmctl >/dev/null
command -v kind >/dev/null
command -v kubectl >/dev/null
command -v python3 >/dev/null
command -v jq >/dev/null
command -v ssh-keygen >/dev/null
vagrant plugin list 2>/dev/null | grep -q vagrant_utm
podman info >/dev/null
echo "OK"

echo "==> Python venv + awx.awx"
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -U pip >/dev/null
pip install -r requirements.txt >/dev/null
mkdir -p controller/collections
export ANSIBLE_COLLECTIONS_PATH="${ROOT}/controller/collections"
ansible-galaxy collection install -r requirements.yml -p controller/collections >/dev/null

echo "==> SSH keypair"
if [[ ! -f keys/id_ed25519 ]]; then
  mkdir -p keys
  ssh-keygen -t ed25519 -f keys/id_ed25519 -N "" -C "ansible-cyberark-demo"
fi

echo "==> Conjur OSS"
FORCE=1 conjur/scripts/gen-tls.sh
cp -f conjur/conf/tls/nginx.crt conjur/conjur-server.pem
( cd conjur && podman compose pull )
conjur/scripts/up.sh
conjur/scripts/bootstrap.sh
conjur/scripts/seed-ssh.sh

echo "==> Target VM (Vagrant/UTM)"
(
  cd vagrant
  vagrant up --provider=utm
  vagrant provision
)

echo "==> Automation Controller (AWX)"
controller/scripts/up.sh
controller/scripts/configure.sh

echo
echo "Setup complete."
echo "  UI:   http://127.0.0.1:8088   (credentials: controller/.controller.env)"
echo "  Demo: make demo"
