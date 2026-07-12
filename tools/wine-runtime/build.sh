#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: build.sh --source PATH --build PATH --install PATH [--jobs COUNT]

Builds the pinned macOS Wine source as an x86_64 host with i386 and x86_64
Windows modules. TOOLCHAIN_PREFIX may override the default /usr/local prefix.
EOF
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
patch_root="$repo_root/Packaging/WineRuntime/patches"
source_root=""
build_root=""
install_root=""
jobs=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || usage
      source_root="$2"
      shift 2
      ;;
    --build)
      [[ $# -ge 2 ]] || usage
      build_root="$2"
      shift 2
      ;;
    --install)
      [[ $# -ge 2 ]] || usage
      install_root="$2"
      shift 2
      ;;
    --jobs)
      [[ $# -ge 2 ]] || usage
      jobs="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$source_root" && -n "$build_root" && -n "$install_root" ]] || usage
[[ -z "$jobs" || "$jobs" =~ ^[1-9][0-9]*$ ]] || usage

[[ -x "$source_root/configure" ]] || {
  echo "Wine configure script not found: $source_root/configure" >&2
  exit 1
}

[[ ! -e "$build_root" ]] || {
  echo "Build path already exists: $build_root" >&2
  exit 1
}

[[ ! -e "$install_root" ]] || {
  echo "Install path already exists: $install_root" >&2
  exit 1
}

toolchain_prefix="${TOOLCHAIN_PREFIX:-/usr/local}"
llvm_bin="$toolchain_prefix/opt/llvm/bin"
bison_bin="$toolchain_prefix/opt/bison/bin"
export PATH="$bison_bin:$llvm_bin:$toolchain_prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_PATH="$toolchain_prefix/lib/pkgconfig:$toolchain_prefix/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CPPFLAGS="-I$toolchain_prefix/include${CPPFLAGS:+ $CPPFLAGS}"
export LDFLAGS="-L$toolchain_prefix/lib${LDFLAGS:+ $LDFLAGS}"
export CC="${CC:-$llvm_bin/clang}"
export CXX="${CXX:-$llvm_bin/clang++}"

for command in "$CC" "$CXX" bison flex git i686-w64-mingw32-gcc x86_64-w64-mingw32-gcc make pkg-config; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required build command not found: $command" >&2
    exit 1
  }
done

file "$CC" | grep -q 'x86_64' || {
  echo "The macOS compiler must support x86_64: $CC" >&2
  exit 1
}

pkg-config --exists freetype2 vulkan || {
  echo "x86_64 FreeType and Vulkan development packages are required under $toolchain_prefix" >&2
  exit 1
}

for patch in "$patch_root"/*.patch; do
  [[ -e "$patch" ]] || continue
  git -C "$source_root" apply --check "$patch"
  git -C "$source_root" apply "$patch"
done

if [[ -z "$jobs" ]]; then
  jobs="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
  if (( jobs > 4 )); then
    jobs=4
  fi
fi

configure_options=(
  --build=x86_64-apple-darwin
  --prefix="$install_root"
  --enable-archs=i386,x86_64
  --disable-tests
  --without-alsa
  --without-capi
  --without-cups
  --without-dbus
  --without-ffmpeg
  --without-fontconfig
  --without-gettext
  --without-gphoto
  --without-gnutls
  --without-gssapi
  --without-gstreamer
  --without-hwloc
  --without-inotify
  --without-krb5
  --without-netapi
  --without-opencl
  --without-opengl
  --without-oss
  --without-pcap
  --without-pcsclite
  --without-pulse
  --without-sane
  --without-sdl
  --without-udev
  --without-usb
  --without-v4l2
  --without-wayland
  --without-x
)

mkdir -p "$build_root"
(
  cd "$build_root"
  "$source_root/configure" "${configure_options[@]}"
)

make -C "$build_root" -j "$jobs"
make -C "$build_root" install-lib INSTALL_PROGRAM_FLAGS=--strip

[[ -x "$install_root/bin/wine" && -x "$install_root/bin/wineserver" ]] || {
  echo "Wine installation did not produce the expected executables." >&2
  exit 1
}

file "$install_root/bin/wine" | grep -q 'x86_64' || {
  echo "Installed Wine loader is not x86_64." >&2
  exit 1
}

echo "Built Wine runtime into $install_root"
