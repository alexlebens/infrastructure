# =========================================================================
# Official Upstream Tool Sources
# Standalone CLI tools used across Gitea workflows
# =========================================================================

# renovate: datasource=docker depName=jdxcode/mise versioning=docker
FROM harbor.alexlebens.dev/proxy-hub.docker/jdxcode/mise:2026.10.25@sha256:91417f41840316b7c5da6854bef393eccea4546ae70f8baf0803e0e94287b68d AS mise-source

# renovate: datasource=docker depName=ghcr.io/astral-sh/uv versioning=semver
FROM harbor.alexlebens.dev/proxy-ghcr.io/astral-sh/uv:0.13.6@sha256:af22a52f5eafef3d78e551599d405c02df61919d18028f0cea8eda93bc9986d0 AS uv-source

# renovate: datasource=docker depName=ghcr.io/astral-sh/ruff versioning=semver
FROM harbor.alexlebens.dev/proxy-ghcr.io/astral-sh/ruff:0.17.3-debian@sha256:e7311317f3583bd199ee6eace2a3ab08797271c9c1c26912e5fdeb3bb94305eb AS ruff-source

# renovate: datasource=docker depName=gcr.io/go-containerregistry/crane versioning=semver
FROM harbor.alexlebens.dev/proxy-gcr.io/go-containerregistry/crane:v0.22.1@sha256:1f968817b95790bed063f71175aa6b8ff879fa17064020415f3e18bb6e6a36e1 AS crane-source

# renovate: datasource=docker depName=alpine/helm versioning=semver
FROM harbor.alexlebens.dev/proxy-hub.docker/alpine/helm:4.3.1@sha256:e3f8d5c462d75470fbb1fce79ad5c20063657096d1f98c0fcea869e2600e2e5e AS helm-source

# renovate: datasource=docker depName=registry.k8s.io/kubectl versioning=semver
FROM harbor.alexlebens.dev/proxy-registry.k8s/kubectl:v1.37.2@sha256:fe049faa65ae483ac200009a949a68fa4c9985daea12c9cb1195c9c7965301fc AS kubectl-source

# renovate: datasource=docker depName=ghcr.io/opentofu/opentofu versioning=semver
FROM harbor.alexlebens.dev/proxy-ghcr.io/opentofu/opentofu:1.13.5@sha256:5e6046cd8d1e2db82ce71fb56fe0a535b489b5493cfa0d5889ad5cffd2625ab6 AS tofu-source

# renovate: datasource=docker depName=ghcr.io/yannh/kubeconform versioning=semver
FROM harbor.alexlebens.dev/proxy-ghcr.io/yannh/kubeconform:v0.8.0@sha256:faffaf43f95aa6425306e1ab8d6fcad72acb9049158f38e574c085ea1ec0f64e AS kubeconform-source

# renovate: datasource=docker depName=aquasec/trivy versioning=semver
FROM harbor.alexlebens.dev/proxy-hub.docker/aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c AS trivy-source

# renovate: datasource=docker depName=quay.io/argoproj/argocd versioning=semver
FROM harbor.alexlebens.dev/proxy-quay.io/argoproj/argocd:v3.5.7@sha256:16df57da6f223808d204cd94c67c929b931fa01670b91b0b3a2298c4647de0db AS argocd-source

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
  UV_TOOL_BIN_DIR="/usr/local/bin" \
  PATH="/mise/shims:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
  bats \
  shellcheck \
  && rm -rf /var/lib/apt/lists/*

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

# Copy tofu directly from iamge
# renovate: datasource=docker depName=ghcr.io/opentofu/opentofu versioning=semver
COPY --link --from=harbor.alexlebens.dev/proxy-ghcr.io/opentofu/opentofu:1.13.5@sha256:5e6046cd8d1e2db82ce71fb56fe0a535b489b5493cfa0d5889ad5cffd2625ab6 /usr/local/bin/tofu /usr/local/bin/tofu

# Install pytest + pyyaml cleanly via uv instead of outdated apt packages
RUN uv tool install pytest --with pyyaml && rm -rf /root/.cache/uv

# Set a global, user-agnostic cache directory for Trivy
ENV TRIVY_CACHE_DIR="/opt/trivy-cache" \
  TRIVY_DB_REPOSITORY="harbor.alexlebens.dev/proxy-ghcr.io/aquasecurity/trivy-db:2" \
  TRIVY_JAVA_DB_REPOSITORY="harbor.alexlebens.dev/proxy-ghcr.io/aquasecurity/trivy-java-db:1"

# Changing CACHE_BUST invalidates only this final layer so the DB refreshes on every build
ARG CACHE_BUST=1
RUN mkdir -p "${TRIVY_CACHE_DIR}" \
  && trivy image --download-db-only \
  && chmod -R 777 "${TRIVY_CACHE_DIR}"
