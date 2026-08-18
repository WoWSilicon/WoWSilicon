#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: tools/wine-runtime/package.sh [--runtime PATH] [--output-dir PATH]

Creates and validates a versioned WoWSilicon Wine runtime archive.
EOF
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest="$repo_root/Packaging/WineRuntime/runtime-lock.json"
artifact_lock="$repo_root/Packaging/WineRuntime/artifact-lock.json"
runtime="$repo_root/.wine-runtime"
output_dir="$repo_root/.build/runtime-artifacts"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime)
      [[ $# -ge 2 ]] || usage
      runtime="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || usage
      output_dir="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

for command in jq rsync shasum tar xz; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required packaging command not found: $command" >&2
    exit 1
  }
done

"$script_dir/validate.sh" --runtime "$runtime"

runtime_revision="$(jq -er '.runtimeRevision | numbers' "$manifest")"
artifact_name="WoWSilicon-WineRuntime-r${runtime_revision}.tar.xz"
artifact_path="$output_dir/$artifact_name"
checksum_path="$artifact_path.sha256"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/wowsilicon-runtime-package.XXXXXX")"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$work_dir/staging/.wine-runtime" "$work_dir/verify" "$output_dir"
rsync -a --exclude '.DS_Store' "$runtime/" "$work_dir/staging/.wine-runtime/"

# Fixed timestamps, ownership and ordering keep the archive stable when the
# same assembled runtime is packaged again.
TZ=UTC find -s "$work_dir/staging/.wine-runtime" -exec touch -h -t 202001010000 {} +
(
  cd "$work_dir/staging"
  find -s .wine-runtime -print0 > "$work_dir/archive-files"
  COPYFILE_DISABLE=1 tar -cnf - \
    --format ustar \
    --uid 0 --gid 0 --uname root --gname wheel \
    --no-acls --no-fflags --no-xattrs \
    --null -T "$work_dir/archive-files"
) | xz -9 --threads=1 > "$work_dir/$artifact_name"

mv "$work_dir/$artifact_name" "$artifact_path"
artifact_sha256="$(shasum -a 256 "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$artifact_name" > "$checksum_path"

tar -xJf "$artifact_path" -C "$work_dir/verify"
"$script_dir/validate.sh" --runtime "$work_dir/verify/.wine-runtime"

artifact_size="$(wc -c < "$artifact_path" | tr -d ' ')"
jq -n \
  --argjson runtimeRevision "$runtime_revision" \
  --arg releaseTag "wine-runtime-r${runtime_revision}" \
  --arg asset "$artifact_name" \
  --argjson sizeBytes "$artifact_size" \
  --arg sha256 "$artifact_sha256" \
  '{
    schemaVersion: 1,
    runtimeRevision: $runtimeRevision,
    releaseTag: $releaseTag,
    asset: $asset,
    sizeBytes: $sizeBytes,
    sha256: $sha256
  }' > "$work_dir/artifact-lock.json"
mv "$work_dir/artifact-lock.json" "$artifact_lock"

echo "Wine runtime artifact created:"
echo "  $artifact_path"
echo "  $checksum_path"
echo "  $artifact_lock"
echo "  SHA-256: $artifact_sha256"
