#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: assemble.sh --wine-root PATH --mtld3d-root PATH --external-root PATH --output PATH

Assembles a pinned WoWSilicon Wine runtime from an installed Wine tree and
the custom runtime overlays described by Packaging/WineRuntime/runtime-lock.json.
The output path must not already exist.
EOF
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest="$repo_root/Packaging/WineRuntime/runtime-lock.json"
wine_root=""
mtld3d_root=""
external_root=""
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wine-root)
      [[ $# -ge 2 ]] || usage
      wine_root="$2"
      shift 2
      ;;
    --mtld3d-root)
      [[ $# -ge 2 ]] || usage
      mtld3d_root="$2"
      shift 2
      ;;
    --external-root)
      [[ $# -ge 2 ]] || usage
      external_root="$2"
      shift 2
      ;;
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

[[ -n "$wine_root" && -n "$mtld3d_root" && -n "$external_root" && -n "$output" ]] || usage

for command in install_name_tool jq rsync shasum; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

[[ -f "$manifest" ]] || {
  echo "Runtime lock manifest not found: $manifest" >&2
  exit 1
}

[[ -x "$wine_root/bin/wine" && -x "$wine_root/bin/wineserver" ]] || {
  echo "Wine root must contain executable bin/wine and bin/wineserver files: $wine_root" >&2
  exit 1
}

[[ ! -e "$output" ]] || {
  echo "Output path already exists: $output" >&2
  exit 1
}

verify_group() {
  local group="$1"
  local source_root="$2"

  jq -r --arg group "$group" '.overlays[$group][] | [.sha256, .source] | @tsv' "$manifest" |
    while IFS=$'\t' read -r expected relative_path; do
      local source_path="$source_root/$relative_path"
      [[ -f "$source_path" ]] || {
        echo "Missing $group input: $source_path" >&2
        exit 1
      }

      local actual
      actual="$(shasum -a 256 "$source_path" | awk '{print $1}')"
      [[ "$actual" == "$expected" ]] || {
        echo "Checksum mismatch for $group input: $source_path" >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 1
      }
    done
}

copy_group() {
  local group="$1"
  local source_root="$2"

  jq -r --arg group "$group" '.overlays[$group][] | [.source, .destination] | @tsv' "$manifest" |
    while IFS=$'\t' read -r relative_source destination; do
      mkdir -p "$output/$(dirname "$destination")"
      cp -pX "$source_root/$relative_source" "$output/$destination"
    done
}

relocate_group() {
  local group="$1"

  jq -r --arg group "$group" \
    '.overlays[$group][] | .destination as $destination | (.deleteRpaths // [])[] | [$destination, .] | @tsv' \
    "$manifest" |
    while IFS=$'\t' read -r destination rpath; do
      install_name_tool -delete_rpath "$rpath" "$output/$destination"
    done
}

verify_group "winerosetta" "$repo_root"
verify_group "mtld3d" "$mtld3d_root"
verify_group "external" "$external_root"

mkdir -p "$output"
rsync -a --exclude='.DS_Store' "$wine_root/" "$output/"

copy_group "winerosetta" "$repo_root"
copy_group "mtld3d" "$mtld3d_root"
copy_group "external" "$external_root"

relocate_group "winerosetta"
relocate_group "mtld3d"
relocate_group "external"

mkdir -p "$output/share/wowsilicon"
cp -X "$manifest" "$output/share/wowsilicon/runtime-lock.json"

echo "Assembled WoWSilicon Wine runtime at $output"
