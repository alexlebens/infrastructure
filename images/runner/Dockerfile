# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# =========================================================================
# Minimal runner image: base Gitea runner + mise + cache/registry ENV config.
# All repo tools (including uv, bun, python, etc.) are installed by mise
# into the persistent /cache/mise mount.
# =========================================================================

# renovate: datasource=docker depName=jdxcode/mise versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/jdxcode/mise:2026.11.6@sha256:d4de1845114f6d73e90e15f7642885f74f3ca93074491038a2b9c43e4b897f21 AS mise-source

# =========================================================================
# Gitea Runner Image
# =========================================================================
# renovate: datasource=docker depName=gitea/runner-images versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/gitea/runner-images:ubuntu-26.04@sha256:a71bcbfef0157f767c84efc3dcbc9dc56c249db320b627ed2b802dc867337458

ENV DEBIAN_FRONTEND=noninteractive \
  # --- Mise (persisted on runner /cache/mise mount) ---
  MISE_DATA_DIR="/root/.local/share/mise" \
  MISE_CACHE_DIR="/root/.local/share/mise/cache" \
  MISE_CONFIG_DIR="/etc/mise" \
  MISE_YES="1" \
  MISE_TRUSTED_CONFIG_PATHS="/workspace:/github/workspace" \
  MISE_TASK_RUN_AUTO_INSTALL="true" \
  MISE_EXEC_AUTO_INSTALL="true" \
  # --- uv (persisted on runner /cache/uv mount) ---
  UV_CACHE_DIR="/root/.cache/uv" \
  UV_LINK_MODE="copy" \
  # --- Bun (persisted on runner /cache/bun mount) ---
  BUN_INSTALL_CACHE_DIR="/root/.bun/install/cache" \
  # --- Trivy (Harbor proxy caches avoid upstream rate limits) ---
  TRIVY_CACHE_DIR="/opt/trivy-cache" \
  TRIVY_DB_REPOSITORY="harbor.alexlebens.dev/proxy-ghcr.io/aquasecurity/trivy-db:2" \
  TRIVY_JAVA_DB_REPOSITORY="harbor.alexlebens.dev/proxy-ghcr.io/aquasecurity/trivy-java-db:1" \
  PATH="/root/.local/share/mise/shims:/root/.local/bin:${PATH}"

COPY --link --from=mise-source /usr/local/bin/mise /usr/local/bin/mise

RUN --mount=type=bind,source=verify-tools.sh,target=/tmp/verify-tools.sh \
  bash /tmp/verify-tools.sh
