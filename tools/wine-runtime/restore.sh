#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--runtime PATH] [--repository OWNER/REPO]" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
artifact_lock="$repo_root/Packaging/WineRuntime/artifact-lock.json"
runtime="$repo_root/.wine-runtime"
repository="${GITHUB_REPOSITORY:-WoWSilicon/WoWSilicon}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime)
      [[ $# -ge 2 ]] || usage
      runtime="$2"
      shift 2
      ;;
    --repository)
      [[ $# -ge 2 ]] || usage
      repository="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

for command in curl jq shasum tar; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required restore command not found: $command" >&2
    exit 1
  }
done

[[ ! -e "$runtime" ]] || {
  echo "Wine runtime destination already exists: $runtime" >&2
  exit 1
}

release_tag="$(jq -er '.releaseTag | strings' "$artifact_lock")"
asset_name="$(jq -er '.asset | strings' "$artifact_lock")"
expected_size="$(jq -er '.sizeBytes | numbers' "$artifact_lock")"
expected_sha256="$(jq -er '.sha256 | strings' "$artifact_lock")"
download_url="https://github.com/$repository/releases/download/$release_tag/$asset_name"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/wowsilicon-runtime-restore.XXXXXX")"
archive="$work_dir/$asset_name"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

echo "Downloading Wine runtime $release_tag ..."
curl -fL --retry 3 --retry-all-errors --progress-bar -o "$archive" "$download_url"

actual_size="$(wc -c < "$archive" | tr -d ' ')"
[[ "$actual_size" == "$expected_size" ]] || {
  echo "Wine runtime size mismatch: expected $expected_size, got $actual_size" >&2
  exit 1
}

actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$actual_sha256" == "$expected_sha256" ]] || {
  echo "Wine runtime checksum mismatch: expected $expected_sha256, got $actual_sha256" >&2
  exit 1
}

archive_root="$(tar -tJf "$archive" | sed -n '1p')"
[[ "$archive_root" == ".wine-runtime/" ]] || {
  echo "Unexpected Wine runtime archive root: $archive_root" >&2
  exit 1
}

mkdir -p "$runtime"
tar -xJf "$archive" --strip-components 1 -C "$runtime"
"$script_dir/validate.sh" --runtime "$runtime"

echo "Restored Wine runtime $release_tag at $runtime"
