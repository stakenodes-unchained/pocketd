#!/bin/bash
set -e

# 🎨 Terminal color codes
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD_RED="${BOLD}${RED}"
BOLD_GREEN="${BOLD}${GREEN}"
BOLD_YELLOW="${BOLD}${YELLOW}"
NC='\033[0m'

print_color() {
  echo -e "${1}${2}${NC}"
}

# 🧱 Stage 1: Initialization Info
: "${NETWORK:?Environment variable NETWORK not set.}"
: "${EXTERNAL_IP:?Environment variable EXTERNAL_IP not set.}"
: "${NODE_MONIKER:?Environment variable NODE_MONIKER not set.}"
: "${POCKETD_LOG_LEVEL:?Environment variable POCKETD_LOG_LEVEL not set.}"
: "${USE_SNAPSHOT:?Environment variable USE_SNAPSHOT not set.}"
RESNAPSHOT="${RESNAPSHOT:-false}"
SNAPSHOT_TYPE="${SNAPSHOT_TYPE:-archival}"  # 'archival' or 'pruned'
DAEMON_HOME="${DAEMON_HOME:-/home/pocket/.pocket}"
POCKETD_LOG_LEVEL="${POCKETD_LOG_LEVEL:-info}"

# 📁 Stage 2: Paths
DATA_DIR="$DAEMON_HOME/data"
CONFIG_FILE="$DAEMON_HOME/config/genesis.json"
POCKET_BIN="$DAEMON_HOME/cosmovisor/genesis/bin/pocketd"
PRIV_FILE="priv_validator_state.json"

# 📦 Stage 3: Ensure Binary and Symlink
if [ ! -f "$POCKET_BIN" ]; then
  print_color $BOLD_YELLOW "📦 Copying pocketd binary into volume..."
  mkdir -p "$(dirname "$POCKET_BIN")"
  cp /usr/local/cosmovisor/genesis/bin/pocketd "$POCKET_BIN"
fi

if [ ! -L "$DAEMON_HOME/cosmovisor/current" ] || [ "$(readlink "$DAEMON_HOME/cosmovisor/current")" != "$DAEMON_HOME/cosmovisor/genesis" ]; then
  print_color $BOLD_YELLOW "🔗 Fixing cosmovisor/current symlink..."
  rm -f "$DAEMON_HOME/cosmovisor/current"
  ln -sf "$DAEMON_HOME/cosmovisor/genesis" "$DAEMON_HOME/cosmovisor/current"
fi

# 🚀 Stage 4: Node Initialization
if [ -s "$CONFIG_FILE" ]; then
  print_color $BOLD_YELLOW "⚠️ Node already initialized. Skipping setup."
