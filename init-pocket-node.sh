#!/bin/bash
set -e

# Terminal color codes with bold
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'

BOLD_RED="${BOLD}${RED}"
BOLD_GREEN="${BOLD}${GREEN}"
BOLD_YELLOW="${BOLD}${YELLOW}"
NC='\033[0m' # Reset

print_color() {
  COLOR=$1
  MESSAGE=$2
  echo -e "${COLOR}${MESSAGE}${NC}"
}

# Required environment variables
: "${NETWORK:?Environment variable NETWORK not set.}"
: "${EXTERNAL_IP:?Environment variable EXTERNAL_IP not set.}"
: "${NODE_MONIKER:?Environment variable NODE_MONIKER not set.}"
: "${USE_SNAPSHOT:?Environment variable USE_SNAPSHOT not set.}"
RESNAPSHOT="${RESNAPSHOT:-false}"
SNAPSHOT_TYPE="${SNAPSHOT_TYPE:-archival}"  # 'archival' or 'pruned'

# Paths
DATA_DIR="$HOME/.pocket/data"
CONFIG_FILE="$HOME/.pocket/config/genesis.json"
POCKET_BIN="$HOME/.pocket/cosmovisor/genesis/bin/pocketd"
PRIV_FILE="priv_validator_state.json"

# ===============================
# 🔧 Initialize Node Configuration
# ===============================
if [ -s "$CONFIG_FILE" ]; then
  print_color $BOLD_YELLOW "⚠️ Node already initialized. Skipping setup."
else
  POCKET_NETWORK_GENESIS_BRANCH="${POCKET_NETWORK_GENESIS_BRANCH:-master}"
  BASE_URL="https://raw.githubusercontent.com/pokt-network/pocket-network-genesis/${POCKET_NETWORK_GENESIS_BRANCH}/shannon/$NETWORK"
  SEEDS_URL="$BASE_URL/seeds"
  GENESIS_URL="$BASE_URL/genesis.json"

  GENESIS_FILE="/tmp/genesis.json"
  print_color $BOLD_YELLOW "📥 Downloading genesis file from $GENESIS_URL..."
  curl -sSL -o "$GENESIS_FILE" "$GENESIS_URL" || {
    print_color $BOLD_RED "❌ Failed to download genesis file."
    exit 1
  }

  CHAIN_ID=$(jq -r '.chain_id' < "$GENESIS_FILE")
  [ -z "$CHAIN_ID" ] && { print_color $BOLD_RED "❌ Failed to extract chain_id."; exit 1; }

  GENESIS_VERSION=$(jq -r '.app_version' < "$GENESIS_FILE")
  [ -z "$GENESIS_VERSION" ] && { print_color $BOLD_RED "❌ Failed to extract app_version."; exit 1; }

  print_color $BOLD_GREEN "🔗 chain_id: $CHAIN_ID"
  print_color $BOLD_GREEN "📦 app_version: $GENESIS_VERSION"

  SEEDS=$(curl -s "$SEEDS_URL")
  [ -z "$SEEDS" ] && { print_color $BOLD_RED "❌ Failed to fetch seeds."; exit 1; }
  print_color $BOLD_GREEN "🌱 Seeds fetched successfully"

  "$POCKET_BIN" init "$NODE_MONIKER" --chain-id="$CHAIN_ID" --home=$HOME/.pocket >/dev/null 2>&1
  cp "$GENESIS_FILE" $HOME/.pocket/config/genesis.json
  sed -i -e "s|^seeds *=.*|seeds = \"$SEEDS\"|" $HOME/.pocket/config/config.toml
  sed -i -e "s|^external_address *=.*|external_address = \"$EXTERNAL_IP:26656\"|" $HOME/.pocket/config/config.toml
  sed -i -e "s|^keyring-backend *=.*|keyring-backend = \"test\"|" $HOME/.pocket/config/client.toml

  print_color $BOLD_GREEN "✅ Node initialized successfully."
fi

# ===============================
# 📦 Download & Apply Snapshot
# ===============================
DATA_USAGE_MB=$(du -sm "$DATA_DIR" 2>/dev/null | cut -f1)

