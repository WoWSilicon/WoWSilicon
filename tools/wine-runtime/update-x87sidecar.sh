#!/usr/bin/env bash
# Update the bundled x87sidecar to the latest release, or to --tag TAG.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
lock_file="$repo_root/Packaging/X87Sidecar/x87sidecar-lock.json"
destination_dir="$repo_root/Sources/WoWSiliconSwift/Resources/Patching/x87sidecar"
tag=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || { echo "Usage: $0 [--tag TAG]" >&2; exit 1; }
      tag="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--tag TAG]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

for command in curl jq python3 shasum tar; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

if [[ -n "$tag" ]]; then
  api_url="https://api.github.com/repos/athei/x87sidecar/releases/tags/$tag"
else
  api_url="https://api.github.com/repos/athei/x87sidecar/releases/latest"
fi

release_json="$(curl -fsSL "$api_url")"
release_tag="$(jq -r '.tag_name' <<<"$release_json")"
asset_name="x87sidecar.tar.xz"
asset_url="$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url' <<<"$release_json")"
asset_digest="$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .digest' <<<"$release_json")"
expected_asset_sha256="${asset_digest#sha256:}"

[[ -n "$asset_url" && "$asset_url" != "null" ]] || {
  echo "Release $release_tag does not contain $asset_name" >&2
  exit 1
}
[[ "$expected_asset_sha256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Release $release_tag does not publish a valid SHA-256 digest" >&2
  exit 1
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/x87sidecar-update.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

tarball="$work_dir/$asset_name"
curl -fsSL --progress-bar -o "$tarball" "$asset_url"
actual_asset_sha256="$(shasum -a 256 "$tarball" | awk '{print $1}')"
[[ "$actual_asset_sha256" == "$expected_asset_sha256" ]] || {
  echo "Asset checksum mismatch: expected $expected_asset_sha256, got $actual_asset_sha256" >&2
  exit 1
}

tar -xJf "$tarball" -C "$work_dir"
binary="$work_dir/x87sidecar"
[[ -f "$binary" ]] || { echo "Archive does not contain x87sidecar" >&2; exit 1; }
[[ "$(file -b "$binary")" == *"Mach-O 64-bit executable arm64"* ]] || {
  echo "The release binary is not an arm64 Mach-O executable" >&2
  exit 1
}
binary_sha256="$(shasum -a 256 "$binary" | awk '{print $1}')"

mkdir -p "$destination_dir"
install -m 0755 "$binary" "$destination_dir/x87sidecar"
curl -fsSL "https://raw.githubusercontent.com/athei/x87sidecar/$release_tag/LICENSE" \
  -o "$destination_dir/LICENSE"

python3 - "$lock_file" "$release_tag" "$asset_name" "$actual_asset_sha256" "$binary_sha256" <<'PYEOF'
import json
import pathlib
import sys

path, version, asset, asset_sha256, binary_sha256 = sys.argv[1:]
data = {
    "schemaVersion": 1,
    "version": version,
    "asset": asset,
    "assetSha256": asset_sha256,
    "binarySha256": binary_sha256,
}
pathlib.Path(path).write_text(json.dumps(data, indent=2) + "\n")
PYEOF

echo "Bundled x87sidecar $release_tag"
echo "  asset:  $actual_asset_sha256"
echo "  binary: $binary_sha256"
