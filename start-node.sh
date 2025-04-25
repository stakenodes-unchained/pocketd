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

# Trap to detect if container stops
trap 'print_color $RED "🛑 Pocket Node stopped."' EXIT

# --- Stage 1: Initialization Info ---
print_color $GREEN "🚀 Bootstrapping Pocket Node..."
print_color $YELLOW "🛠 NETWORK: ${NETWORK}"
print_color $YELLOW "🛠 NODE_MONIKER: ${NODE_MONIKER}"
print_color $YELLOW "🛠 USE_SNAPSHOT: ${USE_SNAPSHOT}"
print_color $YELLOW "🛠 EXTERNAL_IP: ${EXTERNAL_IP}"

# --- Stage 2: Validate Environment Variables ---
: "${DAEMON_HOME:?Environment variable DAEMON_HOME not set.}"
: "${POCKETD_LOG_LEVEL:?Environment variable POCKETD_LOG_LEVEL not set.}"

# --- Stage 3: Run initialization script (if needed) ---
/init-pocket-node.sh

# --- Stage 4: Start cosmovisor with full startup flags ---
print_color $GREEN "🚀 Starting cosmovisor with configured options..."
exec cosmovisor run start \
  --home="$DAEMON_HOME" \
  --rpc.laddr="tcp://0.0.0.0:26657" \
  --p2p.laddr="tcp://0.0.0.0:26656" \
  --p2p.external-address="${EXTERNAL_IP}:26656" \
  --log_level="${POCKETD_LOG_LEVEL}"
