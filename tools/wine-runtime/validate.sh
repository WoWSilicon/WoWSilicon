#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --runtime PATH" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest="$repo_root/Packaging/WineRuntime/runtime-lock.json"
runtime=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime)
      [[ $# -ge 2 ]] || usage
      runtime="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$runtime" ]] || usage

for command in file jq otool shasum strings; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required validation command not found: $command" >&2
    exit 1
  }
done

[[ -d "$runtime" ]] || {
  echo "Runtime directory not found: $runtime" >&2
  exit 1
}

embedded_manifest="$runtime/share/wowsilicon/runtime-lock.json"
[[ -f "$embedded_manifest" ]] || {
  echo "Embedded runtime lock not found: $embedded_manifest" >&2
  exit 1
}

cmp -s "$manifest" "$embedded_manifest" || {
  echo "Embedded runtime lock does not match the repository lock." >&2
  exit 1
}

for executable in "$runtime/bin/wine" "$runtime/bin/wineserver"; do
  [[ -x "$executable" ]] || {
    echo "Required runtime executable is missing: $executable" >&2
    exit 1
  }
  file "$executable" | grep -q 'x86_64' || {
    echo "Runtime executable does not support x86_64: $executable" >&2
    exit 1
  }
done

for module_root in \
  "$runtime/lib/wine/i386-windows" \
  "$runtime/lib/wine/x86_64-windows" \
  "$runtime/lib/wine/x86_64-unix"; do
  [[ -d "$module_root" && -n "$(find "$module_root" -type f -print -quit)" ]] || {
    echo "Required Wine module tree is empty or missing: $module_root" >&2
    exit 1
  }
done

jq -r '.overlays | to_entries[].value[] | [(.assembledSha256 // .sha256), .destination] | @tsv' "$manifest" |
  while IFS=$'\t' read -r expected destination; do
    path="$runtime/$destination"
    [[ -f "$path" ]] || {
      echo "Pinned runtime file is missing: $path" >&2
      exit 1
    }
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || {
      echo "Assembled checksum mismatch: $path" >&2
      echo "Expected: $expected" >&2
      echo "Actual:   $actual" >&2
      exit 1
    }
  done

mach_o_list="$(mktemp /tmp/wowsilicon-mach-o.XXXXXX)"
cleanup() {
  rm -f "$mach_o_list"
}
trap cleanup EXIT

find "$runtime" -type f -print0 | xargs -0 file | grep 'Mach-O' | cut -d: -f1 > "$mach_o_list"
[[ -s "$mach_o_list" ]] || {
  echo "Runtime contains no Mach-O files." >&2
  exit 1
}

resolve_dependency() {
  local binary="$1"
  local dependency="$2"
  local binary_dir
  binary_dir="$(dirname "$binary")"

  case "$dependency" in
    /System/Library/*|/usr/lib/*)
      return 0
      ;;
    @loader_path/*)
      [[ -e "$binary_dir/${dependency#@loader_path/}" ]]
      return
      ;;
    @executable_path/*)
      [[ -e "$runtime/bin/${dependency#@executable_path/}" ]]
      return
      ;;
    @rpath/*)
      local suffix="${dependency#@rpath/}"
      local rpath
      for rpath in $(otool -l "$binary" | awk '
        $1 == "cmd" && $2 == "LC_RPATH" { reading = 1; next }
        reading && $1 == "path" { print $2; reading = 0 }
      '); do
        rpath="${rpath//@loader_path/$binary_dir}"
        rpath="${rpath//@executable_path/$runtime/bin}"
        if [[ -e "$rpath/$suffix" ]]; then
          return 0
        fi
      done
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

while IFS= read -r binary; do
  file "$binary" | grep -q 'x86_64' || {
    echo "Mach-O file does not support x86_64: $binary" >&2
    exit 1
  }

  while IFS= read -r rpath; do
    case "$rpath" in
      @loader_path*|@executable_path*) ;;
      *)
        echo "Non-relocatable RPATH in $binary: $rpath" >&2
        exit 1
        ;;
    esac
  done < <(otool -l "$binary" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { reading = 1; next }
    reading && $1 == "path" { print $2; reading = 0 }
  ')

  while IFS= read -r dependency; do
    resolve_dependency "$binary" "$dependency" || {
      echo "Unresolved dependency in $binary: $dependency" >&2
      exit 1
    }
  done < <(otool -l "$binary" | awk '
    $1 == "cmd" && ($2 == "LC_LOAD_DYLIB" || $2 == "LC_LOAD_WEAK_DYLIB" ||
      $2 == "LC_REEXPORT_DYLIB" || $2 == "LC_LOAD_UPWARD_DYLIB") { reading = 1; next }
    reading && $1 == "name" { print $2; reading = 0 }
  ')
done < "$mach_o_list"

secur32="$runtime/lib/wine/x86_64-unix/secur32.so"
[[ -f "$secur32" ]] || {
  echo "Wine secur32 backend is missing: $secur32" >&2
  exit 1
}

strings -a "$secur32" | grep 'gnutls_global_init' >/dev/null || {
  echo "Wine secur32 was built without GnuTLS; HTTPS will not work." >&2
  exit 1
}

arch -x86_64 "$runtime/bin/wine" --version >/dev/null

echo "Validated WoWSilicon Wine runtime at $runtime"
