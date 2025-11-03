#!/usr/bin/env bash
set -euo pipefail

WG_CONFIG_DIR=${WG_CONFIG_DIR:-/etc/wireguard}
PERSIST_CONFIG_DIR=${PERSIST_CONFIG_DIR:-/config}

# Defaults suitable for local testing; replace during real deployment
WG_INTERFACE_NAME=${WG_INTERFACE_NAME:-wg0}
WG_SERVER_ADDRESS=${WG_SERVER_ADDRESS:-10.66.66.1/24}
WG_LISTEN_PORT=${WG_LISTEN_PORT:-51820}
WG_PEER_NAME=${WG_PEER_NAME:-peer1}
WG_PEER_ADDRESS=${WG_PEER_ADDRESS:-10.66.66.2/32}
WG_ALLOWED_IPS=${WG_ALLOWED_IPS:-0.0.0.0/0, ::/0}
WG_ENDPOINT=${WG_ENDPOINT:-your.public.ip.example.com:${WG_LISTEN_PORT}}
WG_PERSISTENT_KEEPALIVE=${WG_PERSISTENT_KEEPALIVE:-25}

mkdir -p "${WG_CONFIG_DIR}" "${PERSIST_CONFIG_DIR}" "${PERSIST_CONFIG_DIR}/server" "${PERSIST_CONFIG_DIR}/clients/${WG_PEER_NAME}"

SERVER_PRIV_KEY_FILE="${PERSIST_CONFIG_DIR}/server/privatekey"
SERVER_PUB_KEY_FILE="${PERSIST_CONFIG_DIR}/server/publickey"
CLIENT_PRIV_KEY_FILE="${PERSIST_CONFIG_DIR}/clients/${WG_PEER_NAME}/privatekey"
CLIENT_PUB_KEY_FILE="${PERSIST_CONFIG_DIR}/clients/${WG_PEER_NAME}/publickey"

# Generate keys if missing
if [ ! -f "${SERVER_PRIV_KEY_FILE}" ]; then
  umask 077
  wg genkey | tee "${SERVER_PRIV_KEY_FILE}" | wg pubkey > "${SERVER_PUB_KEY_FILE}"
fi
if [ ! -f "${CLIENT_PRIV_KEY_FILE}" ]; then
  umask 077
  wg genkey | tee "${CLIENT_PRIV_KEY_FILE}" | wg pubkey > "${CLIENT_PUB_KEY_FILE}"
fi

SERVER_PRIVATE_KEY=$(cat "${SERVER_PRIV_KEY_FILE}")
SERVER_PUBLIC_KEY=$(cat "${SERVER_PUB_KEY_FILE}")
CLIENT_PRIVATE_KEY=$(cat "${CLIENT_PRIV_KEY_FILE}")
CLIENT_PUBLIC_KEY=$(cat "${CLIENT_PUB_KEY_FILE}")

# Server configuration
cat > "${WG_CONFIG_DIR}/${WG_INTERFACE_NAME}.conf" <<EOF
[Interface]
Address = ${WG_SERVER_ADDRESS}
ListenPort = ${WG_LISTEN_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
# Enable forwarding and NAT if needed (adjust to your host network later)
# PostUp = sysctl -w net.ipv4.ip_forward=1; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# ${WG_PEER_NAME}
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${WG_PEER_ADDRESS}
EOF

# Client configuration
# Extract server IP (without CIDR) for DNS setting
WG_SERVER_IP=${WG_SERVER_ADDRESS%%/*}

cat > "${PERSIST_CONFIG_DIR}/clients/${WG_PEER_NAME}/${WG_INTERFACE_NAME}-client.conf" <<EOF
[Interface]
Address = ${WG_PEER_ADDRESS}
PrivateKey = ${CLIENT_PRIVATE_KEY}
DNS = ${WG_SERVER_IP}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
AllowedIPs = ${WG_ALLOWED_IPS}
Endpoint = ${WG_ENDPOINT}
PersistentKeepalive = ${WG_PERSISTENT_KEEPALIVE}
EOF

# Also render a QR for mobile clients
if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ansiutf8 < "${PERSIST_CONFIG_DIR}/clients/${WG_PEER_NAME}/${WG_INTERFACE_NAME}-client.conf" || true
fi

echo "[generate-wg-config] Server config: ${WG_CONFIG_DIR}/${WG_INTERFACE_NAME}.conf"
echo "[generate-wg-config] Client config: ${PERSIST_CONFIG_DIR}/clients/${WG_PEER_NAME}/${WG_INTERFACE_NAME}-client.conf"
