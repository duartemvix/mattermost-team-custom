# Custom Mattermost Team Edition image.
#
# Built on the official Team Edition image for the pinned release. Three
# things change: the server binary (OIDC provider, guests, badge removal),
# the web app (guest screens, badge removal, adaptive OIDC button icon),
# and the config defaults below.

ARG BASE_TAG=v11.11.1
FROM docker.io/mattermost/mattermost-team-edition:${BASE_TAG} AS upstream

# The guest administration screens and the licence badges live in the web app,
# so upstream's prebuilt one has to be replaced or those two patches do nothing
# at all.
#
# COPY merges rather than replaces, and the base image has no shell to delete
# with, so upstream's bundles would otherwise linger: unreachable, because
# every filename is content hashed and our root.html references only ours, but
# still around 87 MB. This stage empties them, so nothing stale is reachable.
# It does not shrink the image: layers are additive, so the base layer keeps
# the originals either way.
FROM docker.io/library/alpine:3.20 AS webapp
COPY --from=upstream /mattermost/client /old
COPY client /new
RUN set -eu; \
    mkdir -p /out; \
    cp -a /new/. /out/; \
    cd /old; \
    find . -type f | while read -r f; do \
        if [ ! -e "/out/$f" ]; then \
            mkdir -p "/out/$(dirname "$f")"; \
            : > "/out/$f"; \
        fi; \
    done

# The image ships a fully written config.json, so every default our patches set
# in Go is already spelled out in that file and never reached. Patching the Go
# constant stays right for anyone building from source; this makes it true for
# the image too. Only the keys in config/overrides.json change.
FROM docker.io/library/alpine:3.20 AS config
RUN apk add --no-cache python3
COPY --from=upstream /mattermost/config/config.json /in.json
COPY config/overrides.json /overrides.json
COPY scripts/merge-config.py /merge.py
RUN python3 /merge.py /in.json /overrides.json /out.json


FROM docker.io/mattermost/mattermost-team-edition:${BASE_TAG}

COPY --chown=2000:2000 mattermost-server /mattermost/bin/mattermost
COPY --from=webapp --chown=2000:2000 /out /mattermost/client
COPY --from=config --chown=2000:2000 --chmod=600 /out.json /mattermost/config/config.json

# Playbooks ships prepackaged and then refuses to activate without a
# Professional licence, so all it contributes is an error on every start.
ENV MM_PREPACKAGED_PLUGINS_SKIP=mattermost-plugin-playbooks-

LABEL org.opencontainers.image.title="Custom Mattermost Team Edition" \
      org.opencontainers.image.description="Mattermost Team Edition with OIDC SSO, guests and no free-tier nag" \
      org.opencontainers.image.source="https://github.com/duartemvix/mattermost-team-custom" \
      org.opencontainers.image.licenses="AGPL-3.0-only"
