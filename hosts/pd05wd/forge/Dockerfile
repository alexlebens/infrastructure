FROM pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy

WORKDIR /workspace

# Install system dependencies (git, ffmpeg for Wan 2.2 video generation, libgl for OpenCV)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv package manager
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Create non-root user
RUN useradd -m -u 1000 -s /bin/bash forge && \
    mkdir -p /workspace/forge && \
    chown -R forge:forge /workspace

USER forge

# Clone SD-WebUI Forge Classic (Neo fork by Haoming02)
RUN git clone https://github.com/Haoming02/sd-webui-forge-classic.git /workspace/forge

WORKDIR /workspace/forge

EXPOSE 7860

# Launch Forge with API enabled and uv for rapid package installations
CMD ["python", "launch.py", "--listen", "--port", "7860", "--api", "--enable-insecure-extension-access", "--uv"]
