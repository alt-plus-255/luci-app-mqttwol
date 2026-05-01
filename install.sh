#!/bin/sh
# shellcheck shell=dash

set -eu

REPO_API="https://api.github.com/repos/alt-plus-255/luci-app-mqttwol/releases/latest"
DOWNLOAD_DIR="/tmp/luci-app-mqttwol-install"
RETRY_COUNT=3
PKG_FMT="${PKG_FMT:-auto}" # auto|apk|ipk

PKG_IS_APK=0
if command -v apk >/dev/null 2>&1; then
	PKG_IS_APK=1
fi

msg() {
	printf "\033[32;1m%s\033[0m\n" "$1"
}

err() {
	printf "\033[31;1m%s\033[0m\n" "$1" >&2
}

need_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		err "Missing required command: $1"
		exit 1
	fi
}

download_with_retry() {
	url="$1"
	out="$2"
	i=1
	while [ "$i" -le "$RETRY_COUNT" ]; do
		msg "Download $(basename "$out") (attempt $i/$RETRY_COUNT)..."
		if wget -q -O "$out" "$url" && [ -s "$out" ]; then
			return 0
		fi
		rm -f "$out"
		i=$((i + 1))
	done
	return 1
}

pkg_list_update() {
	if [ "$PKG_IS_APK" -eq 1 ]; then
		apk update
	else
		opkg update
	fi
}

pkg_install_repo() {
	pkg="$1"
	if [ "$PKG_IS_APK" -eq 1 ]; then
		apk add "$pkg"
	else
		opkg install "$pkg"
	fi
}

pkg_install_file() {
	pkg_file="$1"
	if [ "$PKG_IS_APK" -eq 1 ]; then
		apk add "$pkg_file"
	else
		opkg install "$pkg_file"
	fi
}

pick_asset_url() {
	pattern="$1"
	printf '%s\n' "$RELEASE_JSON" | grep -o "$pattern" | head -n1
}

check_system() {
	if [ "$(id -u)" -ne 0 ]; then
		err "Run as root."
		exit 1
	fi

	need_cmd wget
	need_cmd grep
	need_cmd sed
	need_cmd awk

	if ! nslookup github.com >/dev/null 2>&1; then
		err "DNS/network is not working."
		exit 1
	fi
}

install_dependencies() {
	msg "Installing dependencies..."
	pkg_install_repo luci-base
	pkg_install_repo mosquitto-client
	pkg_install_repo etherwake
}

resolve_pkg_format() {
	if [ "$PKG_FMT" = "apk" ] || [ "$PKG_FMT" = "ipk" ]; then
		return 0
	fi

	if [ "$PKG_IS_APK" -eq 1 ]; then
		PKG_FMT="apk"
	else
		PKG_FMT="ipk"
	fi
}

fetch_release() {
	msg "Fetching latest release metadata..."
	RELEASE_JSON="$(wget -qO- "$REPO_API" || true)"
	if [ -z "$RELEASE_JSON" ]; then
		err "Failed to get latest release info from GitHub API."
		exit 1
	fi

	if printf '%s' "$RELEASE_JSON" | grep -q "API rate limit exceeded"; then
		err "GitHub API rate limit exceeded. Try later."
		exit 1
	fi
}

install_apk() {
	APK_URL="$(pick_asset_url 'https://[^"[:space:]]*luci-app-mqttwol[^"[:space:]]*\.apk')"

	if [ -z "$APK_URL" ]; then
		err "Release does not contain luci-app-mqttwol .apk asset."
		return 1
	fi

	APK_FILE="$DOWNLOAD_DIR/$(basename "$APK_URL")"

	download_with_retry "$APK_URL" "$APK_FILE" || {
		err "Failed to download apk package."
		return 1
	}

	msg "Installing apk package (allow-untrusted)..."
	apk add --allow-untrusted "$APK_FILE"
}

install_ipk() {
	IPK_URL="$(pick_asset_url 'https://[^"[:space:]]*luci-app-mqttwol[^"[:space:]]*\.ipk')"
	if [ -z "$IPK_URL" ]; then
		err "No .ipk asset found in latest release."
		return 1
	fi

	IPK_FILE="$DOWNLOAD_DIR/$(basename "$IPK_URL")"
	download_with_retry "$IPK_URL" "$IPK_FILE" || {
		err "Failed to download ipk package."
		return 1
	}

	msg "Installing ipk package..."
	pkg_install_file "$IPK_FILE"
}

post_install() {
	msg "Enabling and starting mqttwol service..."
	/etc/init.d/mqttwol enable >/dev/null 2>&1 || true
	/etc/init.d/mqttwol restart >/dev/null 2>&1 || true
	msg "Done. Open LuCI: Services -> MQTT Wake-on-LAN"
}

main() {
	check_system

	rm -rf "$DOWNLOAD_DIR"
	mkdir -p "$DOWNLOAD_DIR"

	resolve_pkg_format
	msg "Package manager: $( [ "$PKG_IS_APK" -eq 1 ] && echo apk || echo opkg )"
	msg "Package format: $PKG_FMT"

	pkg_list_update
	install_dependencies
	fetch_release

	if [ "$PKG_FMT" = "apk" ]; then
		if ! install_apk; then
			err "APK install path failed; trying IPK fallback..."
			install_ipk
		fi
	else
		if ! install_ipk; then
			err "IPK install path failed; trying APK fallback..."
			install_apk
		fi
	fi

	post_install
	rm -rf "$DOWNLOAD_DIR"
}

main "$@"