if { [ "$USE_SNAPSHOT" = "true" ] || [ "$RESNAPSHOT" = "true" ]; }; then
  print_color $BOLD_YELLOW "📊 Preparing to download snapshot..."

  # Backup priv_validator_state.json if it exists
  if [ -f "$DATA_DIR/$PRIV_FILE" ]; then
    cp "$DATA_DIR/$PRIV_FILE" "/tmp/$PRIV_FILE"
    print_color $BOLD_YELLOW "🔒 Backed up $PRIV_FILE"
  fi

  # Clean data if forced
  if [ "$RESNAPSHOT" = "true" ]; then
    print_color $BOLD_YELLOW "♻️ RESNAPSHOT=true. Forcing snapshot reset."
    rm -rf "$DATA_DIR"/*
  elif [ "${DATA_USAGE_MB:-0}" -ge 1024 ]; then
    print_color $BOLD_YELLOW "⚠️ Skipping snapshot: data already populated (${DATA_USAGE_MB}MB)."
    exit 0
  fi

  # Prepare snapshot info
  SNAPSHOT_BASE_URL="https://snapshots.us-nj.poktroll.com"
  LATEST_SNAPSHOT_HEIGHT=$(curl -s "$SNAPSHOT_BASE_URL/$NETWORK-latest-${SNAPSHOT_TYPE}.txt")
  SNAPSHOT_VERSION=$(curl -s "$SNAPSHOT_BASE_URL/$NETWORK-$LATEST_SNAPSHOT_HEIGHT-version.txt")
  TORRENT_URL="$SNAPSHOT_BASE_URL/$NETWORK-$LATEST_SNAPSHOT_HEIGHT-${SNAPSHOT_TYPE}.torrent"

  print_color $BOLD_GREEN "📦 Snapshot type: $SNAPSHOT_TYPE"
  print_color $BOLD_GREEN "📦 Snapshot height: $LATEST_SNAPSHOT_HEIGHT"
  print_color $BOLD_GREEN "📄 Version: $SNAPSHOT_VERSION"
  print_color $BOLD_GREEN "🌐 Torrent: $TORRENT_URL"

  # Prepare folders
  SNAPSHOT_DIR="$HOME/pocket_snapshot"
  DOWNLOAD_DIR="$SNAPSHOT_DIR/download"
  TORRENT_FILE="$SNAPSHOT_DIR/snapshot.torrent"
  mkdir -p "$DOWNLOAD_DIR" "$DATA_DIR"

  # Download torrent file silently
  curl -sSL -o "$TORRENT_FILE" "$TORRENT_URL"

  print_color $BOLD_YELLOW "📡 Downloading snapshot via torrent... (this may take a while)"

  # Run aria2c silently
  aria2c --quiet=true \
         --seed-time=0 --dir="$DOWNLOAD_DIR" --file-allocation=none --continue=true \
         --max-connection-per-server=4 --max-concurrent-downloads=16 --split=16 \
         --bt-enable-lpd=true --bt-max-peers=100 --bt-prioritize-piece=head,tail \
         --bt-seed-unverified --summary-interval=0 \
         "$TORRENT_FILE"

  if [ $? -ne 0 ]; then
    print_color $BOLD_RED "❌ aria2c download failed."
    exit 1
  else
    print_color $BOLD_GREEN "✅ Snapshot download completed."
  fi

  # Determine file and check disk space
  DOWNLOADED_FILE=$(find "$DOWNLOAD_DIR" -type f | head -n 1)
  [ -z "$DOWNLOADED_FILE" ] && { print_color $BOLD_RED "❌ No snapshot file found."; exit 1; }

  FILE_SIZE_MB=$(( ($(stat -c %s "$DOWNLOADED_FILE") + 1048575) / 1048576 ))
  REQUIRED_MB=$(( FILE_SIZE_MB * 2 ))
  AVAILABLE_MB=$(df --output=avail -m "$DATA_DIR" | tail -1)

  print_color $BOLD_YELLOW "📁 Snapshot file size: ${FILE_SIZE_MB}MB"
  print_color $BOLD_YELLOW "💾 Required space to extract: ${REQUIRED_MB}MB"
  print_color $BOLD_YELLOW "🧮 Available space: ${AVAILABLE_MB}MB"

  if [ "$AVAILABLE_MB" -lt "$REQUIRED_MB" ]; then
    print_color $BOLD_RED "❌ Not enough disk space. Required: ${REQUIRED_MB}MB, Available: ${AVAILABLE_MB}MB"
    exit 1
  fi

  # Extract
  if [[ "$DOWNLOADED_FILE" == *.tar.zst ]]; then
    print_color $BOLD_YELLOW "🗜️ Extracting .tar.zst snapshot..."
    zstd -d "$DOWNLOADED_FILE" --stdout | tar -xf - -C "$DATA_DIR"
  elif [[ "$DOWNLOADED_FILE" == *.tar.gz ]]; then
    print_color $BOLD_YELLOW "🗜️ Extracting .tar.gz snapshot..."
    tar -zxf "$DOWNLOADED_FILE" -C "$DATA_DIR"
  else
    print_color $BOLD_RED "❌ Unknown snapshot format: $DOWNLOADED_FILE"
    exit 1
  fi

  # Restore priv_validator_state.json
  if [ -f "/tmp/$PRIV_FILE" ]; then
    mv "/tmp/$PRIV_FILE" "$DATA_DIR/$PRIV_FILE"
    print_color $BOLD_GREEN "🔒 Restored $PRIV_FILE"
  fi

  print_color $BOLD_GREEN "✅ Snapshot extraction complete."
  rm -rf "$SNAPSHOT_DIR"
  print_color $BOLD_GREEN "🧹 Cleaned up temporary snapshot files."

else
  print_color $BOLD_YELLOW "⚠️ Skipping snapshot: USE_SNAPSHOT=false and RESNAPSHOT=false."
fi
