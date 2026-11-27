#!/usr/bin/env bash
# Store demo SSH username + private key in Conjur.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "${ROOT}/.." && pwd)"
cd "${ROOT}"

KEY_FILE="${REPO}/keys/id_ed25519"
[[ -f "${KEY_FILE}" ]] || { echo "Missing ${KEY_FILE}. Run: make keys" >&2; exit 1; }
[[ -f policy_data ]] || { echo "Missing policy_data. Run: make conjur-bootstrap" >&2; exit 1; }

OPERATOR_KEY="$(jq -r '.created_roles["demo:user:operator@ansible"].api_key // empty' policy_data)"
if [[ -z "${OPERATOR_KEY}" || "${OPERATOR_KEY}" == "null" ]]; then
  OPERATOR_KEY="$(podman exec conjur_server conjurctl role retrieve-key 'demo:user:operator@ansible' | tr -d '\r\n')"
fi

echo "==> Login operator@ansible"
podman exec conjur_client conjur logout >/dev/null 2>&1 || true
podman exec conjur_client conjur login -i operator@ansible -p "${OPERATOR_KEY}" >/dev/null

echo "==> Seed ansible/target/ssh_user=demo"
podman exec conjur_client conjur variable set -i ansible/target/ssh_user -v demo >/dev/null

echo "==> Seed ansible/target/ssh_private_key"
podman exec conjur_client bash -lc 'conjur variable set -i ansible/target/ssh_private_key -v "$(cat /keys/id_ed25519)"' >/dev/null

echo "SSH secrets seeded in Conjur."
