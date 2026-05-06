#!/bin/bash

# ====================================================================
#  BENTENG DNS + MONITORING NOC INSTALLER (Ubuntu 22.04)
#  PT Media Data Lintas Nusantara Bersatu
#  Special Thanks to: https://github.com/azhrimzdi/dnsdist-one-click
# ====================================================================

set -e
export DEBIAN_FRONTEND=noninteractive

# Warna untuk output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}Starting Installation for Ubuntu 22.04...${NC}"

# ==========================================
# 1. Update & Install Dependencies Dasar
# ==========================================
echo -e "${YELLOW}Installing base dependencies...${NC}"
apt-get update -yq
apt-get install -yq dnsdist pdns-recursor freecdb curl wget prometheus prometheus-node-exporter apt-transport-https software-properties-common gnupg2

# Install Grafana dari Repositori Resmi
mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
apt-get update -yq
apt-get install -yq grafana

# ==========================================
# 2. Bebaskan Port 53 dari systemd-resolved
# ==========================================
echo -e "${YELLOW}Freeing up Port 53...${NC}"
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# ==========================================
# 3. Konfigurasi PowerDNS Recursor (Port 5353)
# ==========================================
echo -e "${YELLOW}Configuring PowerDNS Recursor...${NC}"
cat > /etc/powerdns/recursor.conf <<EOF
local-address=127.0.0.1
local-port=5353
allow-from=127.0.0.0/8
webserver=yes
webserver-address=127.0.0.1
webserver-port=8082
api-key=superrahasia
# Bypass ISP Port 53 Block: Forward to reliable upstreams
forward-zones-recurse=.=8.8.8.8, 1.1.1.1
EOF

