FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Build arguments for UID, GID, and versions
ARG PUID=1025
ARG PGID=1025
ARG COSMOVISOR_VERSION=v1.6.0
ARG POCKETD_VERSION=v0.1.26

# Set persistent environment variables
ENV POCKET_USER=pocket
ENV DAEMON_NAME=pocketd
ENV DAEMON_HOME=/home/pocket/.pocket
ENV COSMOVISOR_VERSION=${COSMOVISOR_VERSION}
ENV POCKETD_VERSION=${POCKETD_VERSION}
ENV HOME=/home/pocket
ENV PATH="/home/pocket/.local/bin:/usr/local/cosmovisor/current/bin:$PATH"

# Install packages and create pocket user
RUN apt-get update && apt-get install -y \
    curl wget jq tar zstd aria2 vim sudo ca-certificates bash git && \
    groupadd -g ${PGID} ${POCKET_USER} && \
    useradd -u ${PUID} -g ${PGID} -m -s /bin/bash ${POCKET_USER} && \
    mkdir -p /usr/local/cosmovisor /home/${POCKET_USER}/.local/bin && \
    rm -rf /var/lib/apt/lists/*

# Download and install cosmovisor and pocketd
RUN set -e && \
    ARCH=$(uname -m) && \
    [ "$ARCH" = "x86_64" ] && ARCH="amd64" || ARCH="arm64" && \
    curl -sL "https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2F${COSMOVISOR_VERSION}/cosmovisor-${COSMOVISOR_VERSION}-linux-${ARCH}.tar.gz" \
      | tar -zx -C /usr/local/bin && \
    mkdir -p /usr/local/cosmovisor/genesis/bin && \
    curl -sL "https://github.com/pokt-network/poktroll/releases/download/${POCKETD_VERSION}/pocket_linux_${ARCH}.tar.gz" \
      | tar -zx -C /usr/local/cosmovisor/genesis/bin && \
    chmod +x /usr/local/cosmovisor/genesis/bin/pocketd && \
    ln -sf /usr/local/cosmovisor/current/bin/pocketd /usr/local/bin/pocketd

# Set permissions on directories
RUN chown -R ${POCKET_USER}:${POCKET_USER} /home/${POCKET_USER} /usr/local/cosmovisor

# Copy in scripts and make them executable
COPY --chown=${POCKET_USER}:${POCKET_USER} scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Use non-root user for execution
USER ${POCKET_USER}
WORKDIR /home/${POCKET_USER}

# Expose Pocket node ports
EXPOSE 9090 1317 26656 26657 26660

# Entrypoint script to initialize and start the Pocket node using Cosmovisor
CMD ["bash", "/scripts/entrypoint.sh"]
