# =========================================================================
# Tool versions: single source of truth is the repo-root mise.toml.
# CI generates these with `images/runner/build-args.sh mise.toml`.
# Deliberately no defaults: a missing build-arg yields an invalid FROM and fails fast.
# =========================================================================
ARG ARGOCD_VERSION
ARG BATS_VERSION
ARG CRANE_VERSION
ARG HELM_VERSION
ARG JQ_VERSION
ARG KUBECONFORM_VERSION
ARG KUBECTL_VERSION
ARG OPENTOFU_VERSION
ARG RUFF_VERSION
ARG SHELLCHECK_VERSION
ARG TRIVY_VERSION
ARG UV_VERSION
ARG YQ_VERSION

# =========================================================================
# Tool sources using passed args
# =========================================================================

# renovate: datasource=docker depName=jdxcode/mise versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/jdxcode/mise:2026.10.25@sha256:91417f41840316b7c5da6854bef393eccea4546ae70f8baf0803e0e94287b68d AS mise-source

FROM harbor.alexlebens.dev/proxy-ghcr.io/astral-sh/uv:${UV_VERSION} AS uv-source
FROM harbor.alexlebens.dev/proxy-ghcr.io/astral-sh/ruff:${RUFF_VERSION}-debian AS ruff-source
FROM harbor.alexlebens.dev/proxy-gcr.io/go-containerregistry/crane:v${CRANE_VERSION} AS crane-source
FROM harbor.alexlebens.dev/proxy-hub.docker/alpine/helm:${HELM_VERSION} AS helm-source
FROM harbor.alexlebens.dev/proxy-registry.k8s/kubectl:v${KUBECTL_VERSION} AS kubectl-source
FROM harbor.alexlebens.dev/proxy-ghcr.io/opentofu/opentofu:${OPENTOFU_VERSION}-minimal AS tofu-source
FROM harbor.alexlebens.dev/proxy-ghcr.io/yannh/kubeconform:v${KUBECONFORM_VERSION} AS kubeconform-source
FROM harbor.alexlebens.dev/proxy-hub.docker/aquasec/trivy:${TRIVY_VERSION} AS trivy-source
FROM harbor.alexlebens.dev/proxy-quay.io/argoproj/argocd:v${ARGOCD_VERSION} AS argocd-source

# =========================================================================
# Tools with no official image: installed by mise, one stage each for caching
# =========================================================================
FROM mise-source AS jq-source
ARG JQ_VERSION
ENV MISE_DATA_DIR=/mise MISE_YES=1
RUN mise install "jq@${JQ_VERSION}"

FROM mise-source AS yq-source
ARG YQ_VERSION
ENV MISE_DATA_DIR=/mise MISE_YES=1
RUN mise install "yq@${YQ_VERSION}"

FROM mise-source AS shellcheck-source
ARG SHELLCHECK_VERSION
ENV MISE_DATA_DIR=/mise MISE_YES=1
RUN mise install "shellcheck@${SHELLCHECK_VERSION}"

FROM mise-source AS bats-source
ARG BATS_VERSION
ENV MISE_DATA_DIR=/mise MISE_YES=1
RUN mise install "bats@${BATS_VERSION}"

# =========================================================================
# Gitea Runner Image
# =========================================================================

# renovate: datasource=docker depName=gitea/runner-images versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/gitea/runner-images:ubuntu-26.04@sha256:a71bcbfef0157f767c84efc3dcbc9dc56c249db320b627ed2b802dc867337458

ENV DEBIAN_FRONTEND=noninteractive \
  # Ensure repo-level .mise.toml files work seamlessly inside Gitea Actions steps
  MISE_DATA_DIR="/mise" \
  MISE_CONFIG_DIR="/mise" \
  MISE_YES="1" \
  MISE_TRUSTED_CONFIG_PATHS="/workspace" \
  # Tools are baked in; never let repo mise.toml trigger a second download at CI time
  MISE_TASK_RUN_AUTO_INSTALL="false" \
  MISE_EXEC_AUTO_INSTALL="false" \
  UV_TOOL_BIN_DIR="/usr/local/bin" \
  PATH="/mise/shims:${PATH}"

# Use COPY --link so updating one tool doesn't invalidate the layer cache of the others
COPY --link --from=uv-source /uv /uvx /usr/local/bin/
COPY --link --from=helm-source /usr/bin/helm /usr/local/bin/helm
COPY --link --from=kubectl-source /bin/kubectl /usr/local/bin/kubectl
COPY --link --from=tofu-source /usr/local/bin/tofu /usr/local/bin/tofu
COPY --link --from=kubeconform-source /kubeconform /usr/local/bin/kubeconform
COPY --link --from=trivy-source /usr/local/bin/trivy /usr/local/bin/trivy
COPY --link --from=crane-source /ko-app/crane /usr/local/bin/crane
COPY --link --from=argocd-source /usr/local/bin/argocd /usr/local/bin/argocd
COPY --link --from=mise-source /usr/local/bin/mise /usr/local/bin/mise
COPY --link --from=ruff-source /usr/local/bin/ruff /usr/local/bin/ruff

# mise-installed tools (jq, yq, shellcheck, bats) keep mise's install layout
COPY --link --from=jq-source /mise/installs/jq /mise/installs/jq
COPY --link --from=yq-source /mise/installs/yq /mise/installs/yq
COPY --link --from=shellcheck-source /mise/installs/shellcheck /mise/installs/shellcheck
COPY --link --from=bats-source /mise/installs/bats /mise/installs/bats
# Link into /usr/local/bin instead of using mise shims: shims fail with "No version is set"
# outside a directory whose mise config lists the tool, and would shadow any base-image copy.
RUN set -eu; \
  for t in jq yq shellcheck bats; do \
    bin="$(find "/mise/installs/$t" -type f -perm -u+x -name "$t" | head -n1)"; \
    [ -n "$bin" ] || { echo "no $t binary found in /mise/installs/$t" >&2; exit 1; }; \
    ln -sf "$bin" "/usr/local/bin/$t"; \
  done

# -------------------------------------------------------------------------
# Runner-only tooling (used by Gitea scripts, not part of mise.toml)
# -------------------------------------------------------------------------

# Install pytest + pyyaml cleanly via uv instead of outdated apt packages
RUN uv tool install pytest --with pyyaml && rm -rf /root/.cache/uv

# Enforce strict 1:1 with mise.toml (tiny layer; re-runs only when mise.toml or the script changes)
COPY --from=repo mise.toml /tmp/mise.toml
COPY verify-tools.sh /tmp/verify-tools.sh
RUN bash /tmp/verify-tools.sh /tmp/mise.toml && rm -f /tmp/mise.toml /tmp/verify-tools.sh

# Set a global, user-agnostic cache directory for Trivy
ENV TRIVY_CACHE_DIR="/opt/trivy-cache" \
  TRIVY_DB_REPOSITORY="harbor.alexlebens.dev/proxy-ghcr.io/aquasecurity/trivy-db:2" \
  TRIVY_JAVA_DB_REPOSITORY="harbor.alexlebens.dev/proxy-ghcr.io/aquasecurity/trivy-java-db:1"

# Changing CACHE_BUST invalidates only this final layer so the DB refreshes on every build
ARG CACHE_BUST=1
RUN mkdir -p "${TRIVY_CACHE_DIR}" \
  && trivy image --download-db-only \
  && chmod -R 777 "${TRIVY_CACHE_DIR}"
