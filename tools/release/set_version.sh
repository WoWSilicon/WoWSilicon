#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 vMAJOR.MINOR.PATCH [BUILD_NUMBER]" >&2
  exit 1
fi

version="${1#v}"
build_number="${2:-$(tools/release/version_to_build_number.sh "$version")}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" Packaging/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" Packaging/Info.plist

perl -0pi -e "s/\"MARKETING_VERSION\": \"[^\"]+\"/\"MARKETING_VERSION\": \"$version\"/" Project.swift
perl -0pi -e "s/\"CURRENT_PROJECT_VERSION\": \"[^\"]+\"/\"CURRENT_PROJECT_VERSION\": \"$build_number\"/" Project.swift

echo "Set WoWSilicon version to $version ($build_number)"
