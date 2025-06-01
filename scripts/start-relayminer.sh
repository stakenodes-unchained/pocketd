#!/bin/bash
set -e

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

print_color() {
  COLOR=$1
  MESSAGE=$2
  echo -e "${COLOR}${BOLD}${MESSAGE}${NC}"
}

# Display environment variables
print_color $YELLOW "🔁 ENABLE_RELAYMINER: ${ENABLE_RELAYMINER}"
print_color $YELLOW "🔗 CHAIN_ID: ${CHAIN_ID}"

# Set the keyring-backend to file
sed -i -e "s|^keyring-backend *=.*|keyring-backend = \"file\"|" $HOME/.pocket/config/client.toml

# Check if RelayMiner should run
if [ "${ENABLE_RELAYMINER}" = "false" ]; then
  print_color $YELLOW "⚠️ RelayMiner is not needed and will be terminated."
  exit 0
fi

# Config file path (can be overridden via environment variable)
CONFIG_PATH="${CONFIG_PATH:-/home/pocket/.pocket/relayminer-config.yaml}"
KEYRING_DIR="${DAEMON_HOME:-/home/pocket/.pocket}/keyring-file"
MAX_ATTEMPTS=5
WAIT_TIME=60
ATTEMPT=1

# Wait for the config file to exist
while [ ! -f "$CONFIG_PATH" ]; do
  print_color $RED "⏳ RelayMiner config not found at $CONFIG_PATH"
  print_color $YELLOW "Waiting for file to be copied... (Attempt $ATTEMPT of $MAX_ATTEMPTS)"
  sleep $WAIT_TIME
  ATTEMPT=$((ATTEMPT+1))
  if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
    print_color $RED "❌ RelayMiner config file was not found after 5 minutes. Exiting."
    exit 1
  fi
done

# Wait for keyring directory to contain keys
ATTEMPT=1
while [ ! -d "$KEYRING_DIR" ] || [ -z "$(ls -A "$KEYRING_DIR" 2>/dev/null)" ]; do
  print_color $RED "🔒 No keys found in keyring directory at $KEYRING_DIR"
  print_color $YELLOW "Waiting for keys to appear... (Attempt $ATTEMPT of $MAX_ATTEMPTS)"
  sleep $WAIT_TIME
  ATTEMPT=$((ATTEMPT+1))
  if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
    print_color $RED "❌ Keyring folder remained empty after 5 minutes. Exiting."
    exit 1
  fi
done

# Wait for Pocket RPC endpoint to be ready
POCKET_RPC_URL="http://pocketd-node:26657/status"
ATTEMPT=1
print_color $YELLOW "⏳ Waiting for Pocket RPC endpoint to be ready..."

until curl -sf "$POCKET_RPC_URL" >/dev/null; do
  print_color $YELLOW "Attempt $ATTEMPT of $MAX_ATTEMPTS: RPC not ready..."
  sleep $WAIT_TIME
  ATTEMPT=$((ATTEMPT+1))
  if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
    print_color $RED "❌ Pocket RPC not reachable at $POCKET_RPC_URL after 5 minutes. Exiting."
    exit 1
  fi
done

# Start RelayMiner
print_color $GREEN "🚀 Starting RelayMiner..."
exec echo "$POCKET_KEYRING_PASSPHRASE" | pocketd \
  relayminer start \
  --grpc-insecure=true \
  --log_level=debug \
  --config="$CONFIG_PATH" \
  --chain-id="${CHAIN_ID}"
  --keyring-backend=file
  --home="$DAEMON_HOME"
