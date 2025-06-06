FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Set UID/GID explicitly for reproducibility
ARG PUID=1025
ARG PGID=1025

# Environment setup
ENV POCKET_USER=pocket \
    DAEMON_NAME=pocketd \
    DAEMON_HOME=/home/pocket/.pocket \
    DAEMON_RESTART_AFTER_UPGRADE=true \
    DAEMON_ALLOW_DOWNLOAD_BINARIES=true \
    UNSAFE_SKIP_BACKUP=true \
    COSMOVISOR_VERSION=v1.6.0 \
    POCKETD_VERSION=v0.1.17 \
    HOME=/home/pocket

# Install dependencies and create user
RUN apt-get update && apt-get install -y \
    curl wget jq tar zstd aria2 vim sudo ca-certificates bash git && \
    groupadd -g ${PGID} ${POCKET_USER} && \
    useradd -u ${PUID} -g ${PGID} -m -s /bin/bash ${POCKET_USER} && \
    mkdir -p /home/${POCKET_USER}/.local/bin && \
    chown -R ${POCKET_USER}:${POCKET_USER} /home/${POCKET_USER} && \
    rm -rf /var/lib/apt/lists/*

# Switch to non-root user
USER ${POCKET_USER}
WORKDIR /home/${POCKET_USER}

# Set path
ENV PATH="/home/${POCKET_USER}/.local/bin:${DAEMON_HOME}/cosmovisor/current/bin:$PATH"

# Download binaries only (no init or genesis)
RUN set -e && \
    ARCH=$(uname -m) && \
    [ "$ARCH" = "x86_64" ] && ARCH="amd64" || ARCH="arm64" && \
    mkdir -p ${DAEMON_HOME}/cosmovisor/genesis/bin && \
    curl -sL "https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2F${COSMOVISOR_VERSION}/cosmovisor-${COSMOVISOR_VERSION}-linux-${ARCH}.tar.gz" \
      | tar -zx -C /home/${POCKET_USER}/.local/bin && \
    curl -sL "https://github.com/pokt-network/poktroll/releases/download/${POCKETD_VERSION}/pocket_linux_${ARCH}.tar.gz" \
      | tar -zx -C ${DAEMON_HOME}/cosmovisor/genesis/bin && \
    chmod +x ${DAEMON_HOME}/cosmovisor/genesis/bin/pocketd && \
    ln -sf ${DAEMON_HOME}/cosmovisor/genesis ${DAEMON_HOME}/cosmovisor/current && \
    ln -sf ${DAEMON_HOME}/cosmovisor/current/bin/pocketd /home/${POCKET_USER}/.local/bin/pocketd

# Copy all scripts in the container
COPY --chown=${POCKET_USER}:${POCKET_USER} scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Expose ports
EXPOSE 9090 1317 26656 26657 26660
