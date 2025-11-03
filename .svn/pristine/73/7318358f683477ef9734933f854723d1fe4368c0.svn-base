#!/usr/bin/env bash
set -euo pipefail

# Script to add a new Wireguard peer
# Usage: ./add-peer.sh <peer-name>

if [ $# -ne 1 ]; then
  echo "Usage: $0 <peer-name>"
  echo "Example: $0 peer2"
  exit 1
fi

PEER_NAME="$1"
PERSIST_CONFIG_DIR="${PERSIST_CONFIG_DIR:-/config}"
WG_INTERFACE_NAME="${WG_INTERFACE_NAME:-wg0}"
WG_SERVER_ADDRESS="${WG_SERVER_ADDRESS:-10.66.66.1/24}"
WG_LISTEN_PORT="${WG_LISTEN_PORT:-51820}"
WG_ENDPOINT="${WG_ENDPOINT:-your.public.ip.example.com:${WG_LISTEN_PORT}}"
WG_ALLOWED_IPS="${WG_ALLOWED_IPS:-0.0.0.0/0, ::/0}"
WG_PERSISTENT_KEEPALIVE="${WG_PERSISTENT_KEEPALIVE:-25}"

# Extract server IP and network
WG_SERVER_IP=${WG_SERVER_ADDRESS%%/*}
WG_NETWORK_PREFIX=$(echo "$WG_SERVER_ADDRESS" | cut -d'.' -f1-3)

# Check if peer already exists
PEER_DIR="${PERSIST_CONFIG_DIR}/clients/${PEER_NAME}"
if [ -d "$PEER_DIR" ]; then
  echo "Error: Peer '${PEER_NAME}' already exists in ${PEER_DIR}"
  exit 1
fi

# Create peer directory
mkdir -p "${PEER_DIR}"

# Generate keys
echo "[add-peer] Generating keys for ${PEER_NAME}..."
umask 077
wg genkey | tee "${PEER_DIR}/privatekey" | wg pubkey > "${PEER_DIR}/publickey"

CLIENT_PRIVATE_KEY=$(cat "${PEER_DIR}/privatekey")
CLIENT_PUBLIC_KEY=$(cat "${PEER_DIR}/publickey")

# Get server public key
SERVER_PUBLIC_KEY=$(cat "${PERSIST_CONFIG_DIR}/server/publickey")

# Find next available IP address
echo "[add-peer] Finding next available IP address..."
USED_IPS=$(wg show "${WG_INTERFACE_NAME}" allowed-ips | grep -oE "${WG_NETWORK_PREFIX}\.[0-9]+" | cut -d'.' -f4 | sort -n)

# Start from .2 (since .1 is the server)
NEXT_IP=2
for used in $USED_IPS; do
  if [ "$used" -ge "$NEXT_IP" ]; then
    NEXT_IP=$((used + 1))
  fi
done

# Ensure we don't exceed 254
if [ "$NEXT_IP" -gt 254 ]; then
  echo "Error: No available IP addresses in the ${WG_NETWORK_PREFIX}.0/24 subnet"
  exit 1
fi

PEER_IP="${WG_NETWORK_PREFIX}.${NEXT_IP}"
echo "[add-peer] Assigned IP address: ${PEER_IP}/32"

# Add peer to Wireguard interface
echo "[add-peer] Adding peer to Wireguard interface..."
wg set "${WG_INTERFACE_NAME}" peer "${CLIENT_PUBLIC_KEY}" allowed-ips "${PEER_IP}/32"

# Also add to the server config file for persistence across restarts
echo "[add-peer] Adding peer to server configuration file..."
cat >> "/etc/wireguard/${WG_INTERFACE_NAME}.conf" <<EOF

[Peer]
# ${PEER_NAME}
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${PEER_IP}/32
EOF

# Create client configuration
echo "[add-peer] Creating client configuration..."
cat > "${PEER_DIR}/${WG_INTERFACE_NAME}-client.conf" <<EOF
[Interface]
Address = ${PEER_IP}/32
PrivateKey = ${CLIENT_PRIVATE_KEY}
DNS = ${WG_SERVER_IP}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
AllowedIPs = ${WG_ALLOWED_IPS}
Endpoint = ${WG_ENDPOINT}
PersistentKeepalive = ${WG_PERSISTENT_KEEPALIVE}
EOF

# Generate QR code if available
if command -v qrencode >/dev/null 2>&1; then
  echo "[add-peer] Generating QR code..."
  qrencode -t ansiutf8 < "${PEER_DIR}/${WG_INTERFACE_NAME}-client.conf"
else
  echo "[add-peer] qrencode not found, skipping QR code generation"
fi

echo ""
echo "============================================"
echo "✓ Peer '${PEER_NAME}' added successfully!"
echo "============================================"
echo "Peer IP: ${PEER_IP}/32"
echo "Config file: ${PEER_DIR}/${WG_INTERFACE_NAME}-client.conf"
echo ""
echo "Current Wireguard status:"
wg show "${WG_INTERFACE_NAME}"

