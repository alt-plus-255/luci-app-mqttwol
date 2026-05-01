#!/bin/sh

set -eu

# Prepares publish-ready artifacts:
# - luci-app-mqttwol-<version>.apk
# - public-key.pem (for /etc/apk/keys on routers)
# - install command helper text
#
# Usage:
#   ./scripts/prepare-release-artifacts.sh /path/to/openwrt ./dist

OPENWRT_DIR="${1:-}"
OUT_DIR="${2:-./dist}"

if [ -z "$OPENWRT_DIR" ]; then
	echo "Usage: $0 <openwrt_dir> [output_dir]" >&2
	exit 1
fi

if [ ! -d "$OPENWRT_DIR" ]; then
	echo "OpenWrt dir not found: $OPENWRT_DIR" >&2
	exit 1
fi

PKG_PATH="$(ls -1 "$OPENWRT_DIR"/bin/packages/*/base/luci-app-mqttwol-*.apk 2>/dev/null | sort | tail -n1 || true)"

if [ -z "$PKG_PATH" ] || [ ! -f "$PKG_PATH" ]; then
	echo "Package not found. Build first:" >&2
	echo "  make package/luci-app-mqttwol/compile V=s -j1" >&2
	exit 1
fi

KEY_PATH="$OPENWRT_DIR/public-key.pem"
if [ ! -f "$KEY_PATH" ]; then
	echo "Missing $KEY_PATH (OpenWrt signing pubkey)." >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
cp -f "$PKG_PATH" "$OUT_DIR/"
cp -f "$KEY_PATH" "$OUT_DIR/public-key.pem"

PKG_FILE="$(basename "$PKG_PATH")"

cat > "$OUT_DIR/INSTALL-ON-ROUTER.txt" <<EOF
Upload these two files to your release/assets:
  - $PKG_FILE
  - public-key.pem

Router install commands:
  wget -O /etc/apk/keys/luci-app-mqttwol.pem "<PUBLIC_KEY_URL>"
  wget -O /tmp/$PKG_FILE "<APK_URL>"
  apk add /tmp/$PKG_FILE

Example with local files already on router:
  cp /tmp/public-key.pem /etc/apk/keys/luci-app-mqttwol.pem
  apk add /tmp/$PKG_FILE
EOF

echo "Artifacts prepared in: $OUT_DIR"
ls -lh "$OUT_DIR"
