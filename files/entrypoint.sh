#!/usr/bin/env bash
set -euo pipefail

# Ensure /dev/net/tun exists
if [ ! -c /dev/net/tun ]; then
  mkdir -p /dev/net/tun || true
  mknod /dev/net/tun c 10 200 || true
fi

# Generate configs if needed
/usr/local/bin/generate-wg-config.sh

# Enable forwarding and NAT for internet access through VPS
OUT_IF=${WG_OUT_INTERFACE:-eth0}

# Enable IPv4 forwarding (ignore if not permitted; compose sysctls should handle it)
(sysctl -w net.ipv4.ip_forward=1 >/dev/null) || true

# Set up NAT (MASQUERADE) and forwarding rules if not present
iptables -t nat -C POSTROUTING -o "$OUT_IF" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o "$OUT_IF" -j MASQUERADE
iptables -C FORWARD -i "$OUT_IF" -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "$OUT_IF" -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -C FORWARD -i wg0 -o "$OUT_IF" -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i wg0 -o "$OUT_IF" -j ACCEPT

# Bring up WireGuard interface
if [ -f "/etc/wireguard/wg0.conf" ]; then
  echo "[entrypoint] Bringing up wg0"
  wg-quick up wg0 || (echo "Failed to bring up wg0" && cat /etc/wireguard/wg0.conf && exit 1)
else
  echo "[entrypoint] Missing /etc/wireguard/wg0.conf" >&2
  exit 1
fi

# Derive WG IP (strip CIDR)
WG_IP=${WG_SERVER_ADDRESS:-10.66.66.1/24}
WG_IP=${WG_IP%%/*}

# ---- Unbound ----
cat > /etc/unbound/unbound.conf.d/pi-hole.conf <<'CONF'
server:
    verbosity: 0

    interface: __BIND_IP__
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes

    do-ip6: yes
    prefer-ip6: no

    #root-hints: "/var/lib/unbound/root.hints"

    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: no

    edns-buffer-size: 1232
    prefetch: yes
    num-threads: 1
    so-rcvbuf: 1m

    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10

    private-address: 192.0.2.0/24
    private-address: 198.51.100.0/24
    private-address: 203.0.113.0/24
    private-address: 255.255.255.255/32
    private-address: 2001:db8::/32

    # Allow queries from localhost and Wireguard subnet
    access-control: 127.0.0.0/8 allow
    access-control: 10.66.66.0/24 allow
    access-control: 0.0.0.0/0 refuse
CONF

sed -i "s/__BIND_IP__/${WG_IP}/" /etc/unbound/unbound.conf.d/pi-hole.conf

mkdir -p /var/lib/unbound
if [ ! -f /var/lib/unbound/root.key ]; then
  unbound-anchor -a /var/lib/unbound/root.key || true
fi

if unbound-checkconf -f /etc/unbound/unbound.conf; then
  echo "[entrypoint] Starting unbound bound to ${WG_IP}:5335"
  (unbound -d -c /etc/unbound/unbound.conf &) 
else
  echo "[entrypoint] Unbound configuration invalid" >&2
  unbound-checkconf -f /etc/unbound/unbound.conf || true
fi

# ---- Pi-hole ----
# Use environment variable for Pi-hole interface (defaults to wg0 if not set)
PIHOLE_INTERFACE=${PIHOLE_INTERFACE:-wg0}

mkdir -p /etc/pihole
cat > /etc/pihole/setupVars.conf <<EOV
PIHOLE_INTERFACE=${PIHOLE_INTERFACE}
IPV4_ADDRESS=${WG_IP}
DNSMASQ_LISTENING=single
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
PIHOLE_DNS_1=${WG_IP}#5335
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
EOV

if ! command -v pihole >/dev/null 2>&1; then
  echo "[entrypoint] Installing Pi-hole (unattended)"
  curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended || true
fi

# Enforce Pi-hole settings
sed -i "s/^PIHOLE_INTERFACE=.*/PIHOLE_INTERFACE=${PIHOLE_INTERFACE}/" /etc/pihole/setupVars.conf || true
sed -i "s/^PIHOLE_DNS_1=.*/PIHOLE_DNS_1=${WG_IP}#5335/" /etc/pihole/setupVars.conf || true
sed -i "s/^DNSMASQ_LISTENING=.*/DNSMASQ_LISTENING=single/" /etc/pihole/setupVars.conf || true

# Lighttpd binding via conf-enabled snippet (idempotent)
mkdir -p /etc/lighttpd/conf-available /etc/lighttpd/conf-enabled
cat > /etc/lighttpd/conf-available/10-bind-wg0.conf <<EOF
server.bind = "${WG_IP}"
EOF
ln -sf ../conf-available/10-bind-wg0.conf /etc/lighttpd/conf-enabled/10-bind-wg0.conf

# Remove any server.bind lines in main config to avoid duplicates
sed -i '/^server.bind\s*=\s*".*"/d' /etc/lighttpd/lighttpd.conf || true

# Add HaGeZi Ultimate blocklist to adlists
echo "[entrypoint] Adding HaGeZi Ultimate blocklist"
HAGEZI_URL="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/ultimate.txt"
if ! grep -q "$HAGEZI_URL" /etc/pihole/adlists.list 2>/dev/null; then
  echo "$HAGEZI_URL" >> /etc/pihole/adlists.list
fi

# Initialize gravity database
pihole -g || true

# Create log directories and files before starting FTL
mkdir -p /var/log/pihole /etc/pihole/config_backups
touch /var/log/pihole/FTL.log /var/log/pihole/pihole.log
chmod 644 /var/log/pihole/*.log
chown -R root:www-data /var/log/pihole

# Start FTL to generate pihole.toml if it doesn't exist
echo "[entrypoint] Starting pihole-FTL"
pihole-FTL &
FTL_PID=$!
sleep 5

# Now configure upstream DNS in pihole.toml (created by FTL on first run)
if [ -f /etc/pihole/pihole.toml ]; then
  echo "[entrypoint] Configuring upstream DNS in pihole.toml"
  sed -i 's/upstreams = \[\]/upstreams = ["'"${WG_IP}"'#5335"]/' /etc/pihole/pihole.toml || true
  
  # Restart FTL to apply the upstream DNS configuration
  echo "[entrypoint] Restarting FTL to apply upstream DNS config"
  pkill -x pihole-FTL
  sleep 2
  pihole-FTL &
  sleep 3
else
  echo "[entrypoint] WARNING: pihole.toml not found after FTL startup"
fi

# Validate and start lighttpd
if lighttpd -tt -f /etc/lighttpd/lighttpd.conf; then
  pkill -x lighttpd || true
  (lighttpd -f /etc/lighttpd/lighttpd.conf &) || true
fi

# Verify services are running
echo "[entrypoint] Verifying services..."
pihole status || true

# Show status
wg show

exec tail -f /dev/null
