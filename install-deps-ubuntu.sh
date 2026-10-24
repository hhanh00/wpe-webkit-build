#!/usr/bin/env bash
# Install the packages build.sh needs on Ubuntu 24.04 (also Debian trixie).
# bubblewrap and xdg-dbus-proxy are runtime tools, but WebKit's configure step
# runs `bwrap --version` and checks both paths. Run as root or with sudo.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl xz-utils patch patchelf binutils bubblewrap xdg-dbus-proxy \
  clang lld cmake ninja-build meson pkg-config gperf ruby python3 unifdef \
  perl libfile-copy-recursive-perl gettext bison flex \
  libglib2.0-dev libsoup-3.0-dev libicu-dev libxml2-dev libxslt1-dev \
  libsqlite3-dev libharfbuzz-dev libfreetype-dev libfontconfig-dev \
  libjpeg-dev libpng-dev libwebp-dev libavif-dev libjxl-dev liblcms2-dev \
  libepoxy-dev libegl1-mesa-dev libgles2-mesa-dev libgbm-dev \
  libdrm-dev libxkbcommon-dev libgcrypt20-dev libtasn1-6-dev libhyphen-dev \
  libsecret-1-dev libseccomp-dev libexpat1-dev zlib1g-dev
