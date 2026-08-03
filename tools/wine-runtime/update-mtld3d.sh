#!/usr/bin/env bash
# update-mtld3d.sh — Update the bundled mtld3d to the latest (or a pinned) release.
#
# Usage:
#   update-mtld3d.sh [--tag v0.3.0] [--skip-assemble] [--dry-run]
#
#   --tag TAG          Pin to a specific release tag instead of the latest.
#   --skip-assemble    Only update runtime-lock.json; do not update .wine-runtime.
#   --dry-run          Print what would change but do not write anything.
#
# Requirements: curl, jq, python3, shasum, tar, rsync
set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest="$repo_root/Packaging/WineRuntime/runtime-lock.json"
runtime_dir="$repo_root/.wine-runtime"

tag=""
skip_assemble=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || { echo "Usage: $0 [--tag TAG] [--skip-assemble] [--dry-run]" >&2; exit 1; }
      tag="$2"; shift 2 ;;
    --skip-assemble)
      skip_assemble=true; shift ;;
    --dry-run)
      dry_run=true; shift ;;
    -h|--help)
      grep '^#' "$0" | head -n 12 | sed 's/^# \?//'
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
for cmd in curl jq python3 shasum tar; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Required command not found: $cmd" >&2; exit 1
  }
done

[[ -f "$manifest" ]] || { echo "Runtime lock not found: $manifest" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Resolve the release to use
# ---------------------------------------------------------------------------
if [[ -n "$tag" ]]; then
  api_url="https://api.github.com/repos/athei/mtld3d/releases/tags/$tag"
  echo "Fetching mtld3d release $tag ..."
else
  api_url="https://api.github.com/repos/athei/mtld3d/releases/latest"
  echo "Fetching latest mtld3d release ..."
fi

release_json="$(curl -fsSL "$api_url")"
release_tag="$(jq -r '.tag_name' <<<"$release_json")"
release_url="$(jq -r '.html_url' <<<"$release_json")"

# Pick the production (non-debug) tarball
asset_url="$(jq -r '.assets[] | select(.name == "mtld3d.tar.xz") | .browser_download_url' <<<"$release_json")"
asset_digest="$(jq -r '.assets[] | select(.name == "mtld3d.tar.xz") | .digest' <<<"$release_json")"
# GitHub digest format is "sha256:<hex>", strip the prefix
expected_tarball_sha256="${asset_digest#sha256:}"

[[ -n "$asset_url" ]] || {
  echo "Could not find mtld3d.tar.xz asset in release $release_tag" >&2; exit 1
}

# Check whether we are already on this version
current_tag="$(jq -r '.mtld3d.version // ""' "$manifest")"
if [[ "$current_tag" == "$release_tag" ]]; then
  echo "Already at mtld3d $release_tag — nothing to do."
  exit 0
fi

echo "Updating mtld3d: ${current_tag:-<unset>} → $release_tag"
echo "  Asset: $asset_url"

# ---------------------------------------------------------------------------
# Download & verify tarball
# ---------------------------------------------------------------------------
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mtld3d-update.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

tarball="$work_dir/mtld3d.tar.xz"
echo "Downloading ..."
curl -fsSL --progress-bar -o "$tarball" "$asset_url"

echo "Verifying tarball checksum ..."
actual_tarball_sha256="$(shasum -a 256 "$tarball" | awk '{print $1}')"
[[ "$actual_tarball_sha256" == "$expected_tarball_sha256" ]] || {
  echo "Tarball checksum mismatch!" >&2
  echo "  Expected: $expected_tarball_sha256" >&2
  echo "  Actual:   $actual_tarball_sha256" >&2
  exit 1
}
echo "  ✓ $actual_tarball_sha256"

# ---------------------------------------------------------------------------
# Extract tarball
# ---------------------------------------------------------------------------
extract_dir="$work_dir/extracted"
mkdir -p "$extract_dir"
echo "Extracting ..."
tar -xJf "$tarball" -C "$extract_dir"

# If tarball has a single top-level directory, descend into it
shopt -s nullglob
entries=("$extract_dir"/*)
shopt -u nullglob
if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
  extract_dir="${entries[0]}"
fi

# ---------------------------------------------------------------------------
# Verify expected overlay files are present in the tarball
# ---------------------------------------------------------------------------
echo "Verifying extracted files match overlay entries ..."
missing=0
while IFS= read -r rel_path; do
  if [[ ! -f "$extract_dir/$rel_path" ]]; then
    echo "  Missing in tarball: $rel_path" >&2
    missing=1
  fi
done < <(jq -r '.overlays.mtld3d[].source' "$manifest")
if [[ $missing -ne 0 ]]; then
  echo "Tarball is missing expected files. The overlay mapping in runtime-lock.json may need updating." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Compute new SHA-256 checksums and write them to a temp file for Python
# ---------------------------------------------------------------------------
echo "Computing file checksums ..."
checksums_file="$work_dir/checksums.tsv"
> "$checksums_file"

while IFS= read -r rel_path; do
  hash="$(shasum -a 256 "$extract_dir/$rel_path" | awk '{print $1}')"
  printf '%s\t%s\n' "$rel_path" "$hash" >> "$checksums_file"
  printf "  %-55s %s\n" "$rel_path" "$hash"
done < <(jq -r '.overlays.mtld3d[].source' "$manifest")

# ---------------------------------------------------------------------------
# Show diff summary
# ---------------------------------------------------------------------------
echo ""
echo "Checksum changes:"
changed=0
while IFS=$'\t' read -r old_sha rel_path; do
  new_sha="$(awk -F'\t' -v k="$rel_path" '$1==k{print $2}' "$checksums_file")"
  if [[ "$old_sha" != "$new_sha" ]]; then
    printf "  CHANGED  %s\n    old: %s\n    new: %s\n" "$rel_path" "$old_sha" "$new_sha"
    changed=1
  fi
done < <(jq -r '.overlays.mtld3d[] | [.sha256, .source] | @tsv' "$manifest")
if [[ $changed -eq 0 ]]; then
  echo "  (no checksum changes — binaries are identical to current lock)"
fi

if $dry_run; then
  echo ""
  echo "[dry-run] No files written."
  exit 0
fi

# ---------------------------------------------------------------------------
# Update runtime-lock.json using Python (reliable on macOS without extra deps)
# ---------------------------------------------------------------------------
echo ""
echo "Updating runtime-lock.json ..."

python3 - "$manifest" "$release_tag" "$checksums_file" <<'PYEOF'
import sys, json, pathlib

manifest_path, new_tag, checksums_path = sys.argv[1], sys.argv[2], sys.argv[3]

checksums = {}
for line in pathlib.Path(checksums_path).read_text().splitlines():
    if line.strip():
        rel_path, sha = line.split('\t', 1)
        checksums[rel_path] = sha

data = json.loads(pathlib.Path(manifest_path).read_text())
data['mtld3d']['version'] = new_tag
for entry in data['overlays']['mtld3d']:
    src = entry['source']
    if src in checksums:
        entry['sha256'] = checksums[src]

pathlib.Path(manifest_path).write_text(json.dumps(data, indent=2) + '\n')
PYEOF

echo "  ✓ runtime-lock.json updated (mtld3d version: $release_tag)"

# ---------------------------------------------------------------------------
# Copy new binaries into .wine-runtime
# ---------------------------------------------------------------------------
if $skip_assemble; then
  echo ""
  echo "Skipping .wine-runtime update (--skip-assemble)."
  echo "Re-run assemble.sh manually to rebuild the runtime from scratch."
  exit 0
fi

if [[ ! -d "$runtime_dir" ]]; then
  echo ""
  echo "No .wine-runtime directory found; skipping in-place binary update."
  echo "Run tools/wine-runtime/assemble.sh to build the runtime from scratch."
  exit 0
fi

echo ""
echo "Updating .wine-runtime in place ..."
while IFS=$'\t' read -r rel_source rel_dest; do
  src="$extract_dir/$rel_source"
  dst="$runtime_dir/$rel_dest"
  mkdir -p "$(dirname "$dst")"
  cp -pX "$src" "$dst"
  echo "  ✓ $rel_dest"
done < <(jq -r '.overlays.mtld3d[] | [.source, .destination] | @tsv' "$manifest")

# Keep the embedded manifest copy in sync so validate.sh stays happy
mkdir -p "$runtime_dir/share/wowsilicon"
cp "$manifest" "$runtime_dir/share/wowsilicon/runtime-lock.json"
echo "  ✓ share/wowsilicon/runtime-lock.json"

echo ""
echo "mtld3d updated to $release_tag"
echo "  $release_url"
echo ""
echo ""
echo "Run 'make validate_wine_runtime' to confirm the runtime is healthy."
