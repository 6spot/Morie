#!/bin/sh
set -eu

OUTPUT_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
OUTPUT_FILE="$OUTPUT_DIR/MorieBuildIdentity.plist"

COMMIT="$(git -C "$SRCROOT" rev-parse --short=8 HEAD 2>/dev/null || printf 'unknown')"
BRANCH="$(git -C "$SRCROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'detached')"

DIRTY=false
if ! git -C "$SRCROOT" diff --quiet --ignore-submodules HEAD -- 2>/dev/null; then
  DIRTY=true
fi

mkdir -p "$OUTPUT_DIR"
/usr/bin/plutil -create xml1 "$OUTPUT_FILE"
/usr/bin/plutil -insert commit -string "$COMMIT" "$OUTPUT_FILE"
/usr/bin/plutil -insert branch -string "$BRANCH" "$OUTPUT_FILE"
/usr/bin/plutil -insert dirty -bool "$DIRTY" "$OUTPUT_FILE"
