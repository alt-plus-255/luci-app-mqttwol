#!/bin/sh

set -eu

# Persistent SDK build flow:
# - base SDK images are created once and reused
# - builder containers are created once and reused
# - reset only by explicit flag
#
# Usage:
#   ./build-sdk-packages.sh [--out-dir <dir>] [--enable-log] [--rebuild-base] [--reset-builders] [--only-apk|--only-ipk]

OUT_DIR="./dist/sdk"
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REBUILD_BASE=0
RESET_BUILDERS=0
ONLY_APK=0
ONLY_IPK=0
LOG_FILE=""
MAKE_VERBOSE="${MAKE_VERBOSE:-sc}"
ENABLE_LOG=0

EXPECT_OUT_DIR=0
for arg in "$@"; do
	if [ "$EXPECT_OUT_DIR" -eq 1 ]; then
		OUT_DIR="$arg"
		EXPECT_OUT_DIR=0
		continue
	fi

	case "$arg" in
		--out-dir)
			EXPECT_OUT_DIR=1
			;;
		--enable-log)
			ENABLE_LOG=1
			;;
		--rebuild-base) REBUILD_BASE=1 ;;
		--reset-builders) RESET_BUILDERS=1 ;;
		--only-apk) ONLY_APK=1 ;;
		--only-ipk) ONLY_IPK=1 ;;
		--*)
			echo "Unknown option: $arg" >&2
			exit 1
			;;
		*) OUT_DIR="$arg" ;;
	esac
done

if [ "$EXPECT_OUT_DIR" -eq 1 ]; then
	echo "Missing value for --out-dir" >&2
	exit 1
fi

if [ "$ONLY_APK" -eq 1 ] && [ "$ONLY_IPK" -eq 1 ]; then
	echo "Use only one mode: --only-apk or --only-ipk" >&2
	exit 1
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
	echo "  sudo ./build-sdk-packages.sh" >&2
	exit 1
fi

mkdir -p "$OUT_DIR/apk" "$OUT_DIR/ipk"
mkdir -p "$OUT_DIR/.tmp-apk" "$OUT_DIR/.tmp-ipk"
if [ "$ENABLE_LOG" -eq 1 ]; then
	mkdir -p "$OUT_DIR/logs"
	LOG_FILE="$OUT_DIR/logs/build-$(date +%Y%m%d-%H%M%S).log"
	touch "$LOG_FILE"
fi

log() {
	msg="$1"
	echo "$msg"
	if [ "$ENABLE_LOG" -eq 1 ]; then
		printf '%s %s\n' "$(date '+%F %T')" "$msg" >> "$LOG_FILE"
	fi
}

run_logged() {
	if [ "$ENABLE_LOG" -eq 1 ]; then
		printf '\n$ %s\n' "$*" | tee -a "$LOG_FILE"
		pipe_file="$(mktemp -u)"
		mkfifo "$pipe_file"
		tee -a "$LOG_FILE" <"$pipe_file" &
		tee_pid=$!
		"$@" >"$pipe_file" 2>&1
		cmd_status=$?
		rm -f "$pipe_file"
		wait "$tee_pid" || true
		return "$cmd_status"
	fi

	printf '\n$ %s\n' "$*"
	"$@"
}

log "Build root: $ROOT_DIR"
log "Output dir: $OUT_DIR"
log "Logging enabled: $ENABLE_LOG"
if [ "$ENABLE_LOG" -eq 1 ]; then
	log "Log file: $LOG_FILE"
fi
log "Make verbosity: $MAKE_VERBOSE (override: MAKE_VERBOSE=s ./build-sdk-packages.sh ...)"
if [ "$ONLY_APK" -eq 1 ]; then
	log "Mode: only APK"
elif [ "$ONLY_IPK" -eq 1 ]; then
	log "Mode: only IPK"
else
	log "Mode: APK + IPK"
fi
log "Rebuild base images: $REBUILD_BASE"
log "Reset builder containers: $RESET_BUILDERS"

