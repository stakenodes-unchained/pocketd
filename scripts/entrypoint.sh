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
DAEMON_HOME="${DAEMON_HOME:-/home/pocket/.pocket}"

print_color $BOLD_GREEN "🧱 Bootstrapping Pocket Node..."
print_color $BOLD_YELLOW "🛠  NETWORK: ${NETWORK}"
print_color $BOLD_YELLOW "🛠  NODE_MONIKER: ${NODE_MONIKER}"
print_color $BOLD_YELLOW "🛠  EXTERNAL_IP: ${EXTERNAL_IP}"
print_color $BOLD_YELLOW "🛠  POCKETD_LOG_LEVEL: ${POCKETD_LOG_LEVEL}"
print_color $BOLD_YELLOW "🛠  DAEMON_HOME: ${DAEMON_HOME}"

# 📦 Stage 2: Ensure Binary and Symlink
POCKET_BIN="$DAEMON_HOME/cosmovisor/genesis/bin/pocketd"
GENESIS_BIN="/usr/local/cosmovisor/genesis/bin/pocketd"
COSMOVISOR_SYMLINK="$DAEMON_HOME/cosmovisor/current"

if [ ! -f "$POCKET_BIN" ]; then
  print_color $BOLD_YELLOW "📦 Copying pocketd binary into volume..."
  mkdir -p "$(dirname "$POCKET_BIN")"
  cp "$GENESIS_BIN" "$POCKET_BIN"
fi

if [ ! -L "$COSMOVISOR_SYMLINK" ] || [ "$(readlink "$COSMOVISOR_SYMLINK")" != "$DAEMON_HOME/cosmovisor/genesis" ]; then
  print_color $BOLD_YELLOW "🔗 Fixing cosmovisor/current symlink..."
  rm -f "$COSMOVISOR_SYMLINK"
  ln -s "$DAEMON_HOME/cosmovisor/genesis" "$COSMOVISOR_SYMLINK"
fi

# 🧬 Stage 3: Node Initialization
CONFIG_FILE="$DAEMON_HOME/config/genesis.json"

if [ -s "$CONFIG_FILE" ]; then
  print_color $BOLD_YELLOW "⚠️ Node already initialized. Skipping setup."
else
  GENESIS_BRANCH="${POCKET_NETWORK_GENESIS_BRANCH:-master}"
  BASE_URL="https://raw.githubusercontent.com/pokt-network/pocket-network-genesis/${GENESIS_BRANCH}/shannon/${NETWORK}"
  GENESIS_URL="${BASE_URL}/genesis.json"
  SEEDS_URL="${BASE_URL}/seeds"
  GENESIS_FILE="/tmp/genesis.json"

  print_color $BOLD_YELLOW "📥 Downloading genesis file..."
  curl -sSL -o "$GENESIS_FILE" "$GENESIS_URL" || {
    print_color $BOLD_RED "❌ Failed to download genesis."
    exit 1
  }

  # Derive chain ID from network name
  case "$NETWORK" in
    testnet-beta)  CHAIN_ID="pocket-beta" ;;
    testnet-alpha) CHAIN_ID="pocket-alpha" ;;
    mainnet)       CHAIN_ID="pocket" ;;
    *)             print_color $BOLD_RED "❌ Unsupported NETWORK: $NETWORK"; exit 1 ;;
  esac

  GENESIS_VERSION=$(jq -r '.app_version' < "$GENESIS_FILE")

  [ -z "$GENESIS_VERSION" ] && { print_color $BOLD_RED "❌ app_version missing."; exit 1; }

  print_color $BOLD_GREEN "🔗 chain_id: $CHAIN_ID"
  print_color $BOLD_GREEN "📦 version: $GENESIS_VERSION"

  SEEDS=$(curl -s "$SEEDS_URL")
  [ -z "$SEEDS" ] && { print_color $BOLD_RED "❌ Failed to fetch seeds."; exit 1; }

  "$POCKET_BIN" init "$NODE_MONIKER" --chain-id="$CHAIN_ID" --home="$DAEMON_HOME" >/dev/null 2>&1
  cp "$GENESIS_FILE" "$CONFIG_FILE"

  print_color $BOLD_GREEN "✅ Node initialized successfully."
fi

# ⏭️ Stage 4: Handle Upgrade Skips
SKIP_UPGRADES_HEIGHTS_URL="${BASE_URL}/skip_upgrade_heights"
SKIP_UPGRADES=""
SKIP_UPGRADE_HEIGHTS=$(curl -s "$SKIP_UPGRADES_HEIGHTS_URL")
if [ -n "$SKIP_UPGRADE_HEIGHTS" ]; then
  print_color $BOLD_YELLOW "⏭️  Skipping upgrade heights: $SKIP_UPGRADE_HEIGHTS"
  SKIP_UPGRADES="--unsafe-skip-upgrades $SKIP_UPGRADE_HEIGHTS"
fi

# 🚀 Stage 5: Start the Node
print_color $BOLD_GREEN "🚀 Starting cosmovisor..."
exec cosmovisor run start \
  --home="$DAEMON_HOME" \
  --rpc.laddr="tcp://0.0.0.0:26657" \
  --p2p.laddr="tcp://0.0.0.0:26656" \
  --p2p.external-address="${EXTERNAL_IP}:26656" \
  --p2p.seeds="${SEEDS}" \
  --log_level="${POCKETD_LOG_LEVEL}" \
  $SKIP_UPGRADES
