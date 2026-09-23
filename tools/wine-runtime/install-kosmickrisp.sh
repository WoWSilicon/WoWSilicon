#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: install-kosmickrisp.sh --runtime PATH --loader PATH --driver PATH

Installs an x86_64 Vulkan loader and KosmicKrisp ICD into a local WoWSilicon
Wine runtime. MoltenVK remains installed and selectable as the default driver.
EOF
  exit 1
}

runtime=""
loader=""
driver=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime) runtime="${2:-}"; shift 2 ;;
    --loader) loader="${2:-}"; shift 2 ;;
    --driver) driver="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$runtime" && -n "$loader" && -n "$driver" ]] || usage
loader="$(realpath "$loader")"
driver="$(realpath "$driver")"
[[ -d "$runtime/lib/wine/x86_64-unix" ]] || { echo "Invalid Wine runtime: $runtime" >&2; exit 1; }
[[ -f "$runtime/lib/external/libMoltenVK.dylib" ]] || { echo "MoltenVK is missing from: $runtime" >&2; exit 1; }
[[ -f "$loader" && "$(file "$loader")" == *x86_64* ]] || { echo "Vulkan loader must be an x86_64 Mach-O file: $loader" >&2; exit 1; }
[[ -f "$driver" && "$(file "$driver")" == *x86_64* ]] || { echo "KosmicKrisp driver must be an x86_64 Mach-O file: $driver" >&2; exit 1; }

external="$runtime/lib/external"
manifests="$runtime/lib/vulkan/icd.d"
mkdir -p "$external" "$manifests"
[[ ! -e "$external/libvulkan.1.dylib" ]] || chmod u+w "$external/libvulkan.1.dylib"
[[ ! -e "$external/libvulkan_kosmickrisp.dylib" ]] || chmod u+w "$external/libvulkan_kosmickrisp.dylib"
cp -p "$loader" "$external/libvulkan.1.dylib"
cp -p "$driver" "$external/libvulkan_kosmickrisp.dylib"
chmod 755 "$external/libvulkan.1.dylib" "$external/libvulkan_kosmickrisp.dylib"

printf '%s\n' \
  '{' \
  '  "file_format_version": "1.0.1",' \
  '  "ICD": {' \
  '    "api_version": "1.4.0",' \
  '    "library_path": "../../external/libMoltenVK.dylib"' \
  '  }' \
  '}' > "$manifests/MoltenVK_icd.json"

printf '%s\n' \
  '{' \
  '  "file_format_version": "1.0.1",' \
  '  "ICD": {' \
  '    "api_version": "1.4.358",' \
  '    "library_path": "../../external/libvulkan_kosmickrisp.dylib"' \
  '  }' \
  '}' > "$manifests/KosmicKrisp_icd.json"

ln -sfn "../../external/libvulkan.1.dylib" "$runtime/lib/wine/x86_64-unix/libvulkan.1.dylib"

echo "Installed KosmicKrisp into $runtime"
echo "MoltenVK and KosmicKrisp are now selected through the Vulkan loader."