else
  GENESIS_BRANCH="${POCKET_NETWORK_GENESIS_BRANCH:-master}"
  BASE_URL="https://raw.githubusercontent.com/pokt-network/pocket-network-genesis/${GENESIS_BRANCH}/shannon/$NETWORK"
  GENESIS_URL="$BASE_URL/genesis.json"
  SEEDS_URL="$BASE_URL/seeds"
  GENESIS_FILE="/tmp/genesis.json"

  print_color $BOLD_YELLOW "📥 Downloading genesis file..."
  curl -sSL -o "$GENESIS_FILE" "$GENESIS_URL" || { print_color "$BOLD_RED" "❌ Failed to download genesis."; exit 1; }

  CHAIN_ID=$(jq -r '.chain_id' < "$GENESIS_FILE")
  GENESIS_VERSION=$(jq -r '.app_version' < "$GENESIS_FILE")

  [ -z "$CHAIN_ID" ] && { print_color "$BOLD_RED" "❌ chain_id missing."; exit 1; }
  [ -z "$GENESIS_VERSION" ] && { print_color "$BOLD_RED" "❌ app_version missing."; exit 1; }

  print_color $BOLD_GREEN "🔗 chain_id: $CHAIN_ID"
  print_color $BOLD_GREEN "📦 version: $GENESIS_VERSION"

  SEEDS=$(curl -s "$SEEDS_URL")
  [ -z "$SEEDS" ] && { print_color "$BOLD_RED" "❌ Failed to fetch seeds."; exit 1; }

  "$POCKET_BIN" init "$NODE_MONIKER" --chain-id="$CHAIN_ID" --home="$DAEMON_HOME" >/dev/null 2>&1
  cp "$GENESIS_FILE" "$CONFIG_FILE"

  # 🛠 Stage 4.1: Configuration Tweaks
  sed -i -e 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.000000001upokt"|' $DAEMON_HOME/config/app.toml
  sed -i -e 's|^swagger *=.*|swagger = false|' $DAEMON_HOME/config/app.toml
  sed -i -e 's|^rpc-max-body-bytes *=.*|rpc-max-body-bytes = 1000000|' $DAEMON_HOME/config/app.toml
  sed -i -e 's|^rpc-read-timeout *=.*|rpc-read-timeout = 120|' $DAEMON_HOME/config/app.toml
  sed -i -e 's|^rpc-write-timeout *=.*|rpc-write-timeout = 120|' $DAEMON_HOME/config/app.toml
  sed -i -e 's|^enabled-unsafe-cors *=.*|enabled-unsafe-cors = true|' $DAEMON_HOME/config/app.toml
  sed -i -e 's|^max-recv-msg-size *=.*|max-recv-msg-size = "2147483647"|' $DAEMON_HOME/config/app.toml
  sed -i -e 's|^max-txs *=.*|max-txs = 10000|' $DAEMON_HOME/config/app.toml
  sed -i -e 's|^prometheus-retention-time *=.*|prometheus-retention-time = "1800"|' $DAEMON_HOME/config/app.toml
  echo -e '\n[rpc]\ncors_allowed_origins = ["*"]' >> $DAEMON_HOME/config/app.toml

  sed -i -e "s|^seeds *=.*|seeds = \"$SEEDS\"|" $DAEMON_HOME/config/config.toml
  sed -i -e "s|^external_address *=.*|external_address = \"$EXTERNAL_IP:26656\"|" $DAEMON_HOME/config/config.toml
  sed -i -e 's|^cors_allowed_origins *=.*|cors_allowed_origins = ["*", ]|' $DAEMON_HOME/config/config.toml
  sed -i -e 's|^timeout_broadcast_tx_commit *=.*|timeout_broadcast_tx_commit = "300s"|' $DAEMON_HOME/config/config.toml
  sed -i -e 's|^max_body_bytes *=.*|max_body_bytes = 1000000000|' $DAEMON_HOME/config/config.toml
  sed -i -e 's|^max_header_bytes *=.*|max_header_bytes = 5242880|' $DAEMON_HOME/config/config.toml
  sed -i -e 's|^send_rate *=.*|send_rate = 5120000|' $DAEMON_HOME/config/config.toml
  sed -i -e 's|^recv_rate *=.*|recv_rate = 5120000|' $DAEMON_HOME/config/config.toml
  sed -i -e 's|^timeout_propose *=.*|timeout_propose = "5m0s"|' $DAEMON_HOME/config/config.toml
  sed -i -e 's|^timeout_commit *=.*|timeout_commit = "5m0s"|' $DAEMON_HOME/config/config.toml
  sed -i -e 's|^max_tx_bytes *=.*|max_tx_bytes = 100000000|' $DAEMON_HOME/config/config.toml
  sed -i -e "s|^keyring-backend *=.*|keyring-backend = \"file\"|" $DAEMON_HOME/config/client.toml

  print_color $BOLD_GREEN "✅ Node initialized successfully."
fi

# 🔄 Stage 5: Snapshot Bootstrapping
DATA_USAGE_MB=$(du -sm "$DATA_DIR" 2>/dev/null | cut -f1)

