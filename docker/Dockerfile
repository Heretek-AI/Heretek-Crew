# syntax=docker/dockerfile:1.20
#
# Heretek-Crew: Paperclip + OpenCode v2 image.
#
# Strategy: EXTEND the official Paperclip build, do not fork it. The official
# image is built first from the pinned Paperclip source in /tmp/paperclip,
# then this Dockerfile layers the OpenCode v2 toolchain and the CLI
# compatibility shim on top.
#
# Two-step build (build context = this repository):
#   1. docker build -t paperclip:official-local /tmp/paperclip
#      (uses Paperclip's official Dockerfile; base node:24-trixie-slim)
#   2. docker build -f docker/Dockerfile \
#        --build-arg PAPERCLIP_BASE_IMAGE=paperclip:official-local \
#        -t heretek-crew/paperclip:wave1 .
#
# Pinned versions (never `latest`):
#   node base ........... node:24-trixie-slim (inherited from official base)
#   postgres ............ postgres:17-alpine (see docker-compose.yml)
#   @opencode/cli ....... 2.0.32
#   @opencode/client .... 2.0.32
#   @heretek-ai/opencode-harness .. 1.0.7
#   opencode-mem ........ 2.31.3 (memory plugin referenced by fleet roles;
#                         provides persistent Turso/libSQL-backed memory)
#   @prevalentware/opencode-goal-plugin .. 0.1.64 (goal-tracking plugin
#                         referenced by exec-director; npm dist-tag latest
#                         verified 2026-10-17 — Wave C P0-5: installed here so
#                         it resolves from the image, not ambient cache luck)
#   caddy ............... 2.11.7-alpine (see docker-compose.yml)
#   tailscale ........... v1.104.1 (see docker-compose.yml)

ARG PAPERCLIP_BASE_IMAGE=paperclip:official-local
FROM ${PAPERCLIP_BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Promote pins to ENV so `docker inspect` records exactly what is installed.
ENV OPENCODE_CLI_VERSION=2.0.32 \
    OPENCODE_CLIENT_VERSION=2.0.32 \
    OPENCODE_HARNESS_VERSION=1.0.7 \
    OPENCODE_MEM_VERSION=2.31.3 \
    OPENCODE_GOAL_PLUGIN_VERSION=0.1.64

# Everything in this layer needs root; the runtime user is dropped to `node`
# by the inherited official entrypoint (see USER note below).
USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        curl \
        jq \
        tini \
        ripgrep \
        python3 \
        ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /usr/local/bin/opencode /usr/local/bin/opencode-bin; \
    npm install --global --omit=dev --force \
        "@opencode/cli@${OPENCODE_CLI_VERSION}" \
        "@opencode/client@${OPENCODE_CLIENT_VERSION}" \
        "@heretek-ai/opencode-harness@${OPENCODE_HARNESS_VERSION}" \
        "opencode-mem@${OPENCODE_MEM_VERSION}" \
        "@prevalentware/opencode-goal-plugin@${OPENCODE_GOAL_PLUGIN_VERSION}"; \
    npm ls --global --depth=0 "@opencode/cli" "@opencode/client" "@heretek-ai/opencode-harness" "opencode-mem" "@prevalentware/opencode-goal-plugin"; \
    test -x /usr/local/bin/opencode || { echo "ERROR: /usr/local/bin/opencode missing after npm install" >&2; exit 1; }; \
    case "$(readlink /usr/local/bin/opencode)" in \
        *@opencode/cli*) ;; \
        *) echo "ERROR: /usr/local/bin/opencode does not point at @opencode/cli v2" >&2; exit 1 ;; \
    esac; \
    mv /usr/local/bin/opencode /usr/local/bin/opencode-bin; \
    test -x /usr/local/bin/opencode-bin || { echo "ERROR: opencode-bin move failed" >&2; exit 1; }; \
    /usr/local/bin/opencode-bin --help >/dev/null; \
    mkdir -p /paperclip /paperclip/workspaces /roles /workspaces; \
    chown -R node:node /paperclip /roles /workspaces; \
    chmod 755 /paperclip /roles /workspaces

# Install the OpenCode v2 compatibility shim as `opencode` (earlier on PATH
# than nothing else; it delegates to /usr/local/bin/opencode-bin).
COPY scripts/opencode-shim.sh /usr/local/bin/opencode
RUN chmod +x /usr/local/bin/opencode \
    && test -x /usr/local/bin/opencode \
    && test -x /usr/local/bin/opencode-bin

# App home for named/bind mounts. The server reads PAPERCLIP_HOME=/paperclip
# (inherited ENV from the official base); /app stays the code workdir because
# CMD below addresses server/dist relative to it.
WORKDIR /app

# Runtime user note (deliberate, security-reviewed):
# There is intentionally NO `USER node` directive here. The inherited
# official entrypoint (docker-entrypoint.sh) starts as root, repairs
# ownership of the /paperclip data volume (fresh Docker named volumes arrive
# root-owned and would otherwise crash the server on its first mkdir), then
# `exec gosu node` so the Paperclip server and every agent child process run
# as `node` (UID 1000). Declaring `USER node` would silently disable that
# repair and break first boot. Effective runtime user: node (UID 1000).
#
# ENTRYPOINT is re-declared identical to the official base so this layer is
# explicit about PID 1: tini reaps zombie agent/tool descendants and forwards
# signals; the entrypoint then drops privileges to node.
ENTRYPOINT ["/usr/bin/tini", "--", "docker-entrypoint.sh"]
CMD ["node", "--import", "./server/node_modules/tsx/dist/loader.mjs", "server/dist/index.js"]

LABEL org.opencontainers.image.title="heretek-crew/paperclip" \
      org.opencontainers.image.description="Paperclip orchestrating OpenCode v2 agents via CLI compatibility shim" \
      org.opencontainers.image.version="wave1" \
      heretek.opencode-cli="2.0.32" \
      heretek.opencode-client="2.0.32"
