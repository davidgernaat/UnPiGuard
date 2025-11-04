# UnPiGuard = Wireguard + Pi-hole + Unbound + Docker

A free and open-source ad-blocker with integrated recursive DNS resolution in a single Docker container that can be used as a VPN or in your home network.

A normal website-visit exposes that which you read and see to your:
- ✅ **Internet Service Provider (ISP)**: the people giving you internet
- ✅ **DNS provider**: the people giving you the ip-address related to the www.websitename.com
- ✅ **website-owner**: the people hosting the website you visit
- ✅ **third-party advertisers**: the people trying to sell you something while visiting the website
- ❌ **VPS provider**: the company to have your VPN hosted on.

With UnPiGuard you reduce this to:
- ❌ **Internet Service Provider (ISP)**: the people giving you internet
- ❌ **DNS provider**: the people giving you the ip-address related to the www.websitename.com
- ❌ **website-owner**: the people hosting the website you visit
- ❌ **third-party advertisers**: the people trying to sell you something while visiting the website
- ✅ **VPS provider**: the company to have your VPN hosted on.  Choose wisely: https://www.privacytools.io/private-hosting

It spins up creating an Wireguard-peer that is pointed towards the integrated pi-hole add-blocker that uses the integrated Unbound recursive DNS provider to resolve DNS requests: 

- **Wireguard VPN**: Secure VPN tunnel with automatic peer management
- **Pi-hole**: DNS-based ad blocking with web interface
- **Unbound**: Recursive DNS resolver for privacy and security

You can also use it for your home network: just ignore Wireguard and omit opening ports, instead point your router' DNS to the local host-computer ip-address.

## Quick Start

On a VPS, or on a home computer:

1) 📦 Install

git clone https://github.com/davidgernaat/UnPiGuard

docker pull ghcr.io/davidgernaat/unpiguard:latest

docker pull davidgernaat/unpiguard:latest

2) 🔧 Configure yaml-file

Edit `docker-compose.yml`: change <YOUR_VPS_IP> and peer name.

| Variable | Default | Description |
|----------|---------|-------------|
| `PIHOLE_INTERFACE` | `wg0` | Network interface Pi-hole listens on. For Wireguard: wg0. For home-router: local|
| `WG_INTERFACE_NAME` | `wg0` | Interface Wireguard listens too |
| `WG_SERVER_ADDRESS` | `10.66.66.1/24` | Wireguard server IP and subnet |
| `WG_LISTEN_PORT` | `51820` | Wireguard listening port |
| `WG_ENDPOINT` | `<YOUR_VPS_IP>:51820` | Public IP-address |
| `WG_PEER_NAME` | `peer1` | Name of the first peer |
| `WG_PEER_ADDRESS` | `10.66.66.2/32` | IP address of the first peer |
| `WG_ALLOWED_IPS` | `0.0.0.0/0, ::/0` | Traffic to route through VPN |
| `WG_PERSISTENT_KEEPALIVE` | `25` | Keepalive interval in seconds |

3) 🔧 Configure ports

If you want to use it as a VPN:

  Open vps firewall
  ```bash
  ufw allow 51820
  ```

If you want to use it for your home router:

  Point your router' DNS resolution to custum local IP -> find the LAN-ip of your host computer

  In the yaml-file, change the WG_INTERFACE_NAME from wg0 (which is Wireguard) to local (which is your LAN)

4) 🚀 Build & run:

```
If using docker-image:
docker compose up -d

If building from source:
docker compose up -d --build

```

5) :triangular_flag_on_post: VPN peers

The first peer (peer1) is automatically created. Find the configuration at:

```bash
# View config
docker exec unpiguard cat /config/clients/peer1/wg0-client.conf

# Or on host (may need sudo)
cat ./config/clients/peer1/wg0-client.conf
```

The QR code is also displayed in the container logs:

```bash
docker logs unpiguard
```

To add additional Wireguard clients:

```bash
docker exec unpiguard add-peer.sh <peer-name>
```

To list current peers

```bash
docker exec unpiguard wg show wg0
```

To access Pi-hole Web Interface

  - From Wireguard clients: `http://10.66.66.1/admin`
  - Default password: None (set one in Pi-hole settings)
  - HaGeZi Ultimate Blocklist: block ~244,821 Domains, Ads, Affiliate, Tracking, Metrics, Telemetry, Phishing, Malware, Scam, Cryptojacking

6) i Connect and verify

Scan the QR-code with you Wireguard app, or copy peer configuration to you computer. https://www.wireguard.com/quickstart/

Visit https://dnscheck.tools/ to check you public ip-address, your DNS provider, and DNSSEC security.

The public-ip and the DNS-ip should be the same.

Done ✅


## Troubleshooting

### Check Service Status

```bash
# All services
docker exec unpiguard pihole status

# Wireguard
docker exec unpiguard wg show

# Unbound
docker exec unpiguard ss -tulpn | grep 5335

# Pi-hole
docker exec unpiguard ss -tulpn | grep :53
```

## Security Notes

- **Change Pi-hole Web Password**: Access the web interface and set a password
- **Firewall**: Only expose port `51820/udp` publicly when used as VPN
- **Backup Keys**: The `config/` directory contains private keys
- **VPS Security**: Ensure your VPS is properly secured (SSH keys, fail2ban, etc.)

### Scripts

- **`entrypoint.sh`**: Main container startup script
- **`generate-wg-config.sh`**: Creates initial Wireguard configuration
- **`add-peer.sh`**: Adds new Wireguard peers

## License

This setup is provided as-is for educational and personal use.

## Credits

- [Wireguard](https://www.wireguard.com/)
- [Pi-hole](https://pi-hole.net/)
- [Unbound](https://nlnetlabs.nl/projects/unbound/)
- [WireHole](https://github.com/IAmStoxe/wirehole/)
