#!/bin/bash
set -e

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_color() {
  COLOR=$1
  MESSAGE=$2
  echo -e "${COLOR}${MESSAGE}${NC}"
}

# Required: environment variables
: "${NETWORK:?Environment variable NETWORK not set.}"
: "${EXTERNAL_IP:?Environment variable EXTERNAL_IP not set.}"
: "${NODE_MONIKER:?Environment variable NODE_MONIKER not set.}"
: "${USE_SNAPSHOT:?Environment variable USE_SNAPSHOT not set.}"

# Define paths
DATA_DIR="$HOME/.pocket/data"
CONFIG_FILE="$HOME/.pocket/config/genesis.json"
POCKET_BIN="$HOME/.pocket/cosmovisor/genesis/bin/pocketd"
PRIV_FILE="priv_validator_state.json"

# ===============================
# 🔧 Initialize Node Configuration
# ===============================

# Check if config file already exists and is non-empty
if [ -s "$CONFIG_FILE" ]; then
  print_color $YELLOW "⚠️  Node already initialized. Skipping setup."
else
  POCKET_NETWORK_GENESIS_BRANCH="${POCKET_NETWORK_GENESIS_BRANCH:-master}"
  BASE_URL="https://raw.githubusercontent.com/pokt-network/pocket-network-genesis/${POCKET_NETWORK_GENESIS_BRANCH}/shannon/$NETWORK"
  SEEDS_URL="$BASE_URL/seeds"
  GENESIS_URL="$BASE_URL/genesis.json"

  # Download genesis.json and store it
  GENESIS_FILE="/tmp/genesis.json"
  print_color $YELLOW "📥 Downloading genesis file from $GENESIS_URL..."
  curl -s -o "$GENESIS_FILE" "$GENESIS_URL"
  if [ $? -ne 0 ]; then
    print_color $RED "❌ Failed to download genesis file. Please check your internet connection and try again."
    exit 1
  fi

  # Extract chain_id
  CHAIN_ID=$(jq -r '.chain_id' < "$GENESIS_FILE")
  if [ -z "$CHAIN_ID" ]; then
    print_color $RED "❌ Failed to extract chain_id from genesis file."
    exit 1
  fi
  print_color $GREEN "🔗 Using chain_id: $CHAIN_ID from genesis file"

  # Extract app_version
  GENESIS_VERSION=$(jq -r '.app_version' < "$GENESIS_FILE")
  if [ -z "$GENESIS_VERSION" ]; then
    print_color $RED "❌ Failed to extract version information from genesis file."
    exit 1
  fi
  print_color $YELLOW "📦 Detected version from genesis: $GENESIS_VERSION"

  # Fetch seeds from the provided URL
  SEEDS=$(curl -s "$SEEDS_URL")
  if [ -z "$SEEDS" ]; then
    print_color $RED "❌ Failed to fetch seeds from $SEEDS_URL. Please check your internet connection and try again."
    exit 1
  fi
  print_color $GREEN "🌱 Successfully fetched seeds: $SEEDS"

  # Initialize node using pocketd
  "$POCKET_BIN" init "$NODE_MONIKER" --chain-id="$CHAIN_ID" --home=$HOME/.pocket
  cp "$GENESIS_FILE" $HOME/.pocket/config/genesis.json
  sed -i -e "s|^seeds *=.*|seeds = \"$SEEDS\"|" $HOME/.pocket/config/config.toml
  sed -i -e "s|^external_address *=.*|external_address = \"$EXTERNAL_IP:26656\"|" $HOME/.pocket/config/config.toml

  if [ $? -eq 0 ]; then
    print_color $GREEN "✅ pocketd configured successfully."
  else
    print_color $RED "❌ Failed to configure pocketd. Please check the error messages above."
    exit 1
  fi
fi

# ==============================
# 📦 Download & Apply Snapshot
# ==============================

