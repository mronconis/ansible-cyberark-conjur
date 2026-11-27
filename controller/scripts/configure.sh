#!/usr/bin/env bash
# Configure Controller: Conjur lookup credential → Machine SSH key → inventory → JT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "${ROOT}/.." && pwd)"
ENV_FILE="${ROOT}/.controller.env"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ -f "${ENV_FILE}" ]] || { echo "Missing ${ENV_FILE}. Run: make setup" >&2; exit 1; }
[[ -f "${REPO}/conjur/host_api_key" ]] || { echo "Missing conjur/host_api_key" >&2; exit 1; }
[[ -f "${REPO}/conjur/conjur-server.pem" ]] || { echo "Missing conjur/conjur-server.pem" >&2; exit 1; }

mkdir -p "${SCRIPT_DIR}/collections"
[[ -e "${SCRIPT_DIR}/collections/ansible_collections" ]] \
  || ln -sfn "${ROOT}/collections/ansible_collections" "${SCRIPT_DIR}/collections/ansible_collections"

# shellcheck disable=SC1090
set -a
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a

export PATH="/Applications/UTM.app/Contents/MacOS:${PATH}"
if [[ -d "${REPO}/vagrant" ]]; then
  CFG="$(cd "${REPO}/vagrant" && vagrant ssh-config 2>/dev/null || true)"
  PORT="$(printf '%s\n' "${CFG}" | awk '/^[[:space:]]*Port / {print $2; exit}')"
  [[ -n "${PORT}" ]] && export TARGET_PORT="${PORT}"
fi
export TARGET_PORT="${TARGET_PORT:-2250}"
export TARGET_HOST="${TARGET_HOST:-host.containers.internal}"
export CONJUR_URL="${CONJUR_URL:-https://host.containers.internal:8443}"

if [[ -z "${PROJECT_SCM_URL:-}" ]]; then
  PROJECT_SCM_URL="$(git -C "${REPO}" remote get-url origin 2>/dev/null || true)"
fi
# Prefer HTTPS for public GitHub clones (no SCM credential on Controller).
if [[ "${PROJECT_SCM_URL}" =~ ^git@github\.com:(.+)$ ]]; then
  PROJECT_SCM_URL="https://github.com/${BASH_REMATCH[1]}"
elif [[ "${PROJECT_SCM_URL}" =~ ^ssh://git@github\.com/(.+)$ ]]; then
  PROJECT_SCM_URL="https://github.com/${BASH_REMATCH[1]}"
fi
PROJECT_SCM_URL="${PROJECT_SCM_URL%.git}.git"
export PROJECT_SCM_URL
export PROJECT_SCM_BRANCH="${PROJECT_SCM_BRANCH:-$(git -C "${REPO}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"

cd "${REPO}"
# shellcheck disable=SC1091
source .venv/bin/activate
mkdir -p "${ROOT}/collections"
export ANSIBLE_COLLECTIONS_PATH="${ROOT}/collections${ANSIBLE_COLLECTIONS_PATH:+:${ANSIBLE_COLLECTIONS_PATH}}"
ansible-galaxy collection install awx.awx -p "${ROOT}/collections" >/dev/null
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
echo "==> Project SCM: ${PROJECT_SCM_URL} (${PROJECT_SCM_BRANCH})"

echo "==> Waiting for Controller API at ${CONTROLLER_HOST}"
for _ in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "${CONTROLLER_HOST}/api/v2/" || true)"
  [[ "${code}" == "200" ]] && break
  sleep 5
done
[[ "$(curl -s -o /dev/null -w '%{http_code}' "${CONTROLLER_HOST}/api/v2/" || true)" == "200" ]] \
  || { echo "Controller API not ready" >&2; exit 1; }

# Creating hosts requires a READY dispatcher instance (otherwise HTTP 500).
echo "==> Waiting for Controller task capacity"
for _ in $(seq 1 60); do
  cap="$(curl -fsS -u "${CONTROLLER_USERNAME}:${CONTROLLER_PASSWORD}" "${CONTROLLER_HOST}/api/v2/ping/" 2>/dev/null \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(i.get("capacity",0) for i in d.get("instances",[])))' 2>/dev/null || echo 0)"
  [[ "${cap}" =~ ^[0-9]+$ ]] && (( cap > 0 )) && break
  sleep 5
done

ansible-playbook -i localhost, -e ansible_python_interpreter="${REPO}/.venv/bin/python" \
  "${SCRIPT_DIR}/configure.yml"
