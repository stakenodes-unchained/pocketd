#!/bin/bash
set -e

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
BOLD_GREEN="${BOLD}${GREEN}"
BOLD_YELLOW="${BOLD}${YELLOW}"
NC='\033[0m'

print_color() {
  COLOR=$1
  MESSAGE=$2
  echo -e "${COLOR}${MESSAGE}${NC}"
}

# 🏮 Trap to detect if container stops
trap 'print_color $RED "🛑 Pocket Node stopped."' EXIT

# 🧱 Stage 1: Initialization Info
: "${DAEMON_HOME:?Environment variable DAEMON_HOME not set.}"
: "${POCKETD_LOG_LEVEL:?Environment variable POCKETD_LOG_LEVEL not set.}"

print_color $BOLD_GREEN "🧱 Bootstrapping Pocket Node..."
print_color $BOLD_YELLOW "🛠  NETWORK: ${NETWORK}"
print_color $BOLD_YELLOW "🛠  NODE_MONIKER: ${NODE_MONIKER}"
print_color $BOLD_YELLOW "🛠  EXTERNAL_IP: ${EXTERNAL_IP}"
print_color $BOLD_YELLOW "🛠  POCKETD_LOG_LEVEL: ${POCKETD_LOG_LEVEL}"
print_color $BOLD_YELLOW "🛠  DAEMON_HOME: ${DAEMON_HOME}"

# 🏁 Stage 2: Run initialization script
if [ ! -x /scripts/init-pocket-node.sh ]; then
  print_color $RED "❌ /scripts/init-pocket-node.sh is missing or not executable. Exiting."
  exit 1
fi
/scripts/init-pocket-node.sh

# ⏭️ Stage 3: Get skip upgrade heights (if any)
POCKET_NETWORK_GENESIS_BRANCH="${POCKET_NETWORK_GENESIS_BRANCH:-master}"
BASE_URL="https://raw.githubusercontent.com/pokt-network/pocket-network-genesis/${POCKET_NETWORK_GENESIS_BRANCH}/shannon/${NETWORK}"
SKIP_UPGRADES_HEIGHTS_URL="${BASE_URL}/skip_upgrade_heights"

SKIP_UPGRADES=""
SKIP_UPGRADE_HEIGHTS=$(curl -s "$SKIP_UPGRADES_HEIGHTS_URL")
if [ -n "$SKIP_UPGRADE_HEIGHTS" ]; then
  print_color $YELLOW "⏭️  Skipping upgrade heights: $SKIP_UPGRADE_HEIGHTS"
  SKIP_UPGRADES="--unsafe-skip-upgrades $SKIP_UPGRADE_HEIGHTS"
fi

# 🚀 Stage 4: Start cosmovisor with full startup flags
print_color $GREEN "🚀 Starting cosmovisor with configured options..."
exec cosmovisor run start \
  --home="$DAEMON_HOME" \
  --rpc.laddr="tcp://0.0.0.0:26657" \
  --p2p.laddr="tcp://0.0.0.0:26656" \
  --p2p.external-address="${EXTERNAL_IP}:26656" \
  --api.enable \
  --api.address="tcp://0.0.0.0:1317" \
  --api.enabled-unsafe-cors \
  --grpc.enable \
  --grpc.address="0.0.0.0:9090" \
  --minimum-gas-prices="0.000000001upokt" \
  --api.max-open-connections=1000 \
  --api.rpc-read-timeout=120 \
  --api.rpc-write-timeout=120 \
  --api.rpc-max-body-bytes=1000000 \
  --api.swagger=false \
  --mempool.max-txs=10000 \
  --log_level="${POCKETD_LOG_LEVEL}" \
  $SKIP_UPGRADES
