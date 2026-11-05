# syntax=docker/dockerfile:1
# =========================================================================
# Tool sources updated by Renovate (via Harbor registry proxy caches)
# =========================================================================

# --- Package & Tool Managers ---
# renovate: datasource=docker depName=jdxcode/mise versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/jdxcode/mise:2026.10.25@sha256:91417f41840316b7c5da6854bef393eccea4546ae70f8baf0803e0e94287b68d AS mise-source
# renovate: datasource=docker depName=oven/bun versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/oven/bun:1.4.4@sha256:1d22548f177f4ff38e0c15baa3c2c46c6c2060ba2d1bc573bb4720b407548f1d AS bun-source
# renovate: datasource=docker depName=ghcr.io/astral-sh/uv versioning=docker
FROM harbor.alexlebens.dev/proxy-ghcr.io/astral-sh/uv:0.13.7@sha256:96f40d3904aad8d0bd010539001d36c8e2188b981e1334471a90c4a1d93bb490 AS uv-source

# --- Cross-Repo Linters, Testing & CLI Utilities ---
# renovate: datasource=docker depName=rhysd/actionlint versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 AS actionlint-source
# renovate: datasource=docker depName=bats/bats versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/bats/bats:1.14.0@sha256:5322b877351fda0cc435de8c6116de7d0a2ec79d7c680132a0ef329a633bc66f AS bats-source
# renovate: datasource=docker depName=ghcr.io/jqlang/jq versioning=docker
FROM harbor.alexlebens.dev/proxy-ghcr.io/jqlang/jq:1.8.2@sha256:b9c68867e5766576263a222e91db3de422d802069c7af70440e667a95344e486 AS jq-source
# renovate: datasource=docker depName=lycheeverse/lychee versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/lycheeverse/lychee:0.24.2@sha256:e2d19e57cf6ab037026f20b8e449a1f30d9d7f81eef4194763aab2eab20bd28d AS lychee-source
# renovate: datasource=docker depName=ghcr.io/astral-sh/ruff versioning=docker
FROM harbor.alexlebens.dev/proxy-ghcr.io/astral-sh/ruff:0.17.3-debian@sha256:e7311317f3583bd199ee6eace2a3ab08797271c9c1c26912e5fdeb3bb94305eb AS ruff-source
# renovate: datasource=docker depName=koalaman/shellcheck versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d AS shellcheck-source
# renovate: datasource=docker depName=mikefarah/yq versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/mikefarah/yq:4.54.1@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e AS yq-source

# --- GitOps, Kubernetes & Cloud-Native Tooling ---
# renovate: datasource=docker depName=quay.io/argoproj/argocd versioning=docker
FROM harbor.alexlebens.dev/proxy-quay.io/argoproj/argocd:v3.6.1@sha256:296e3d74f449b2ce45265613fcb68c18ed7366488360c8ea32f5f2a93d2e5c54 AS argocd-source
# renovate: datasource=docker depName=gcr.io/go-containerregistry/crane versioning=docker
FROM harbor.alexlebens.dev/proxy-gcr.io/go-containerregistry/crane:v0.22.1@sha256:1f968817b95790bed063f71175aa6b8ff879fa17064020415f3e18bb6e6a36e1 AS crane-source
# renovate: datasource=docker depName=quay.io/helmpack/chart-testing versioning=docker
FROM harbor.alexlebens.dev/proxy-quay.io/helmpack/chart-testing:v3.15.0@sha256:54317f2d93730ea9ca1236e3d79cd95d74110b8d733b6ab124e5829209b5f4e4 AS ct-source
# renovate: datasource=docker depName=alpine/helm versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/alpine/helm:4.3.1@sha256:e3f8d5c462d75470fbb1fce79ad5c20063657096d1f98c0fcea869e2600e2e5e AS helm-source
# renovate: datasource=docker depName=ghcr.io/yannh/kubeconform versioning=docker
FROM harbor.alexlebens.dev/proxy-ghcr.io/yannh/kubeconform:v0.8.0@sha256:faffaf43f95aa6425306e1ab8d6fcad72acb9049158f38e574c085ea1ec0f64e AS kubeconform-source
# renovate: datasource=docker depName=registry.k8s.io/kubectl versioning=docker
FROM harbor.alexlebens.dev/proxy-registry.k8s/kubectl:v1.37.2@sha256:fe049faa65ae483ac200009a949a68fa4c9985daea12c9cb1195c9c7965301fc AS kubectl-source
# renovate: datasource=docker depName=ghcr.io/opentofu/opentofu versioning=docker
FROM harbor.alexlebens.dev/proxy-ghcr.io/opentofu/opentofu:1.13.8-minimal@sha256:f4ef496a61579469a1afe5bd355d15fe1c01dbbe9c4e91a7ee1695c973393ead AS tofu-source
# renovate: datasource=docker depName=aquasec/trivy versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c AS trivy-source

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
  # Baked-in tools resolve directly from /usr/local/bin; repo-specific tools auto-install into /cache/mise
  MISE_DISABLE_TOOLS="actionlint,argocd,bats,bun,crane,ct,helm,jq,kubeconform,kubectl,lychee,opentofu,python,ruff,shellcheck,trivy,uv,yq" \
  # --- uv (persisted on runner /cache/uv mount) ---
  UV_CACHE_DIR="/root/.cache/uv" \
  UV_LINK_MODE="copy" \
  UV_PYTHON_INSTALL_DIR="/opt/python" \
  UV_PYTHON_BIN_DIR="/usr/local/bin" \
  UV_PYTHON_DOWNLOADS="automatic" \
  UV_TOOL_BIN_DIR="/usr/local/bin" \
  UV_TOOL_DIR="/opt/uv-tools" \
  # --- Bun (persisted on runner /cache/bun mount) ---
  BUN_INSTALL_CACHE_DIR="/root/.bun/install/cache" \
  # --- Trivy ---
  TRIVY_CACHE_DIR="/opt/trivy-cache" \
  TRIVY_DB_REPOSITORY="harbor.alexlebens.dev/proxy-ghcr.io/aquasecurity/trivy-db:2" \
  TRIVY_JAVA_DB_REPOSITORY="harbor.alexlebens.dev/proxy-ghcr.io/aquasecurity/trivy-java-db:1" \
  # Include /opt/bats/bin directly in PATH to avoid needing a post-COPY symlink RUN step
  PATH="/root/.local/share/mise/shims:/root/.local/bin:/opt/bats/bin:${PATH}"

