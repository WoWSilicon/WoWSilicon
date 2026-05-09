#!/usr/bin/env bash
set -euo pipefail

key="${SPARKLE_PRIVATE_KEY:-}"

if [[ -z "$key" ]]; then
  echo "SPARKLE_PRIVATE_KEY is empty." >&2
  exit 1
fi

# Accept common copy/paste forms while avoiding printing the secret.
key="${key//$'\r'/}"
key="${key#"${key%%[![:space:]]*}"}"
key="${key%"${key##*[![:space:]]}"}"
key="${key#export SPARKLE_PRIVATE_KEY=}"
key="${key#SPARKLE_PRIVATE_KEY=}"
key="${key#PRIVATE_KEY_SECRET=}"
key="${key#PRIVATE_KEY=}"
key="${key#\"}"
key="${key%\"}"
key="${key#\'}"
key="${key%\'}"
key="$(printf '%s' "$key" | tr -d '[:space:]')"

if [[ ! "$key" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]; then
  echo "SPARKLE_PRIVATE_KEY must contain only the base64 Sparkle private EdDSA key." >&2
  echo "Do not paste the public key, XML, or the full generate_keys output." >&2
  exit 1
fi

printf '%s' "$key"
