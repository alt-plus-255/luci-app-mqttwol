#!/bin/sh

set -eu

# One-shot router installer for published APK builds.
#
# Usage on router:
#   sh router-install.sh <APK_URL> <PUBKEY_URL> [key_name]
#
# Example:
#   sh router-install.sh \
#     https://example.com/luci-app-mqttwol-1.0-r1.apk \
#     https://example.com/public-key.pem

APK_URL="${1:-}"
PUBKEY_URL="${2:-}"
KEY_NAME="${3:-luci-app-mqttwol.pem}"

if [ -z "$APK_URL" ] || [ -z "$PUBKEY_URL" ]; then
	echo "Usage: $0 <apk_url> <pubkey_url> [key_name]" >&2
	exit 1
fi

if ! command -v apk >/dev/null 2>&1; then
	echo "apk is not available on this system." >&2
	exit 1
fi

if ! command -v wget >/dev/null 2>&1; then
	echo "wget is required on router." >&2
	exit 1
fi

KEY_PATH="/etc/apk/keys/$KEY_NAME"
PKG_PATH="/tmp/luci-app-mqttwol.apk"

echo "[1/4] Download and install package public key..."
wget -q -O "$KEY_PATH" "$PUBKEY_URL"
chmod 0644 "$KEY_PATH"

echo "[2/4] Download package..."
wget -q -O "$PKG_PATH" "$APK_URL"

echo "[3/4] Install package..."
apk add "$PKG_PATH"

echo "[4/4] Enable and restart service..."
/etc/init.d/mqttwol enable >/dev/null 2>&1 || true
/etc/init.d/mqttwol restart >/dev/null 2>&1 || true

echo "Done. Open LuCI: Services -> MQTT Wake-on-LAN"