ensure_base_image() {
	pkg_type="$1"
	base_dockerfile="$2"
	base_image="luci-app-mqttwol-sdk-${pkg_type}-base:local"

	if [ "$REBUILD_BASE" -eq 1 ]; then
		log "==> Rebuilding ${pkg_type} SDK base image..."
		run_logged docker build --progress=plain -f "$base_dockerfile" -t "$base_image" "$ROOT_DIR"
		return
	fi

	if docker image inspect "$base_image" >/dev/null 2>&1; then
		log "==> Reusing cached ${pkg_type} SDK base image"
	else
		log "==> Building ${pkg_type} SDK base image (first run)..."
		run_logged docker build --progress=plain -f "$base_dockerfile" -t "$base_image" "$ROOT_DIR"
	fi
}

ensure_builder_container() {
	pkg_type="$1"
	base_image="luci-app-mqttwol-sdk-${pkg_type}-base:local"
	builder="luci-app-mqttwol-sdk-${pkg_type}-builder"

	if [ "$RESET_BUILDERS" -eq 1 ]; then
		log "==> Resetting ${pkg_type} builder container..."
		docker rm -f "$builder" >/dev/null 2>&1 || true
	fi

	if ! docker container inspect "$builder" >/dev/null 2>&1; then
		log "==> Creating ${pkg_type} builder container (first run)..."
		run_logged docker create --name "$builder" -w /builder "$base_image" sleep infinity
	fi

	if [ "$(docker inspect -f '{{.State.Running}}' "$builder")" != "true" ]; then
		run_logged docker start "$builder"
	fi
}

build_in_container() {
	pkg_type="$1"
	ext="$2"
	builder="luci-app-mqttwol-sdk-${pkg_type}-builder"
	tmp_dir="$OUT_DIR/.tmp-${pkg_type}"

	log "==> Building ${pkg_type} package in persistent container..."
	run_logged docker exec "$builder" sh -lc "rm -rf /builder/package/feeds/base/luci-app-mqttwol && mkdir -p /builder/package/feeds/base/luci-app-mqttwol"
	run_logged docker cp "$ROOT_DIR/luci-app-mqttwol/." "$builder:/builder/package/feeds/base/luci-app-mqttwol/"
	run_logged docker exec "$builder" sh -lc "[ -f /builder/.config ] || touch /builder/.config"
	run_logged docker exec "$builder" sh -lc "sed -i '/^CONFIG_PACKAGE_luci-app-mqttwol=/d' /builder/.config && printf 'CONFIG_PACKAGE_luci-app-mqttwol=m\n' >> /builder/.config"
	run_logged docker exec "$builder" sh -lc "cd /builder && make defconfig"
	run_logged docker exec "$builder" sh -lc "cd /builder && make package/feeds/base/luci-app-mqttwol/compile V=$MAKE_VERBOSE -j\"\$(nproc)\""

	log "==> Extracting ${pkg_type} artifacts..."
	run_logged docker cp "$builder:/builder/bin/packages" "$tmp_dir/"

	found=0
	for f in "$tmp_dir"/packages/*/*/luci-app-mqttwol*."$ext"; do
		if [ -f "$f" ]; then
			cp -f "$f" "$OUT_DIR/$pkg_type/"
			found=1
		fi
	done

	if [ "$found" -ne 1 ]; then
		log "No ${ext} artifacts found in SDK output for ${pkg_type}"
		exit 1
	fi
}

if [ "$ONLY_IPK" -ne 1 ]; then
	ensure_base_image "apk" "$ROOT_DIR/sdk/Dockerfile-sdk-apk-base"
	ensure_builder_container "apk"
	build_in_container "apk" "apk"
fi

if [ "$ONLY_APK" -ne 1 ]; then
	ensure_base_image "ipk" "$ROOT_DIR/sdk/Dockerfile-sdk-ipk-base"
	ensure_builder_container "ipk"
	build_in_container "ipk" "ipk"
fi

log ""
log "Build finished. Artifacts:"
if [ "$ONLY_IPK" -ne 1 ]; then
	run_logged ls -lh "$OUT_DIR/apk"
fi
if [ "$ONLY_APK" -ne 1 ]; then
	run_logged ls -lh "$OUT_DIR/ipk"
fi
if [ "$ENABLE_LOG" -eq 1 ]; then
	log "Log saved to: $LOG_FILE"
fi
