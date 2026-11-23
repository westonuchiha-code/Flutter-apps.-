#!/usr/bin/env bash
# Installs the Flutter SDK and the Linux desktop toolchain on Ubuntu/Debian.
# Used for local Linux development and for cloud dev containers.
# Usage: sudo tool/setup_linux_dev.sh   (FLUTTER_VERSION / FLUTTER_DIR may be overridden)
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.50.1}"   # keep in sync with .github/workflows/ci.yml
FLUTTER_DIR="${FLUTTER_DIR:-/opt/flutter}"

apt-get update -qq
apt-get install -y -qq git curl unzip xz-utils clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev libasound2-dev

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
git config --global --add safe.directory "$FLUTTER_DIR"
"$FLUTTER_DIR/bin/flutter" config --no-analytics >/dev/null
"$FLUTTER_DIR/bin/flutter" precache --linux --no-android --no-ios --no-web >/dev/null
echo "Flutter installed at $FLUTTER_DIR. Add $FLUTTER_DIR/bin to your PATH."
