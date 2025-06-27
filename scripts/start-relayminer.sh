#!/bin/bash
set -e

# 🎨 Terminal colors
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

export PATH="/usr/local/cosmovisor/genesis/bin:$PATH"

# 🚦 Stage 1: Early Exit if Disabled
if [ "${ENABLE_RELAYMINER}" = "false" ]; then
  print_color $YELLOW "⚠️ RelayMiner is not needed and will be terminated."
  exit 0
fi

# 🧱 Stage 2: Initialization Info
: "${CHAIN_ID:?Environment variable CHAIN_ID not set.}"
ENABLE_RELAYMINER="${ENABLE_RELAYMINER:-true}"
DAEMON_HOME="${DAEMON_HOME:-/home/pocket/.pocket}"
POCKET_NODE_URL="${POCKET_ENDPOINT:-http://pocketd-node:26657}"
CONFIG_PATH="${CONFIG_PATH:-$DAEMON_HOME/config/config.yaml}"
KEYRING_BACKEND="${KEYRING_BACKEND:-os}"

print_color $YELLOW "🔁 ENABLE_RELAYMINER: ${ENABLE_RELAYMINER}"
print_color $YELLOW "🔗 CHAIN_ID: ${CHAIN_ID}"
print_color $YELOOW "🛠  POCKETD_VERSION: $(pocketd version)"

# 🔑 Stage 3: Keyring Backend & Passphrase Validation
if [[ "$KEYRING_BACKEND" != "test" && -z "$POCKET_KEYRING_PASSPHRASE" ]]; then
  print_color $RED "❌ POCKET_KEYRING_PASSPHRASE must be set when using '$KEYRING_BACKEND' backend."
  exit 1
fi

# 🏠 Stage 4: Pocket Home & Config
if [ ! -f "$DAEMON_HOME/config/client.toml" ]; then
  print_color $YELLOW "🛠️ Pocket node not initialized. Running 'pocketd init'..."
  pocketd init relayminer --chain-id="${CHAIN_ID}" --home="$DAEMON_HOME"
fi

# Update keyring-backend in client.toml (suppress errors if file doesn't exist yet)
sed -i -e 's|^timeout_propose *=.*|timeout_propose = "15s"|' $DAEMON_HOME/config/config.toml
sed -i -e 's|^timeout_commit *=.*|timeout_commit = "30s"|' $DAEMON_HOME/config/config.toml
sed -i -e "s|^keyring-backend *=.*|keyring-backend = \"${KEYRING_BACKEND}\"|" "$DAEMON_HOME/config/client.toml"

# 🔒 Stage 5: Keyring Directory Check (for 'file' and 'test')
KEYRING_DIR=""
if [[ "$KEYRING_BACKEND" == "file" || "$KEYRING_BACKEND" == "test" ]]; then
  KEYRING_DIR="${DAEMON_HOME}/keyring-${KEYRING_BACKEND}"
fi

# 📝 Stage 6: Wait for Config File
MAX_ATTEMPTS=5
WAIT_TIME=60
ATTEMPT=1
while [ ! -f "$CONFIG_PATH" ]; do
  print_color $RED "⏳ RelayMiner config not found at $CONFIG_PATH"
  print_color $YELLOW "Waiting for file to be copied... (Attempt $ATTEMPT of $MAX_ATTEMPTS)"
  print_color $YELLOW "💡 Example:"
  print_color $YELLOW "   docker cp relayminer-config.yaml relayminer:$CONFIG_PATH"
  sleep $WAIT_TIME
  ATTEMPT=$((ATTEMPT+1))
  if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
    print_color $RED "❌ RelayMiner config file was not found after 5 minutes. Exiting."
    exit 1
  fi
done

# 🔑 Stage 7: Wait for Keyring Keys (only for 'file' or 'test')
if [[ -n "$KEYRING_DIR" ]]; then
  ATTEMPT=1
  while [ ! -d "$KEYRING_DIR" ] || [ -z "$(ls -A "$KEYRING_DIR" 2>/dev/null)" ]; do
    print_color $RED "🔒 No keys found in keyring directory at $KEYRING_DIR"
    print_color $YELLOW "Waiting for keys to appear... (Attempt $ATTEMPT of $MAX_ATTEMPTS)"
    print_color $YELLOW "💡 Example:"
    print_color $YELLOW "   docker exec -it relayminer pocketd keys add <key_name> --home=$DAEMON_HOME --keyring-backend=$KEYRING_BACKEND"
    print_color $YELLOW "   docker exec -it relayminer pocketd keys add <key_name> --recover --home=$DAEMON_HOME --keyring-backend=$KEYRING_BACKEND"
    sleep $WAIT_TIME
    ATTEMPT=$((ATTEMPT+1))
    if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
      print_color $RED "❌ Keyring folder remained empty after 5 minutes. Exiting."
      exit 1
    fi
  done
fi

# 🌐 Stage 8: Wait for Pocket RPC Endpoint
POCKET_RPC_URL_STATUS="${POCKET_NODE_URL}/status"
ATTEMPT=1
print_color $YELLOW "⏳ Waiting for Pocket RPC endpoint to be ready..."

until curl -sf "$POCKET_RPC_URL_STATUS" >/dev/null; do
  print_color $YELLOW "Attempt $ATTEMPT of $MAX_ATTEMPTS: RPC not ready..."
  sleep $WAIT_TIME
  ATTEMPT=$((ATTEMPT+1))
  if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
    print_color $RED "❌ Pocket RPC not reachable at $POCKET_RPC_URL_STATUS after 5 minutes. Exiting."
    exit 1
  fi
done

# 🚀 Stage 9: Start RelayMiner
print_color $GREEN "🚀 Starting RelayMiner..."
if [[ "$KEYRING_BACKEND" == "test" ]]; then
  exec pocketd \
    relayminer start \
    --grpc-insecure=true \
    --log_level=debug \
    --config="$CONFIG_PATH" \
    --chain-id="${CHAIN_ID}" \
    --home="$DAEMON_HOME" \
    --keyring-backend="${KEYRING_BACKEND}" \
    --node="${POCKET_NODE_URL}" \
    --gas-adjustment=1.7 \
    --gas-prices=0.000001upokt
else
  exec bash -c "echo \"\$POCKET_KEYRING_PASSPHRASE\" | pocketd \
    relayminer start \
    --grpc-insecure=true \
    --log_level=debug \
    --config=\"$CONFIG_PATH\" \
    --chain-id=\"${CHAIN_ID}\" \
    --home=\"$DAEMON_HOME\" \
    --keyring-backend=\"${KEYRING_BACKEND}\" \
    --node=\"${POCKET_NODE_URL}\" \
    --gas-adjustment=1.7 \
   --gas-prices=0.000001upokt"
fi
