#!/usr/bin/env bash
# Launch the Conjur demo Job Template on Automation Controller.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "${ROOT}/.." && pwd)"
ENV_FILE="${ROOT}/.controller.env"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ -f "${ENV_FILE}" ]] || { echo "Missing ${ENV_FILE}. Run: make setup" >&2; exit 1; }

mkdir -p "${SCRIPT_DIR}/collections"
if [[ ! -e "${SCRIPT_DIR}/collections/ansible_collections" ]]; then
  ln -sfn "${ROOT}/collections/ansible_collections" "${SCRIPT_DIR}/collections/ansible_collections"
fi

# shellcheck disable=SC1090
set -a
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a

cd "${REPO}"
# shellcheck disable=SC1091
source .venv/bin/activate
ansible-galaxy collection install awx.awx -p "${ROOT}/collections" >/dev/null
export ANSIBLE_COLLECTIONS_PATH="${ROOT}/collections${ANSIBLE_COLLECTIONS_PATH:+:${ANSIBLE_COLLECTIONS_PATH}}"
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

ansible-playbook -i localhost, "${SCRIPT_DIR}/launch.yml"
