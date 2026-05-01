#!/bin/sh

set -eu

# Build both APK/IPK using OpenWrt SDK Docker images and extract artifacts.
# Optimized for repeat runs:
# - SDK dependency layers are built into base images once and reused.
#
# Usage:
#   ./scripts/build-sdk-packages.sh [output_dir] [--rebuild-base]
#
# Output:
#   <output_dir>/apk/luci-app-mqttwol-*.apk
#   <output_dir>/ipk/luci-app-mqttwol-*.ipk

OUT_DIR="${1:-./dist/sdk}"
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
REBUILD_BASE=0

if [ "${2:-}" = "--rebuild-base" ] || [ "${1:-}" = "--rebuild-base" ]; then
	REBUILD_BASE=1
fi

need_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Missing required command: $1" >&2
		exit 1
	fi
}

need_cmd docker

if ! docker info >/dev/null 2>&1; then
	echo "Docker daemon is unavailable for current user." >&2
	echo "Run with sudo or add user to docker group:" >&2
	echo "  sudo ./scripts/build-sdk-packages.sh" >&2
	exit 1
fi

mkdir -p "$OUT_DIR/apk" "$OUT_DIR/ipk"

ensure_base_image() {
	pkg_type="$1"
	base_dockerfile="$2"
	base_image="luci-app-mqttwol-sdk-${pkg_type}-base:local"

	if [ "$REBUILD_BASE" -eq 1 ]; then
		echo "==> Rebuilding ${pkg_type} SDK base image..."
		docker build -f "$base_dockerfile" -t "$base_image" "$ROOT_DIR"
		return
	fi

	if docker image inspect "$base_image" >/dev/null 2>&1; then
		echo "==> Reusing cached ${pkg_type} SDK base image"
	else
		echo "==> Building ${pkg_type} SDK base image (first run)..."
		docker build -f "$base_dockerfile" -t "$base_image" "$ROOT_DIR"
	fi
}

build_and_extract() {
	pkg_type="$1"
	dockerfile="$2"
	ext="$3"

	image="luci-app-mqttwol-sdk-${pkg_type}:local"
	container="luci-app-mqttwol-sdk-${pkg_type}-extract"
	tmp_dir="$OUT_DIR/.tmp-${pkg_type}"
	base_image="luci-app-mqttwol-sdk-${pkg_type}-base:local"

	rm -rf "$tmp_dir"
	mkdir -p "$tmp_dir"

	echo "==> Building ${pkg_type} image..."
	docker build \
		-f "$dockerfile" \
		--build-arg "BASE_IMAGE=$base_image" \
		-t "$image" \
		"$ROOT_DIR"

	echo "==> Extracting ${pkg_type} artifacts..."
	docker rm -f "$container" >/dev/null 2>&1 || true
	docker create --name "$container" "$image" >/dev/null
	docker cp "$container:/builder/bin/packages" "$tmp_dir/"
	docker rm -f "$container" >/dev/null

	found=0
	for f in "$tmp_dir"/packages/*/*/luci-app-mqttwol-*."$ext"; do
		if [ -f "$f" ]; then
			cp -f "$f" "$OUT_DIR/$pkg_type/"
			found=1
		fi
	done

	if [ "$found" -ne 1 ]; then
		echo "No ${ext} artifacts found in SDK output for ${pkg_type}" >&2
		exit 1
	fi
}

ensure_base_image "apk" "$ROOT_DIR/sdk/Dockerfile-sdk-apk-base"
ensure_base_image "ipk" "$ROOT_DIR/sdk/Dockerfile-sdk-ipk-base"
build_and_extract "apk" "$ROOT_DIR/sdk/Dockerfile-sdk-apk" "apk"
build_and_extract "ipk" "$ROOT_DIR/sdk/Dockerfile-sdk-ipk" "ipk"

echo
echo "Build finished. Artifacts:"
ls -lh "$OUT_DIR/apk" "$OUT_DIR/ipk"
