#!/usr/bin/env bash
# Generate nginx TLS material for the Conjur proxy (idempotent unless FORCE=1).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TLS_DIR="${ROOT}/conf/tls"

mkdir -p "${TLS_DIR}"

if [[ "${FORCE:-0}" != "1" && -f "${TLS_DIR}/nginx.crt" && -f "${TLS_DIR}/nginx.key" ]]; then
  echo "TLS certs already present in ${TLS_DIR} (set FORCE=1 to regenerate)"
  exit 0
fi

rm -f "${TLS_DIR}/nginx.crt" "${TLS_DIR}/nginx.key"

echo "Generating self-signed TLS certs in ${TLS_DIR}..."
podman run --rm \
  --entrypoint openssl \
  -v "${TLS_DIR}:/tmp/conf:z" \
  docker.io/cyberark/conjur \
  req -newkey rsa:2048 -days 365 -nodes -x509 \
  -config /tmp/conf/tls.conf \
  -extensions v3_ca \
  -keyout /tmp/conf/nginx.key \
  -out /tmp/conf/nginx.crt

echo "Done: ${TLS_DIR}/nginx.crt ${TLS_DIR}/nginx.key"
