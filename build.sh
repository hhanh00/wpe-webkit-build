#!/usr/bin/env bash
# Build libwpe and WPE WebKit into a self-contained prefix and pack it as a
# tarball for the zkool Linux webview.
#
#   ./build.sh [--prefix DIR] [--out DIR] [--jobs N] [--no-strip] [--configure-only]
#
# Versions and checksums come from versions.env; the WebKit configure options
# from cmake-flags.txt. The result is relocatable: every shared object gets an
# $ORIGIN rpath, the helper processes live under lib/wpe/wpe-webkit-2.0 and
# find the libraries through $ORIGIN/../.., and WebKit is patched to honour
# WEBKIT_EXEC_PATH outside developer mode (see patches/).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=versions.env
source "$here/versions.env"

PREFIX=/opt/wpe
OUT="$PWD/dist"
JOBS=$(nproc)
STRIP=1
CONFIGURE_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --jobs) JOBS=$2; shift 2 ;;
    --no-strip) STRIP=0; shift ;;
    --configure-only) CONFIGURE_ONLY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

WORK=${WORK:-$PWD/work}
ARCH=$(uname -m)
DISTRO=$(. /etc/os-release && echo "${ID}${VERSION_ID}")
mkdir -p "$WORK" "$OUT" "$PREFIX"

fetch() { # url sha256 -> path
  local url=$1 sha=$2 file
  file="$WORK/$(basename "$url")"
  if [ ! -f "$file" ]; then
    curl --fail --location --retry 5 --retry-delay 5 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  echo "$sha  $file" | sha256sum -c - >/dev/null
  echo "$file"
}

# Configure options, comments and blank lines removed.
mapfile -t WPE_FLAGS < <(grep -vE '^\s*(#|$)' "$here/cmake-flags.txt")

# ---- libwpe ---------------------------------------------------------------
libwpe_tar=$(fetch "https://wpewebkit.org/releases/libwpe-${LIBWPE_VERSION}.tar.xz" "$LIBWPE_SHA256")
libwpe_src="$WORK/libwpe-${LIBWPE_VERSION}"
[ -d "$libwpe_src" ] || tar -C "$WORK" -xf "$libwpe_tar"
meson setup "$libwpe_src/build" "$libwpe_src" \
  --prefix="$PREFIX" --libdir=lib --buildtype=release -Dbuild-docs=false \
  >"$WORK/libwpe-configure.log" 2>&1 || { tail -50 "$WORK/libwpe-configure.log"; exit 1; }
ninja -C "$libwpe_src/build" -j"$JOBS" install

# ---- WPE WebKit -----------------------------------------------------------
wpe_tar=$(fetch "https://wpewebkit.org/releases/wpewebkit-${WPE_VERSION}.tar.xz" "$WPE_SHA256")
wpe_src="$WORK/wpewebkit-${WPE_VERSION}"
if [ ! -d "$wpe_src" ]; then
  tar -C "$WORK" -xf "$wpe_tar"
  for p in "$here"/patches/0*.patch; do
    echo "applying $(basename "$p")"
    patch -d "$wpe_src" -p1 --forward <"$p"
  done
fi

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
cmake -S "$wpe_src" -B "$wpe_src/build" -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_INSTALL_LIBEXECDIR=lib/wpe \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DUSE_LD_LLD=ON \
  -DBWRAP_EXECUTABLE=/usr/bin/bwrap \
  -DDBUS_PROXY_EXECUTABLE=/usr/bin/xdg-dbus-proxy \
  "${WPE_FLAGS[@]}"

if [ "$CONFIGURE_ONLY" = 1 ]; then
  echo "configure finished; stopping as requested"
  exit 0
fi

ninja -C "$wpe_src/build" -j"$JOBS"
cmake --install "$wpe_src/build"

# ---- relocation -----------------------------------------------------------
helpers="$PREFIX/lib/wpe/wpe-webkit-2.0"
for so in "$PREFIX"/lib/*.so*; do
  [ -L "$so" ] && continue
  patchelf --set-rpath '$ORIGIN' "$so"
done
for exe in "$helpers"/WPE*Process; do
  patchelf --set-rpath '$ORIGIN/../..' "$exe"
done
bundle="$PREFIX/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
[ -f "$bundle" ] && patchelf --set-rpath '$ORIGIN/../..' "$bundle"

if [ "$STRIP" = 1 ]; then
  find "$PREFIX/lib" -type f \( -name '*.so*' -o -name 'WPE*Process' \) \
    -exec strip --strip-unneeded {} +
fi

# ---- manifest -------------------------------------------------------------
{
  echo "wpewebkit=$WPE_VERSION"
  echo "libwpe=$LIBWPE_VERSION"
  echo "distro=$DISTRO"
  echo "arch=$ARCH"
  echo "prefix=$PREFIX"
  echo "recipe=$(git -C "$here" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "patches=$(cd "$here/patches" && ls 0*.patch | tr '\n' ' ')"
  echo "flags=${WPE_FLAGS[*]}"
  echo
  echo "# shared libraries libWPEWebKit-2.0.so needs from the host"
  ldd "$PREFIX"/lib/libWPEWebKit-2.0.so.1 | awk '/=> \//{print $1, $3}' | grep -v "$PREFIX" | sort
} >"$PREFIX/MANIFEST.txt"

name="wpe-webkit-${WPE_VERSION}-${DISTRO}-${ARCH}"
tar -C "$PREFIX" -cJf "$OUT/$name.tar.xz" .
(cd "$OUT" && sha256sum "$name.tar.xz" >"$name.tar.xz.sha256")
cp "$PREFIX/MANIFEST.txt" "$OUT/$name.manifest.txt"
echo "wrote $OUT/$name.tar.xz"
