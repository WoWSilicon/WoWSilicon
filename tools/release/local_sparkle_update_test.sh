#!usr/bin/env bash
set -euo pipefail

OLD_VERSION="${1:-2.5.0}"
NEW_VERSION="${2:-2.5.1}"
HOST="${SPARKLE_TEST_HOST:-127.0.0.1}"
PORT="${SPARKLE_TEST_PORT:-8000}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$ROOT_DIR/.build/sparkle-local-test"
OLD_APP="$TEST_DIR/WoWSilicon-$OLD_VERSION.app"
FEED_URL="http://$HOST:$PORT/appcast.xml"
DOWNLOAD_URL_PREFIX="http://$HOST:$PORT/"

build_number() {
  local version="$1"
  local major minor patch
  IFS=. read -r major minor patch <<<"$version"
  if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
    echo "Version must be major.minor.patch, got: $version" >&2
    exit 2
  fi
  printf '%d%02d%02d\n' "$major" "$minor" "$patch"
}

OLD_BUILD="$(build_number "$OLD_VERSION")"
NEW_BUILD="$(build_number "$NEW_VERSION")"

cd "$ROOT_DIR"
mkdir -p "$TEST_DIR"

echo "Building old local test app $OLD_VERSION ($OLD_BUILD)..."
make bundle VERSION="$OLD_VERSION" BUILD_NUMBER="$OLD_BUILD"
rm -rf "$OLD_APP"
cp -R "$ROOT_DIR/.build/WoWSilicon.app" "$OLD_APP"

echo "Pointing old app at local feed $FEED_URL..."
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $FEED_URL" "$OLD_APP/Contents/Info.plist"
codesign --force --deep --sign - "$OLD_APP" >/dev/null

echo "Building new update DMG and local appcast $NEW_VERSION ($NEW_BUILD)..."
DOWNLOAD_URL_PREFIX="$DOWNLOAD_URL_PREFIX" make appcast VERSION="$NEW_VERSION" BUILD_NUMBER="$NEW_BUILD"

cat <<EOF

Local Sparkle update test is ready.

1. Start the local appcast server:

   cd "$ROOT_DIR/.build/appcast"
   python3 -m http.server "$PORT" --bind "$HOST"

2. In another terminal, open the old test app:

   open "$OLD_APP"

3. In WoWSilicon, choose Options -> Check for Updates...

Nothing was uploaded. The test feed is:

   $FEED_URL

EOF
