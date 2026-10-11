#!/usr/bin/env bash
#
# Builds the calls plugin bundle (group calls, recording, transcription).
#
# Usage: ./scripts/build-calls.sh [output-dir]
# Requires: git, go, node, npm, make.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
WORK="$ROOT/build/calls"

# shellcheck source=../upstream.env
source "$ROOT/upstream.env"

echo "==> upstream $CALLS_TAG, custom $CALLS_VERSION"
rm -rf "$WORK"; mkdir -p "$(dirname "$WORK")" "$OUT"
git clone --quiet --depth 1 --branch "$CALLS_TAG" \
    https://github.com/mattermost/mattermost-plugin-calls.git "$WORK"

for patch in "$ROOT"/patches/calls/*.patch; do
    echo "    $(basename "$patch")"
    git -C "$WORK" apply "$patch"
done

# The standalone bundle resolves through the webapp's modules, so the webapp
# must be installed first or webpack fails with a few hundred unresolved
# imports that look like our patches broke something. They did not.
( cd "$WORK/webapp" && npm ci --no-audit --no-fund )

make -C "$WORK" dist

# The version is stamped AFTER the build on purpose. `make dist` runs
# `manifest apply`, which rewrites plugin.json from `git describe --tags`, so
# anything set beforehand is discarded. Tagging the checkout does not help
# either: git picks the upstream tag over ours when both point at HEAD.
bundle="$(find "$WORK/dist" -maxdepth 1 -name '*.tar.gz' -print -quit)"
[ -n "$bundle" ] || { echo "build produced no bundle" >&2; exit 1; }

stage="$(mktemp -d)"
tar xzf "$bundle" -C "$stage"
python3 - "$stage/com.mattermost.calls/plugin.json" "$CALLS_VERSION" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
with open(path) as fh:
    m = json.load(fh)
# The plugin id is deliberately unchanged: this is a drop-in replacement
# for official Calls, so existing settings and call history survive the swap.
m["version"] = version
m["name"] = "Calls"
m["homepage_url"] = "https://github.com/duartemvix/mattermost-team-custom"
m["support_url"] = "https://github.com/duartemvix/mattermost-team-custom/issues"
with open(path, "w") as fh:
    json.dump(m, fh, indent=4)
    fh.write("\n")
print(f"    stamped {version}")
PY

target="$OUT/custom-calls-$CALLS_VERSION.tar.gz"
tar czf "$target" -C "$stage" com.mattermost.calls
rm -rf "$stage"
( cd "$OUT" && sha256sum "$(basename "$target")" > "$(basename "$target").sha256" )

echo "==> $target"
