# =========================================================================
# Official Upstream Tool Sources
# Standalone CLI tools used across Gitea workflows
# =========================================================================
# renovate: datasource=docker depName=mikefarah/yq versioning=semver
FROM harbor.alexlebens.dev/proxy-hub.docker/mikefarah/yq:4.54.1@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e AS yq-source

# renovate: datasource=docker depName=ghcr.io/astral-sh/uv versioning=semver
FROM harbor.alexlebens.dev/proxy-ghcr.io/astral-sh/uv:0.13.6@sha256:af22a52f5eafef3d78e551599d405c02df61919d18028f0cea8eda93bc9986d0 AS uv-source

# renovate: datasource=docker depName=alpine/helm versioning=semver
FROM harbor.alexlebens.dev/proxy-hub.docker/alpine/helm:4.3.1@sha256:e3f8d5c462d75470fbb1fce79ad5c20063657096d1f98c0fcea869e2600e2e5e AS helm-source

# renovate: datasource=docker depName=registry.k8s.io/kubectl versioning=semver
FROM harbor.alexlebens.dev/proxy-gcr.io/kubectl:v1.37.2@sha256:fe049faa65ae483ac200009a949a68fa4c9985daea12c9cb1195c9c7965301fc AS kubectl-source

# renovate: datasource=docker depName=ghcr.io/opentofu/opentofu versioning=semver
FROM harbor.alexlebens.dev/proxy-ghcr.io/opentofu/opentofu:1.13.5@sha256:5e6046cd8d1e2db82ce71fb56fe0a535b489b5493cfa0d5889ad5cffd2625ab6 AS tofu-source

# renovate: datasource=docker depName=ghcr.io/yannh/kubeconform versioning=semver
FROM harbor.alexlebens.dev/proxy-ghcr.io/yannh/kubeconform:v0.8.0@sha256:faffaf43f95aa6425306e1ab8d6fcad72acb9049158f38e574c085ea1ec0f64e AS kubeconform-source

# renovate: datasource=docker depName=aquasec/trivy versioning=semver
FROM harbor.alexlebens.dev/proxy-hub.docker/aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c AS trivy-source

# renovate: datasource=docker depName=gcr.io/go-containerregistry/crane versioning=semver
FROM harbor.alexlebens.dev/proxy-gcr.io/go-containerregistry/crane:v0.22.1@sha256:1f968817b95790bed063f71175aa6b8ff879fa17064020415f3e18bb6e6a36e1 AS crane-source

# =========================================================================
# Gitea Runner Image
# =========================================================================
# renovate: datasource=docker depName=ghcr.io/catthehacker/ubuntu versioning=docker
FROM harbor.alexlebens.dev/proxy-ghcr.io/catthehacker/ubuntu:act-24.04@sha256:62d572b92f9f32d3427b6d220ad1f9dca9c7b6ffad37d295425037dbff78abaf

ENV DEBIAN_FRONTEND=noninteractive

# Install system utilities needed by workflow lint/test scripts
RUN apt-get update && apt-get install -y --no-install-recommends \
  shellcheck \
  && rm -rf /var/lib/apt/lists/*

# Copy standalone workflow CLI binaries directly from upstream images
COPY --from=yq-source /usr/bin/yq /usr/local/bin/yq
COPY --from=uv-source /uv /uvx /usr/local/bin/
COPY --from=helm-source /usr/bin/helm /usr/local/bin/helm
COPY --from=kubectl-source /bin/kubectl /usr/local/bin/kubectl
COPY --from=tofu-source /usr/local/bin/tofu /usr/local/bin/tofu
COPY --from=kubeconform-source /kubeconform /usr/local/bin/kubeconform
COPY --from=trivy-source /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=crane-source /ko-app/crane /usr/local/bin/crane
