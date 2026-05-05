#!/usr/bin/env bash
set -euo pipefail

version="${1#v}"

IFS='.' read -r major minor patch extra <<< "$version"

if [[ -n "${extra:-}" || -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "Version must use vMAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH, got: $1" >&2
  exit 1
fi

if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]]; then
  echo "Version components must be numeric, got: $1" >&2
  exit 1
fi

printf '%d\n' "$((10#$major * 10000 + 10#$minor * 100 + 10#$patch))"
