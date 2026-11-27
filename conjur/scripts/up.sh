#!/usr/bin/env bash
# Reliable Conjur stack start for Podman on macOS (avoids podman-compose hangs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

"${ROOT}/scripts/gen-tls.sh"

if [[ ! -f data_key ]]; then
  echo "Generating data_key..."
  podman run --rm docker.io/cyberark/conjur data-key generate | tr -d '\r\n' > data_key
  echo >> data_key
fi
export CONJUR_DATA_KEY
CONJUR_DATA_KEY="$(tr -d '\r\n' < data_key)"

echo "Starting compose (timeout 90s)..."
set +e
perl -e 'alarm shift; exec @ARGV' 90 podman compose up -d
rc=$?
set -e

# Always ensure long-running services are started (compose may hang after create).
for c in postgres_database conjur_server nginx_proxy conjur_client; do
  if podman inspect "$c" >/dev/null 2>&1; then
    state="$(podman inspect -f '{{.State.Status}}' "$c")"
    if [[ "$state" != "running" ]]; then
      echo "Starting ${c} (was ${state})..."
      podman start "$c" >/dev/null
    fi
  fi
done

# Remove leftover openssl container from older compose files if present.
if podman inspect openssl >/dev/null 2>&1; then
  podman rm -f openssl >/dev/null 2>&1 || true
fi

echo "Waiting for Conjur HTTPS..."
for i in $(seq 1 30); do
  code="$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:8443/ || true)"
  if [[ "$code" == "200" ]]; then
    echo "Conjur is up (https://localhost:8443 → ${code})"
    podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'NAMES|postgres|conjur|nginx' || true
    exit 0
  fi
  sleep 2
done

echo "ERROR: Conjur did not become ready. Check: podman logs conjur_server" >&2
exit 1