# ==========================================
# 4. Install & Konfigurasi SmartDNS (Port 5354)
# ==========================================
echo -e "${YELLOW}Installing and Configuring SmartDNS...${NC}"
SMARTDNS_URL=$(curl -s https://api.github.com/repos/pymumu/smartdns/releases/latest | grep -o "https://.*x86_64-debian-all.deb" | head -n 1)
wget -qO /tmp/smartdns.deb "$SMARTDNS_URL"
dpkg -i /tmp/smartdns.deb || apt-get install -f -yq

# Setup SafeSearch
cat > /etc/smartdns/safesearch.conf <<EOF
cname /www.google.com/forcesafesearch.google.com
cname /www.google.co.id/forcesafesearch.google.com
cname /www.youtube.com/restrict.youtube.com
cname /m.youtube.com/restrict.youtube.com
EOF

# Konfigurasi SmartDNS Utama (Pakai DoT/TLS anti blokir ISP)
cat > /etc/smartdns/smartdns.conf <<EOF
bind 127.0.0.1:5354
conf-file /etc/smartdns/safesearch.conf
cache-size 500000
prefetch-domain yes
serve-expired yes
serve-expired-ttl 86400

# Upstream 1: Local PDNS Recursor
server 127.0.0.1:5353

# Upstream 2: Quad9 DoT (Sangat Cepat)
server-tls 9.9.9.9:853 -host-name dns.quad9.net

# Upstream 3: Cloudflare DoT
server-tls 1.1.1.1:853 -host-name cloudflare-dns.com
server-tls 1.0.0.1:853 -host-name cloudflare-dns.com
EOF

# ==========================================
# 5. Konfigurasi dnsdist (Port 53)
# ==========================================
echo -e "${YELLOW}Configuring dnsdist Layer 1...${NC}"
CONSOLE_KEY=$(openssl rand -base64 32)
cat > /etc/dnsdist/dnsdist.conf <<EOF
setLocal("0.0.0.0:53", {reusePort=true})
setKey("${CONSOLE_KEY}")

-- Define Backend SmartDNS
newServer({ address="127.0.0.1:5354", name="SmartDNS", pool="smartdns_pool" })
setServerPolicy(firstAvailable)

-- Setup Packet Cache (Attached to smartdns_pool)
pc = newPacketCache(10000000, {maxTTL=86400, minTTL=0, temporaryFailureTTL=60, staleTTL=60, dontAge=false})
getPool("smartdns_pool"):setCache(pc)

-- Blocklist & Whitelist Setup
local whitelistKVS = newCDBKVStore("/opt/blocklist/whitelist.cdb", 60)
local blocklistKVS = newCDBKVStore("/opt/blocklist/domains.cdb", 60)
local qnameLookupKey = KeyValueLookupKeyQName(false)

addAction(KeyValueStoreLookupRule(whitelistKVS, qnameLookupKey), PoolAction("smartdns_pool"))
addAction(KeyValueStoreLookupRule(blocklistKVS, qnameLookupKey), RCodeAction(DNSRCode.NXDOMAIN))

-- Default Action
addAction(AllRule(), PoolAction("smartdns_pool"))

-- Webserver & API for Prometheus
webserver("0.0.0.0:8083")
setWebserverConfig({password="admin123", apiKey="superrahasia", acl="0.0.0.0/0"})
EOF

# ==========================================
# 6. Setup Auto-Update Blocklist & Whitelist
# ==========================================
echo -e "${YELLOW}Setting up Blocklist System...${NC}"
mkdir -p /opt/blocklist

# Buat file default agar CDB tidak error saat start pertama
echo "google.com" > /opt/blocklist/custom_whitelist.txt
echo "https://raw.githubusercontent.com/faizsho/Whitelist-IP/refs/heads/main/whitelist_domain.txt" > /opt/blocklist/whitelist_sources.txt
echo "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.plus.txt" > /opt/blocklist/sources.txt

# Script Updater yang sudah kebal karakter \r (Windows)
cat > /opt/blocklist/update-blocklist.sh <<'EOF'
#!/bin/bash
WORKDIR="/opt/blocklist"

build_cdb() {
  local SOURCE_FILE=$1
  local CUSTOM_FILE=$2
  local FINAL_CDB=$3
  local TYPE=$4
  local RAW="$WORKDIR/raw_$TYPE.tmp"
  local NEW="$WORKDIR/new_$TYPE.tmp"
  local CDB_INPUT="$WORKDIR/input_$TYPE.tmp"
  local CDB_TMP="$WORKDIR/tmp_$TYPE.cdb"
  
  rm -f "$RAW" "$NEW" "$CDB_INPUT" "$CDB_TMP"
  
  if [ -f "$SOURCE_FILE" ]; then
    while IFS= read -r url || [ -n "$url" ]; do
      url=$(echo "$url" | tr -d '\r' | xargs)
      [[ -z "$url" || "$url" =~ ^# ]] && continue
      curl -L --retry 3 --max-time 60 -s "$url" >> "$RAW"
      echo "" >> "$RAW"
    done < "$SOURCE_FILE"
  fi
  
  if [ -f "$CUSTOM_FILE" ]; then 
    cat "$CUSTOM_FILE" | tr -d '\r' >> "$RAW"
  fi
  
  if [ -s "$RAW" ]; then
    grep -Eo '([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})' "$RAW" | sed 's/^\.//' | tr '[:upper:]' '[:lower:]' | sort -u > "$NEW"
    awk '{ print "+" length($0) ",1:" $0 "->1" } END { print "" }' "$NEW" > "$CDB_INPUT"
    cdbmake "$CDB_TMP" "$WORKDIR/cdbmake_$TYPE.tmp" < "$CDB_INPUT"
    mv "$CDB_TMP" "$FINAL_CDB"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$TYPE] Sukses: $(wc -l < $NEW) domains."
  fi
}

build_cdb "$WORKDIR/whitelist_sources.txt" "$WORKDIR/custom_whitelist.txt" "$WORKDIR/whitelist.cdb" "whitelist"
build_cdb "$WORKDIR/sources.txt" "" "$WORKDIR/domains.cdb" "blocklist"

dnsdist -c -e "reloadConfig" 2>/dev/null || true
EOF

chmod +x /opt/blocklist/update-blocklist.sh

# Generate CDB pertama kali
bash /opt/blocklist/update-blocklist.sh

# Cronjob tiap jam 3 pagi
(crontab -l 2>/dev/null; echo "0 3 * * * bash /opt/blocklist/update-blocklist.sh >> /var/log/update-blocklist.log 2>&1") | crontab -

# ==========================================
# 7. Konfigurasi Prometheus & Auth
# ==========================================
echo -e "${YELLOW}Configuring Prometheus...${NC}"
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

# ==========================================
# 8. Restart & Enable All Services
# ==========================================
echo -e "${YELLOW}Restarting Services...${NC}"
systemctl enable --now pdns-recursor smartdns dnsdist prometheus grafana-server
systemctl restart pdns-recursor smartdns dnsdist prometheus grafana-server

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN} INSTALLATION FINISHED SUCCESSFULLY!${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Grafana Dashboard : http://<YOUR_IP>:3000 (admin/admin)"
echo -e "dnsdist Web UI    : http://<YOUR_IP>:8083 (admin123)"
echo -e "DNS Server is ready on Port 53."
