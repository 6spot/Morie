#!/bin/sh
set -eu

TEAM_ID="${1:-}"

if [ -z "$TEAM_ID" ]; then
  echo "Usage: sh scripts/setup-local-signing.sh YOUR_TEAM_ID" >&2
  exit 64
fi

case "$TEAM_ID" in
  *[!A-Za-z0-9]*)
    echo "Team ID should contain only letters and numbers." >&2
    exit 64
    ;;
esac

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/Config/LocalSigning.xcconfig"

mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" <<EOF
// Local Apple signing settings. This file is intentionally ignored by Git.
MORIE_DEVELOPMENT_TEAM = $TEAM_ID
EOF

echo "Wrote local signing configuration:"
echo "  $CONFIG_FILE"
echo
echo "Verify with:"
echo "  xcodebuild -project Morie.xcodeproj -scheme Morie -showBuildSettings | grep DEVELOPMENT_TEAM"
