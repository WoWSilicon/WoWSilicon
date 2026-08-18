#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --output PATH" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest="$repo_root/Packaging/WineRuntime/runtime-lock.json"
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || usage
      output="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$output" ]] || usage

for command in git jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

[[ -f "$manifest" ]] || {
  echo "Runtime lock manifest not found: $manifest" >&2
  exit 1
}

[[ ! -e "$output" ]] || {
  echo "Output path already exists: $output" >&2
  exit 1
}

repository="$(jq -er '.wine.repository' "$manifest")"
commit="$(jq -er '.wine.commit' "$manifest")"

output_parent="$(dirname "$output")"
mkdir -p "$output_parent"
temporary="$(mktemp -d "$output_parent/.wine-source.XXXXXX")"

cleanup() {
  rm -rf "$temporary"
}
trap cleanup EXIT

git -C "$temporary" init --quiet
git -C "$temporary" remote add origin "$repository"
git -C "$temporary" fetch --quiet --depth 1 --filter=blob:none origin "$commit"
git -C "$temporary" checkout --quiet --detach FETCH_HEAD

actual_commit="$(git -C "$temporary" rev-parse HEAD)"
[[ "$actual_commit" == "$commit" ]] || {
  echo "Fetched Wine commit does not match runtime lock." >&2
  echo "Expected: $commit" >&2
  echo "Actual:   $actual_commit" >&2
  exit 1
}

mv "$temporary" "$output"
trap - EXIT

echo "Fetched Wine source at commit $commit into $output"