# 1. Copy uv first and execute Python layer BEFORE all other COPY --link layers.
# Updating any other CLI tool below will no longer invalidate this Python build step.
COPY --link --from=uv-source /uv /uvx /usr/local/bin/

# renovate: datasource=github-releases depName=python/cpython versioning=semver
ENV PYTHON_VERSION="3.15.2"
RUN --mount=type=cache,target=/root/.cache/uv \
  set -eu; \
  uv python install "${PYTHON_VERSION}" --default --preview-features python-install-default --force; \
  uv tool install --python /usr/local/bin/python3 pytest --with pyyaml; \
  uv tool install --python /usr/local/bin/python3 yamllint; \
  uv tool install --python /usr/local/bin/python3 yamale; \
  uv pip install --python /usr/local/bin/python3 --break-system-packages pyyaml; \
  uv pip install --python /usr/bin/python3 --break-system-packages pyyaml; \
  curl -sSfL "https://raw.githubusercontent.com/yannh/kubeconform/v0.8.0/scripts/openapi2jsonschema.py" \
  -o /usr/local/bin/openapi2jsonschema.py; \
  chmod +x /usr/local/bin/openapi2jsonschema.py

# 2. Independent COPY --link layers (updating any single tool never invalidates the others)
COPY --link --from=mise-source /usr/local/bin/mise /usr/local/bin/mise
COPY --link --from=bun-source /usr/local/bin/bun /usr/local/bin/bunx /usr/local/bin/

COPY --link --from=actionlint-source /usr/local/bin/actionlint /usr/local/bin/actionlint
COPY --link --from=bats-source /opt/bats /opt/bats
COPY --link --from=jq-source /jq /usr/local/bin/jq
COPY --link --from=lychee-source /usr/local/bin/lychee /usr/local/bin/lychee
COPY --link --from=ruff-source /usr/local/bin/ruff /usr/local/bin/ruff
COPY --link --from=shellcheck-source /bin/shellcheck /usr/local/bin/shellcheck
COPY --link --from=yq-source /usr/bin/yq /usr/local/bin/yq

COPY --link --from=argocd-source /usr/local/bin/argocd /usr/local/bin/argocd
COPY --link --from=crane-source /ko-app/crane /usr/local/bin/crane
COPY --link --from=ct-source /usr/local/bin/ct /usr/local/bin/ct
COPY --link --from=ct-source /etc/ct /etc/ct
COPY --link --from=helm-source /usr/bin/helm /usr/local/bin/helm
COPY --link --from=kubeconform-source /kubeconform /usr/local/bin/kubeconform
COPY --link --from=kubectl-source /bin/kubectl /usr/local/bin/kubectl
COPY --link --from=tofu-source /usr/local/bin/tofu /usr/local/bin/tofu
COPY --link --from=trivy-source /usr/local/bin/trivy /usr/local/bin/trivy

# 3. Verify all baked-in tools using a bind mount (zero extra image layers created)
RUN --mount=type=bind,source=verify-tools.sh,target=/tmp/verify-tools.sh \
  bash /tmp/verify-tools.sh

# 4. Refresh Trivy Vulnerability & Java DBs on every build without recursive chmod overhead
ARG CACHE_BUST=1
RUN mkdir -p "${TRIVY_CACHE_DIR}" \
  && trivy image --download-db-only \
  && trivy image --download-java-db-only
