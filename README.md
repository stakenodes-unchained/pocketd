# Pocket Node Docker Setup

## 📚 Table of Contents

- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Hardware Requirements](#hardware-requirements)
- [Environment Variables](#environment-variables)
  - [Required Runtime Environment Variables](#required-runtime-environment-variables)
- [Scripts](#scripts)
- [Notes](#notes)
- [Quick Start](#quick-start)
- [Advanced Configuration](#advanced-configuration)
  - [`app.toml`](#apptoml)
  - [`client.toml`](#clienttoml)
  - [`config.toml`](#configtoml)
- [Pro Tip: Editing Configs Without Stopping the Node](#pro-tip-editing-configs-without-stopping-the-node)
- [🛰️ RelayMiner Setup Guide](#️-relayminer-setup-guide)
  - [1. Prepare Your Supplier Stake File](#1-prepare-your-supplier-stake-file)
  - [2. Prepare the RelayMiner Config File](#2-prepare-the-relayminer-config-file)
  - [3. Enable RelayMiner](#3-enable-relayminer)
  - [4. Countdown for Keyring and Config File](#4-countdown-for-keyring-and-config-file)
  - [5. Key Passphrase Setup](#5-key-passphrase-setup)
- [License](#license)

<p align="center">
  <img alt="Docker" src="https://img.shields.io/badge/Built%20with-Docker-blue?logo=docker" />
  <img alt="Platform" src="https://img.shields.io/badge/Platform-Linux-yellow?logo=linux" />
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green" />
  <img alt="Cosmovisor" src="https://img.shields.io/badge/Managed%20by-Cosmovisor-lightgrey" />
</p>

This project provides a streamlined Dockerized setup for running a Pocket Network node using Cosmovisor.  
It automates image building, initialization, snapshot restoration, and node startup to simplify deployment and management.

## Features

- 🛠 **Automated Environment Initialization**: Prepares the node environment and restores from a blockchain snapshot.
- 🚀 **Cosmovisor Integration**: Handles binary upgrades and runtime management using Cosmovisor.
- 📦 **Dockerized Deployment**: All node services are containerized for consistent and reproducible setups.
- ⚡ **Fast Sync**: Bootstraps from verified snapshots for rapid node synchronization.
- 🖥 **Customizable Configurations**: Environment variables allow flexible adjustments without modifying scripts.

## Project Structure

| File | Description |
|:-----|:------------|
| `Dockerfile` | Builds the Pocket Node container image with required environment variables. |
| `docker-compose.yml` | Defines and orchestrates the services needed to run the node. |
| `init-pocket-node.sh` | Initializes the node and restores the latest snapshot for fast sync (automatically called by `start-node.sh`). |
| `start-node.sh` | Validates environment and launches the node using Cosmovisor. |

## Prerequisites

- [Docker Engine Installation Guide](https://docs.docker.com/engine/install/)
- [Docker Compose Installation Guide](https://docs.docker.com/compose/install/)
- Familiarity with [Pocket Network Shannon Documentation](https://dev.poktroll.com/)

## Hardware Requirements

Refer to [Pocket Network Hardware Requirements](https://dev.poktroll.com/operate/configs/hardware_requirements?_highlight=hardw).

| Component | Minimum | Recommended |
|:----------|:--------|:------------|
| (v)CPU Cores | 4 | 6 |
| RAM | 16GB | 32GB |
| SSD Storage | 200GB | 420GB |

## Environment Variables

The following variables are set inside the Dockerfile to configure the node:

| Variable | Purpose | Default |
|:---------|:--------|:--------|
| `POCKET_USER` | Linux user running the node inside the container | `pocket` |
| `DAEMON_NAME` | Daemon executable name | `pocketd` |
| `DAEMON_HOME` | Path to the node's home directory | `/home/pocket/.pocket` |
| `DAEMON_RESTART_AFTER_UPGRADE` | Auto-restart after upgrade | `true` |
| `DAEMON_ALLOW_DOWNLOAD_BINARIES` | Allow Cosmovisor to download binaries | `true` |
| `UNSAFE_SKIP_BACKUP` | Skip backup (only for dev/test) | `true` |
| `COSMOVISOR_VERSION` | Version of Cosmovisor to install | `v1.6.0` |
| `POCKETD_VERSION` | Version of Pocket Daemon to install | `v0.1.6` |

### Required Runtime Environment Variables

Before starting the node, ensure the following environment variables are set either through your `docker-compose.yml`

| Variable         | Description                                                                 | Example Values             |
|:----------------|:----------------------------------------------------------------------------|:---------------------------|
| `NETWORK`        | Defines the target Pocket Network environment.                              | `testnet-alpha`, `testnet-beta`, `mainnet` |
| `EXTERNAL_IP`    | The external IP address of the server running the node.                     | `192.0.2.1`                |
| `NODE_MONIKER`   | Human-readable name for your node (for identification in network explorers).| `my-pocket-node`          |
| `USE_SNAPSHOT`   | Enables syncing from a snapshot instead of genesis.                         | `true`, `false` (default: `true`) |
| `RESNAPSHOT`     | Forces snapshot re-download even if data exists (preserves priv key state). | `true`, `false` (default: `false`) |
| `SNAPSHOT_TYPE`  | Specifies the snapshot type to use.                                          | `archival`, `pruned` (default: `archival`) |

### 💡 Tips

- Use `RESNAPSHOT=true` if your node becomes corrupted or stuck and you want to **force a fresh state sync** using the latest snapshot. Your `priv_validator_state.json` will be preserved to retain node identity.
- Set `SNAPSHOT_TYPE=pruned` if you want to **reduce storage usage** by skipping historical data. This is suitable for nodes that do not require archival state (e.g., most relay nodes).

## Scripts

| Script | Purpose |
|:-------|:--------|
| `init-pocket-node.sh` | Prepares the node and downloads the latest snapshot. Called automatically by `start-node.sh`. |
| `start-node.sh` | Validates environment variables and starts the node with Cosmovisor. |

## Notes

- Ensure that your `EXTERNAL_IP` environment variable is properly set if operating across public networks.
- Snapshot source URLs should be verified for integrity and authenticity.
- For production environments, consider hardening container security and tuning resource limits.

## Quick Start

1. **(Optional but recommended) Open firewall for P2P traffic:**
   ```bash
   sudo ufw allow 26656/tcp
   sudo ufw reload
   ```
> 📣 Make sure UFW (or your cloud provider firewall) allows external P2P connections.

2. **Clone the repository**:
   ```bash
   git clone https://github.com/stakenodes-unchained/pocketd.git
   cd pocketd
   ```
3. **Set the REQUIRED runtime environment variables in the docker-compose.yml file**
   ```bash
   vi docker-compose.yml
   ```
4. **Build the Docker Image**:
   ```bash
   docker compose build
   ```

5. **Start the Node**:
   ```bash
   docker compose up -d
   ```

6. **Monitor Logs**:
   ```bash
   docker compose logs -f pocketd
   ```

The node will automatically initialize (including downloading and restoring the latest snapshot) and start syncing once the container is running.

## Advanced Configuration

To further optimize and configure your Pocket Node, update the following settings inside your node's configuration files:

### `app.toml`
| Setting | Section | Value |
|:--------|:--------|:------|
| `pruning` | root | `"nothing"` |
| `minimum-gas-prices` | root | `"1upokt"` |
| `enable` | `[api]` | `true` |
| `address` | `[api]` | `"tcp://0.0.0.0:1317"` |
| `enabled-unsafe-cors` | `[api]` | `true` |
| `address` | `[grpc]` | `"0.0.0.0:9090"` |
| `max-recv-msg-size` | `[grpc]` | `"10485760"` |
| `max-txs` | `[mempool]` | `10000` |
| `cardinality-level` | `[pocket]` | `"high"` |

### `client.toml`
| Setting | Section | Value |
|:--------|:--------|:------|
| `keyring-backend` | root | `"test"` |

### `config.toml`
| Setting | Section | Value |
|:--------|:--------|:------|
| `laddr` | `[rpc]` | `"tcp://0.0.0.0:26657"` |
| `cors_allowed_origins` | `[rpc]` | `["*", ]` |

After making these changes inside the container or mounted volumes:

1. **Stop the running container**:
   ```bash
   docker compose down
   ```

2. **Restart the node**:
   ```bash
   docker compose up -d
   ```

This ensures that your new configuration settings are applied properly.

## Pro Tip: Editing Configs Without Stopping the Node

If you need to make quick adjustments to configuration files without bringing the node down, you can connect directly to the running container:

```bash
docker exec -it pocket-node bash
```

Once inside:

1. Navigate to the configuration directory:
   ```bash
   cd /home/pocket/.pocket/config
   ```

2. Edit the necessary files (`app.toml`, `client.toml`, `config.toml`) using a text editor like `vi` or `nano` (if installed).

3. After making changes, gracefully restart the container:
   ```bash
   docker compose restart pocketd
   ```

> ⚡ Note: Some changes (especially network binding changes) may still require a full `docker compose down && up -d` restart.

## 🛰️ RelayMiner Setup Guide

RelayMiner is **disabled by default** to support node operators who may not need it. If you intend to run RelayMiner, you must explicitly enable it and follow the steps below to ensure a successful launch.

### 1. Prepare Your Supplier Stake File

RelayMiner requires an active supplier stake to function.

- A sample `supplier-stake.yaml` is available in the `templates/` directory.
- Modify the values to suit your setup.
- Copy the file into the Pocket node container using:
  ```bash
  docker cp supplier-stake.yaml pocketd-node:/tmp/supplier-stake.yaml
  ```

### 2. Prepare the RelayMiner Config File

- Modify the sample `relayminer-config.yaml` found in the `templates/` directory.
- This file includes important parameters such as service IDs, backend RPC URLs, and signing key names.

> 🛠️ **It’s highly recommended you prepare this file before enabling RelayMiner**, as the container will enter a limited wait loop at startup expecting the file to exist.

### 3. Enable RelayMiner

To activate the service:

- In your `docker-compose.yml`, set:
  ```yaml
  ENABLE_RELAYMINER=true
  ```
- If the container previously started with `false`, remove it and start it again:
  ```bash
  docker compose rm relayminer
  docker compose up -d relayminer
  ```

### 4. Countdown for Keyring and Config File

Once RelayMiner starts with `ENABLE_RELAYMINER=true`, the following validations occur:

- ⏳ **Keyring Check:**  
  The container waits up to **5 minutes** (5 attempts, 60s intervals) for keys to exist in the `keyring-file` directory.  
  You can enter the container and add keys manually:
  ```bash
  docker exec -it relayminer sh
  pocketd keys add <key_name>
  pocketd keys add <key_name> --recover
  ```

- 📄 **Config File Check:**  
  RelayMiner also waits up to **5 minutes** (5 attempts, 60s intervals) for `relayminer-config.yaml` to appear at:  
  `/home/pocket/.pocket/relayminer-config.yaml`

If either of these is missing or empty after their respective countdowns, the container will terminate with an error.

### 5. Key Passphrase Setup

Make sure `POCKET_KEYRING_PASSPHRASE` is set in the environment for non-interactive unlocking of your key during container startup.


## License

MIT License © 2025 Unchained Nodes LLC
