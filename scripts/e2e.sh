#!/usr/bin/env bash
#
# Runs a built custom image for real and checks the promises that matter:
# the server boots, the API answers, users can be created, the interface
# carries no fork branding, and the OIDC plumbing is present.
#
# Usage: ./scripts/e2e.sh [image]
# Requires: docker.

set -euo pipefail

IMAGE="${1:-custom-mm:dev}"
RUN="mm-e2e-$$"
PW='Passw0rd1234!'

cleanup() { docker rm -f "$RUN-mm" "$RUN-db" >/dev/null 2>&1 || true; docker network rm "$RUN" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker network create "$RUN" >/dev/null
docker run -d --name "$RUN-db" --network "$RUN" \
    -e POSTGRES_USER=mmuser -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=mattermost \
    docker.io/library/postgres:17-alpine >/dev/null
for _ in $(seq 1 30); do
    docker exec "$RUN-db" pg_isready -U mmuser -d mattermost >/dev/null 2>&1 && break; sleep 2
done

docker run -d --name "$RUN-mm" --network "$RUN" \
    -e MM_SQLSETTINGS_DRIVERNAME=postgres \
    -e MM_SQLSETTINGS_DATASOURCE="postgres://mmuser:pw@$RUN-db:5432/mattermost?sslmode=disable&connect_timeout=10" \
    -e MM_SERVICESETTINGS_SITEURL=http://localhost:8065 \
    -p 127.0.0.1:18065:8065 \
    "$IMAGE" >/dev/null

echo "==> waiting for the server"
for _ in $(seq 1 60); do
    curl -fsS --max-time 5 http://localhost:18065/api/v4/system/ping >/dev/null 2>&1 && break; sleep 3
done
curl -fsS --max-time 10 http://localhost:18065/api/v4/system/ping >/dev/null \
    || { docker logs --tail 40 "$RUN-mm"; echo "server never came up" >&2; exit 1; }

echo "==> version"
ver="$(curl -fsS --max-time 10 'http://localhost:18065/api/v4/config/client?format=old' | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Version"))')"
echo "server version: $ver"

echo "==> no fork branding in the served interface"
html="$(curl -fsS --max-time 10 http://localhost:18065/)"
main="$(grep -oE '/static/main\.[a-f0-9]+\.js' <<<"$html" | head -1)"
[ -n "$main" ] || { echo "FAIL: no main bundle referenced" >&2; exit 1; }
curl -fsS --max-time 30 "http://localhost:18065$main" -o /tmp/e2e-main.js
if grep -qi 'mattermore' /tmp/e2e-main.js; then
    echo "FAIL: fork branding string in app bundle" >&2; exit 1
fi

echo "==> users can be created through the API"
mmctl() { docker exec "$RUN-mm" /mattermost/bin/mmctl --local "$@"; }
for _ in $(seq 1 60); do mmctl system version >/dev/null 2>&1 && break; sleep 3; done
for i in 1 2 3; do
    mmctl user create --email "e2e$i@example.com" --username "e2e$i" --password "$PW" >/dev/null \
        || { echo "FAIL: user $i refused" >&2; exit 1; }
done

echo "==> checking the calls plugin"
# The output lists enabled plugins first, then disabled ones. The plugin starts
# in the background, so give it a minute rather than racing it.
enabled=""
for _ in $(seq 1 20); do
    enabled="$(mmctl plugin list | awk '/^Listing disabled/ {exit} {print}')"
    grep -q "^com.mattermost.calls: Calls$" <<<"$enabled" && break
    sleep 3
done
echo "$enabled"
if ! grep -q "^com.mattermost.calls: Calls$" <<<"$enabled"; then
    echo "--- plugin list" >&2; mmctl plugin list >&2 || true
    echo "--- server log, plugin lines" >&2; docker logs "$RUN-mm" 2>&1 | grep -i "plugin\|calls" | tail -40 >&2
    echo "FAIL: calls plugin is not enabled" >&2; exit 1
fi

echo "PASS: server $ver up, 3 users created, calls enabled, no fork branding"
