#!/bin/bash

# ====================================================================
#  BENTENG DNS + MONITORING NOC INSTALLER (PT Media Data Lintas Nusantara Bersatu)
#  Special Thanks to: https://github.com/azhrimzdi/dnsdist-one-click
# ====================================================================

set -e
export DEBIAN_FRONTEND=noninteractive

# Warna untuk output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}Starting Installation...${NC}"

# 1. Update & Install Dependencies
apt-get update -yq
apt-get install -yq dnsdist pdns-recursor freecdb curl wget prometheus prometheus-node-exporter grafana apt-transport-https software-properties-common

# 2. Bebaskan Port 53
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# 3. Konfigurasi PowerDNS Recursor (Port 5353)
cat > /etc/powerdns/recursor.conf <<EOF
local-address=127.0.0.1
local-port=5353
allow-from=127.0.0.0/8
webserver=yes
webserver-address=127.0.0.1
webserver-port=8082
api-key=superrahasia
EOF

# 4. Install & Konfigurasi SmartDNS (Port 5354) + SafeSearch
# (Download script SmartDNS terbaru secara dinamis)
SMARTDNS_URL=$(curl -s https://api.github.com/repos/pymumu/smartdns/releases/latest | grep -o "https://.*x86_64-debian-all.deb" | head -n 1)
wget -qO /tmp/smartdns.deb "$SMARTDNS_URL"
dpkg -i /tmp/smartdns.deb || apt-get install -f -yq

cat > /etc/smartdns/safesearch.conf <<EOF
cname /www.google.com/forcesafesearch.google.com
cname /www.google.co.id/forcesafesearch.google.com
cname /www.youtube.com/restrict.youtube.com
cname /m.youtube.com/restrict.youtube.com
EOF

cat > /etc/smartdns/smartdns.conf <<EOF
bind 127.0.0.1:5354
server 127.0.0.1:5353
conf-file /etc/smartdns/safesearch.conf
cache-size 500000
prefetch-domain yes
EOF

# 5. Konfigurasi dnsdist (Port 53)
CONSOLE_KEY=$(openssl rand -base64 32)
cat > /etc/dnsdist/dnsdist.conf <<EOF
setLocal("0.0.0.0:53", {reusePort=true})
setKey("${CONSOLE_KEY}")
newServer({ address="127.0.0.1:5354", name="SmartDNS", pool="smartdns_pool" })
setServerPolicy(firstAvailable)

local whitelistKVS = newCDBKVStore("/opt/blocklist/whitelist.cdb", 60)
local blocklistKVS = newCDBKVStore("/opt/blocklist/domains.cdb", 60)
local qnameLookupKey = KeyValueLookupKeyQName(false)

addAction(KeyValueStoreLookupRule(whitelistKVS, qnameLookupKey), PoolAction("smartdns_pool"))
addAction(KeyValueStoreLookupRule(blocklistKVS, qnameLookupKey), RCodeAction(DNSRCode.NXDOMAIN))
addAction(AllRule(), PoolAction("smartdns_pool"))

webserver("0.0.0.0:8083")
setWebserverConfig({password="admin123", apiKey="superrahasia", acl="0.0.0.0/0"})
EOF

# 6. Konfigurasi Prometheus (Monitoring)
cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'dnsdist'
    metrics_path: '/metrics'
    basic_auth:
      username: 'admin'
      password: 'admin123'
    static_configs:
      - targets: ['127.0.0.1:8083']
EOF

# 7. Setup Auto-Update Blocklist
mkdir -p /opt/blocklist
# (Script update-blocklist.sh yang sudah kita fix sebelumnya diletakkan di sini)

# 8. Restart & Enable Services
systemctl enable --now pdns-recursor smartdns dnsdist prometheus grafana-server

echo -e "${GREEN}Installation Finished! Access Grafana at port 3000${NC}"