DATA_USAGE_MB=$(du -sm "$DATA_DIR" 2>/dev/null | cut -f1)
if [ "$USE_SNAPSHOT" = "true" ] && { [ -z "$DATA_USAGE_MB" ] || [ "$DATA_USAGE_MB" -lt 1024 ]; }; then
  print_color $YELLOW "📊 Data folder usage: ${DATA_USAGE_MB:-0}MB. Proceeding with snapshot download."

  # Backup priv_validator_state.json
  if [ -f "$DATA_DIR/$PRIV_FILE" ]; then
    cp "$DATA_DIR/$PRIV_FILE" "/tmp/$PRIV_FILE"
    print_color $YELLOW "🔒 Backed up $PRIV_FILE"
  fi

  # Clean data directory
  rm -rf "$DATA_DIR"/*

  SNAPSHOT_BASE_URL="https://snapshots.us-nj.poktroll.com"
  LATEST_SNAPSHOT_HEIGHT_URL="$SNAPSHOT_BASE_URL/$NETWORK-latest-archival.txt"
  LATEST_SNAPSHOT_HEIGHT=$(curl -s "$LATEST_SNAPSHOT_HEIGHT_URL")
  SNAPSHOT_VERSION_URL="$SNAPSHOT_BASE_URL/$NETWORK-$LATEST_SNAPSHOT_HEIGHT-version.txt"
  SNAPSHOT_VERSION=$(curl -s "$SNAPSHOT_VERSION_URL")
  TORRENT_URL="$SNAPSHOT_BASE_URL/$NETWORK-$LATEST_SNAPSHOT_HEIGHT-archival.torrent"

  print_color $GREEN "📦 Found snapshot at height: $LATEST_SNAPSHOT_HEIGHT"
  print_color $YELLOW "Snapshot version: $SNAPSHOT_VERSION"
  print_color $YELLOW "Snapshot torrent URL: $TORRENT_URL"

  SNAPSHOT_DIR="$HOME/pocket_snapshot"
  DOWNLOAD_DIR="$SNAPSHOT_DIR/download"
  TORRENT_FILE="$SNAPSHOT_DIR/snapshot.torrent"

  mkdir -p "$DOWNLOAD_DIR"
  curl -L -o "$TORRENT_FILE" "$TORRENT_URL"

  # Run aria2c and extract snapshot
  (
    set -e
    mkdir -p "$DATA_DIR"

    aria2c --seed-time=0 --dir="$DOWNLOAD_DIR" --file-allocation=none --continue=true \
           --max-connection-per-server=4 --max-concurrent-downloads=16 --split=16 \
           --bt-enable-lpd=true --bt-max-peers=100 --bt-prioritize-piece=head,tail \
           --bt-seed-unverified --summary-interval=0 \
           "$TORRENT_FILE"

    DOWNLOADED_FILE=$(find "$DOWNLOAD_DIR" -type f | head -n 1)

    if [ -z "$DOWNLOADED_FILE" ]; then
      echo "No snapshot file found in download directory."
      exit 1
    fi

    if [[ "$DOWNLOADED_FILE" == *.tar.zst ]]; then
      echo "Extracting .tar.zst snapshot..."
      zstd -d "$DOWNLOADED_FILE" --stdout | tar -xf - -C "$DATA_DIR"
    elif [[ "$DOWNLOADED_FILE" == *.tar.gz ]]; then
      echo "Extracting .tar.gz snapshot..."
      tar -zxf "$DOWNLOADED_FILE" -C "$DATA_DIR"
    else
      echo "Unknown snapshot format: $DOWNLOADED_FILE"
      exit 1
    fi
  )

  # Restore priv_validator_state.json
  if [ -f "/tmp/$PRIV_FILE" ]; then
    mv "/tmp/$PRIV_FILE" "$DATA_DIR/$PRIV_FILE"
    print_color $GREEN "🔒 Restored $PRIV_FILE after snapshot"
  fi

  print_color $GREEN "✅ Snapshot download and extraction complete."
  rm -rf "$SNAPSHOT_DIR"
  print_color $GREEN "🧹 Cleaned up temporary files."
else
  print_color $YELLOW "⚠️  Skipping snapshot: either disabled or data folder already populated (>1GB)."
fi
