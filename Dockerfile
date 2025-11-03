FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WG_CONFIG_DIR=/etc/wireguard \
    PERSIST_CONFIG_DIR=/config

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       wireguard-tools iproute2 iptables qrencode ca-certificates procps \
       unbound unbound-anchor dns-root-data \
       curl ca-certificates git lighttpd php-cgi php php-common php-sqlite3 \
       iputils-ping netcat-openbsd cron \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "$WG_CONFIG_DIR" "$PERSIST_CONFIG_DIR" "$PERSIST_CONFIG_DIR/clients" \
    && mkdir -p /etc/unbound/unbound.conf.d /etc/pihole

# Pre-create setupVars so unattended install picks it up later in entrypoint
# (These are placeholder values; actual values from docker-compose.yml environment
# variables will be enforced at runtime by entrypoint.sh)
RUN echo "PIHOLE_INTERFACE=wg0" > /etc/pihole/setupVars.conf \
    && echo "DNSMASQ_LISTENING=single" >> /etc/pihole/setupVars.conf \
    && echo "WEBPASSWORD=" >> /etc/pihole/setupVars.conf

# Copy scripts
COPY ./files/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ./files/generate-wg-config.sh /usr/local/bin/generate-wg-config.sh
COPY ./files/add-peer.sh /usr/local/bin/add-peer.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/generate-wg-config.sh /usr/local/bin/add-peer.sh

VOLUME ["/config"]

# UDP 51820 is the default WireGuard port
EXPOSE 51820/udp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