if { [ "$USE_SNAPSHOT" = "true" ] || [ "$RESNAPSHOT" = "true" ]; }; then
  print_color $BOLD_YELLOW "📊 Preparing to downloading snapshot..."

  if [ -f "$DATA_DIR/$PRIV_FILE" ]; then
    cp "$DATA_DIR/$PRIV_FILE" "/tmp/$PRIV_FILE"
    print_color $BOLD_YELLOW "🔐 Backed up $PRIV_FILE"
  fi

  if [ "$RESNAPSHOT" = "true" ]; then
    print_color $BOLD_YELLOW "♻️ Resnapshot active: wiping data..."
    rm -rf "$DATA_DIR"/*
  elif [ "${DATA_USAGE_MB:-0}" -ge 10240 ]; then
    print_color $BOLD_YELLOW "⚠️ Skipping snapshot, already populated (${DATA_USAGE_MB}MB)."
    exit 0
  fi
  SNAPSHOT_BASE_URL="https://snapshots.us-nj.poktroll.com"
  SNAPSHOT_LATEST_HEIGHT=$(curl -s "$SNAPSHOT_BASE_URL/$NETWORK-latest-${SNAPSHOT_TYPE}.txt")
  SNAPSHOT_VERSION=$(curl -s "$SNAPSHOT_BASE_URL/$NETWORK-$SNAPSHOT_LATEST_HEIGHT-version.txt")
  TORRENT_URL="$SNAPSHOT_BASE_URL/$NETWORK-$SNAPSHOT_LATEST_HEIGHT-${SNAPSHOT_TYPE}.torrent"

  print_color $BOLD_GREEN "📦 Snapshot type: $SNAPSHOT_TYPE"
  print_color $BOLD_GREEN "📦 Snapshot height: $SNAPSHOT_LATEST_HEIGHT"
  print_color $BOLD_GREEN "🌐 Torrent: $TORRENT_URL"
  print_color $BOLD_GREEN "📄 Version: $SNAPSHOT_VERSION"

  SNAPSHOT_DIR="$HOME/pocket_snapshot"
  DOWNLOAD_DIR="$SNAPSHOT_DIR/download"
  TORRENT_FILE="$SNAPSHOT_DIR/snapshot.torrent"
  mkdir -p "$DOWNLOAD_DIR" "$DATA_DIR"
  curl -sSL -o "$TORRENT_FILE" "$TORRENT_URL"

  print_color $BOLD_YELLOW "🧲 Fetching snapshot (torrent)..."
  aria2c --quiet=true --seed-time=0 --dir="$DOWNLOAD_DIR" \
         --file-allocation=none --continue=true --max-connection-per-server=4 \
         --max-concurrent-downloads=16 --split=16 \
         --bt-enable-lpd=true --bt-max-peers=100 --bt-seed-unverified \
         --bt-prioritize-piece=head,tail --summary-interval=0 "$TORRENT_FILE"

  DOWNLOADED_FILE=$(find "$DOWNLOAD_DIR" -type f | head -n 1)
  [ -z "$DOWNLOADED_FILE" ] && { print_color $BOLD_RED "❌ Snapshot file missing."; exit 1; }

  # 💾 Cross-platform stat for file size
  if [[ "$OSTYPE" == "darwin"* ]]; then
    FILE_SIZE_BYTES=$(stat -f %z "$DOWNLOADED_FILE")
  else
    FILE_SIZE_BYTES=$(stat -c %s "$DOWNLOADED_FILE")
  fi
  FILE_SIZE_MB=$(( (FILE_SIZE_BYTES + 1048575) / 1048576 ))
  REQUIRED_MB=$(( FILE_SIZE_MB * 2 ))
  AVAILABLE_MB=$(df --output=avail -m "$DATA_DIR" | tail -1)

  print_color $BOLD_YELLOW "📁 Snapshot file size: ${FILE_SIZE_MB}MB"
  print_color $BOLD_YELLOW "💾 Required space to extract: ${REQUIRED_MB}MB"
  print_color $BOLD_YELLOW "🧮 Available space: ${AVAILABLE_MB}MB"

  if [ "$AVAILABLE_MB" -lt "$REQUIRED_MB" ]; then
    print_color $BOLD_RED "❌ Not enough disk space. Required ${REQUIRED_MB}MB, Available ${AVAILABLE_MB}MB"
    exit 1
  fi

  print_color "$BOLD_YELLOW" "🗜️ Extracting..."
  case "$DOWNLOADED_FILE" in
    *.tar.zst) zstd -d "$DOWNLOADED_FILE" --stdout | tar -xf - -C "$DATA_DIR" ;;
    *.tar.gz)  tar -zxf "$DOWNLOADED_FILE" -C "$DATA_DIR" ;;
    *) print_color $BOLD_RED "❌ Unknown format: $DOWNLOADED_FILE"; exit 1 ;;
  esac

  if [ -f "/tmp/$PRIV_FILE" ]; then
    mv "/tmp/$PRIV_FILE" "$DATA_DIR/$PRIV_FILE"
    print_color $BOLD_GREEN "🔒 Restored $PRIV_FILE"
  fi

  print_color $BOLD_GREEN "✅ Snapshot complete."
  rm -rf "$SNAPSHOT_DIR"
else
  print_color $BOLD_YELLOW "⏭️ Skipping snapshot: USE_SNAPSHOT=false"
fi
