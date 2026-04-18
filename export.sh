#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
EXPORT_DIR="$PROJECT_DIR/../export"
BUILD_DIR="$EXPORT_DIR/web_build"
PROJECT_NAME="lions_in_the_trenches"
EXPORT_PRESET="Web"

if [ ! -d "$EXPORT_DIR" ]; then
	mkdir -p "$EXPORT_DIR"
fi

if ! command -v godot >/dev/null 2>&1; then
	echo "Error: godot not found in PATH"
	exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
	echo "Error: zip not found in PATH"
	exit 1
fi

if ! command -v git >/dev/null 2>&1; then
	echo "Error: git not found in PATH"
	exit 1
fi

DATE_STR="$(date +%Y-%m-%d)"
SHORT_HASH="$(git rev-parse --short HEAD)"

if git describe --tags --exact-match >/dev/null 2>&1; then
	VERSION="$(git describe --tags --exact-match)"
	ARTIFACT_NAME="${PROJECT_NAME}_web_${VERSION}.zip"
else
	LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")"
	COMMITS_SINCE_TAG="$(git rev-list "${LAST_TAG}..HEAD" --count 2>/dev/null || echo "0")"
	VERSION="${LAST_TAG}-dev.${COMMITS_SINCE_TAG}"
	ARTIFACT_NAME="${PROJECT_NAME}_web_${VERSION}_g${SHORT_HASH}_${DATE_STR}.zip"
fi

EXPORT_ENTRY="$BUILD_DIR/index.html"
ZIP_FILE="$EXPORT_DIR/$ARTIFACT_NAME"

if [ -d "$BUILD_DIR" ]; then
	rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"

if [ -f "$ZIP_FILE" ]; then
	rm -f "$ZIP_FILE"
fi

cd "$PROJECT_DIR"
godot --path "$PROJECT_DIR" --export-release "$EXPORT_PRESET" "$EXPORT_ENTRY"

cd "$BUILD_DIR"
zip -r "$ZIP_FILE" .
