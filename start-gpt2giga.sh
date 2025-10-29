#!/usr/bin/env bash
set -euo pipefail

# Directory resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

# .env handling (optional): point ENV_FILE to a custom path if needed
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
if [ -f "$ENV_FILE" ]; then
  # Export non-comment lines KEY=VALUE from .env
  # shellcheck disable=SC2046
  export $(grep -v '^#' "$ENV_FILE" | sed -e '/^$/d')
fi

# Resolve proxy host/port with sensible defaults
HOST="${GPT2GIGA_HOST:-${GPT2GIGA_PROXY_HOST:-0.0.0.0}}"
PORT="${GPT2GIGA_PORT:-${GPT2GIGA_PROXY_PORT:-8090}}"

# Build CLI args for gpt2giga
ARGS=(
  --proxy-host "$HOST"
  --proxy-port "$PORT"
)

# Include .env path explicitly so the CLI loader picks it up
if [ -f "$ENV_FILE" ]; then
  ARGS+=(--env-path "$ENV_FILE")
fi

# Log level (e.g., INFO, DEBUG)
if [ -n "${GPT2GIGA_LOG_LEVEL:-}" ]; then
  ARGS+=(--proxy-log-level "$GPT2GIGA_LOG_LEVEL")
fi

# Optional HTTPS for the proxy itself
USE_HTTPS="${GPT2GIGA_USE_HTTPS:-${GPT2GIGA_PROXY_USE_HTTPS:-}}"
if [[ "$USE_HTTPS" == "True" || "$USE_HTTPS" == "true" ]]; then
  ARGS+=(--proxy-use-https)
  if [ -n "${GPT2GIGA_HTTPS_KEY_FILE:-${GPT2GIGA_PROXY_HTTPS_KEY_FILE:-}}" ]; then
    ARGS+=(--proxy-https-key-file "${GPT2GIGA_HTTPS_KEY_FILE:-${GPT2GIGA_PROXY_HTTPS_KEY_FILE}}")
  fi
  if [ -n "${GPT2GIGA_HTTPS_CERT_FILE:-${GPT2GIGA_PROXY_HTTPS_CERT_FILE:-}}" ]; then
    ARGS+=(--proxy-https-cert-file "${GPT2GIGA_HTTPS_CERT_FILE:-${GPT2GIGA_PROXY_HTTPS_CERT_FILE}}")
  fi
fi

# Optional pass-through toggles
if [[ "${GPT2GIGA_PASS_MODEL:-}" == "True" || "${GPT2GIGA_PASS_MODEL:-}" == "true" ]]; then
  ARGS+=(--proxy-pass-model)
fi
if [[ "${GPT2GIGA_PASS_TOKEN:-}" == "True" || "${GPT2GIGA_PASS_TOKEN:-}" == "true" ]]; then
  ARGS+=(--proxy-pass-token)
fi

# Backend base URL (no-auth or mTLS target)
if [ -n "${GIGACHAT_BASE_URL:-}" ]; then
  ARGS+=(--gigachat-base-url "$GIGACHAT_BASE_URL")
fi

# Backend TLS verification toggle
if [[ "${GIGACHAT_VERIFY_SSL_CERTS:-}" == "True" || "${GIGACHAT_VERIFY_SSL_CERTS:-}" == "true" ]]; then
  ARGS+=(--gigachat-verify-ssl-certs)
fi

# Optional mTLS to backend
if [[ "${GIGACHAT_MTLS_AUTH:-}" == "True" || "${GIGACHAT_MTLS_AUTH:-}" == "true" ]]; then
  ARGS+=(--gigachat-mtls-auth)
  if [ -n "${GIGACHAT_CERT_FILE:-}" ]; then
    ARGS+=(--gigachat-cert-file "$GIGACHAT_CERT_FILE")
  fi
  if [ -n "${GIGACHAT_KEY_FILE:-}" ]; then
    ARGS+=(--gigachat-key-file "$GIGACHAT_KEY_FILE")
  fi
  if [ -n "${GIGACHAT_KEY_FILE_PASSWORD:-}" ]; then
    ARGS+=(--gigachat-key-file-password "$GIGACHAT_KEY_FILE_PASSWORD")
  fi
  if [ -n "${GIGACHAT_CA_BUNDLE_FILE:-}" ]; then
    ARGS+=(--gigachat-ca-bundle-file "$GIGACHAT_CA_BUNDLE_FILE")
  fi
fi

echo "Starting gpt2giga on $HOST:$PORT"

# Prefer Poetry if available; fallback to python -m
if command -v poetry >/dev/null 2>&1; then
  exec poetry run gpt2giga "${ARGS[@]}"
else
  exec python -m gpt2giga.api_server "${ARGS[@]}"
fi


