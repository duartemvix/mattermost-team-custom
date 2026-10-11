#!/usr/bin/env bash
#
# Builds the custom server image: upstream's Team Edition image with our
# binary, web app and config defaults.
#
# Usage: ./scripts/build-image.sh [tag]
# Requires: podman or docker, plus whatever build-server.sh needs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-custom-mm:dev}"
STAGE="$ROOT/build/image"

# shellcheck source=../upstream.env
source "$ROOT/upstream.env"

# CI sets CONTAINER_ENGINE=docker, because the runners ship podman too and the
# image has to land in the store the push step reads from.
engine="${CONTAINER_ENGINE:-$(command -v podman || command -v docker)}" || {
    echo "needs podman or docker" >&2; exit 1
}
command -v "$engine" >/dev/null || { echo "no such engine: $engine" >&2; exit 1; }

rm -rf "$STAGE"; mkdir -p "$STAGE"
"$ROOT/scripts/build-server.sh" "$STAGE/custom-server"   # also emits $STAGE/client
mv "$STAGE/custom-server" "$STAGE/mattermost-server"
cp "$ROOT/Containerfile" "$STAGE/Containerfile"

# The image rewrites the config upstream ships, so both halves of that go into
# the build context.
mkdir -p "$STAGE/config" "$STAGE/scripts"
cp "$ROOT/config/overrides.json" "$STAGE/config/overrides.json"
cp "$ROOT/scripts/merge-config.py" "$STAGE/scripts/merge-config.py"

"$engine" build --build-arg "BASE_TAG=$SERVER_TAG" -t "$TAG" -f "$STAGE/Containerfile" "$STAGE"
echo "==> $TAG"
