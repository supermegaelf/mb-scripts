#!/bin/bash

read -p $'\033[32mDomain for Grafana, Prometheus, Node Exporter and Marzban Exporter: \033[0m' DOMAIN
read -p $'\033[32mMarzban panel URL (e.g., https://dash.panel.com): \033[0m' MARZBAN_URL
read -p $'\033[32mMarzban username: \033[0m' MARZBAN_USER
read -s -p $'\033[32mMarzban password: \033[0m' MARZBAN_PASS
echo

SERVER_IP=$(hostname -I | awk '{print $1}')

# Nginx configurations
cat <<EOF > /etc/nginx/conf.d/grafana.conf
server {
    listen 8444 ssl;
    server_name grafana.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    include /etc/nginx/snippets/ssl.conf;
    include /etc/nginx/snippets/ssl-params.conf;
}
EOF

cat <<EOF > /etc/nginx/conf.d/prometheus.conf
server {
    server_name prometheus.$DOMAIN;

    listen 8444 ssl;
    http2 on;

    location / {
        proxy_pass http://127.0.0.1:9090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    include /etc/nginx/snippets/ssl.conf;
    include /etc/nginx/snippets/ssl-params.conf;
}
EOF

cat <<EOF > /etc/nginx/conf.d/node-exporter.conf
server {
    server_name node-exporter.$DOMAIN;

    listen 8444 ssl;
    http2 on;

    location / {
        proxy_pass http://127.0.0.1:9100;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    include /etc/nginx/snippets/ssl.conf;
    include /etc/nginx/snippets/ssl-params.conf;
}
EOF

cat <<EOF > /etc/nginx/conf.d/marzban-exporter.conf
server {
    server_name marzban-exporter.$DOMAIN;

    listen 8444 ssl;
    http2 on;

    location / {
        proxy_pass http://127.0.0.1:3010;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    include /etc/nginx/snippets/ssl.conf;
    include /etc/nginx/snippets/ssl-params.conf;
}
EOF

echo "Checking Nginx configuration..."
if nginx -t; then
    systemctl restart nginx
else
    echo "Error in Nginx configuration. Check files in /etc/nginx/conf.d/."
    exit 1
fi

mkdir -p /opt/monitoring/prometheus

cat <<EOF > /opt/monitoring/docker-compose.yml
services:
  grafana:
    image: grafana/grafana
    container_name: grafana
    restart: unless-stopped
    ports:
     - 127.0.0.1:3000:3000
    volumes:
      - grafana-storage:/var/lib/grafana

  prometheus:
    image: prom/prometheus
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prom_data:/prometheus

  marzban-exporter:
    image: kutovoys/marzban-exporter
    container_name: marzban-exporter
    restart: unless-stopped
    environment:
      - MARZBAN_BASE_URL=$MARZBAN_URL
      - MARZBAN_USERNAME=$MARZBAN_USER
      - MARZBAN_PASSWORD=$MARZBAN_PASS
    ports:
      - 127.0.0.1:3010:9090

volumes:
  grafana-storage:
    external: true
  prom_data:
    external: true
EOF

cat <<EOF > /opt/monitoring/prometheus/prometheus.yml
global:
  scrape_interval: 20s
  scrape_timeout: 15s
  evaluation_interval: 20s
alerting:
  alertmanagers:
    - static_configs:
      - targets: []
      scheme: http
      timeout: 10s
      api_version: v2
scrape_configs:
  - job_name: prometheus
    honor_timestamps: true
    scrape_interval: 15s
    scrape_timeout: 10s
    metrics_path: /metrics
    scheme: http
    static_configs:
      - targets:
        - localhost:9090
  - job_name: node-exporter
    static_configs:
      - targets: ['127.0.0.1:9100']
  - job_name: marzban-exporter
    static_configs:
      - targets: ['127.0.0.1:3010']
EOF

docker volume create grafana-storage
docker volume create prom_data

# Install Node Exporter
cd /opt/monitoring/
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz
tar xvf node_exporter-1.8.1.linux-amd64.tar.gz
sudo cp node_exporter-1.8.1.linux-amd64/node_exporter /usr/local/bin
rm -rf node_exporter-1.8.1.linux-amd64 node_exporter-1.8.1.linux-amd64.tar.gz

# Check and create node_exporter user
if ! id "node_exporter" >/dev/null 2>&1; then
    sudo useradd --no-create-home --shell /bin/false node_exporter
fi
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

cd /opt/monitoring/
docker compose -f /opt/monitoring/docker-compose.yml up -d

ufw allow from 172.17.0.0/16 to any port 9100 proto tcp comment "Node Exporter - Docker Network 1"
ufw allow from 172.18.0.0/16 to any port 9100 proto tcp comment "Node Exporter - Docker Network 2"
ufw allow from 127.0.0.1 to any port 9100 proto tcp comment "Local Prometheus to Node Exporter"
ufw allow from 127.0.0.1 to any port 9090 proto tcp comment "Local Prometheus Access"
ufw allow from 127.0.0.1 to any port 3010 proto tcp comment "Local Prometheus to Marzban Exporter"
ufw reload

if systemctl is-active node_exporter >/dev/null && docker ps | grep -q grafana && docker ps | grep -q prometheus && docker ps | grep -q marzban-exporter; then
    echo "All services are running."
else
    echo "Some services failed to start. Check 'systemctl status node_exporter' and 'docker ps' for details."
    exit 1
fi

echo "Done."
echo "Prometheus: https://prometheus.$DOMAIN"
echo "Grafana: https://grafana.$DOMAIN"
echo "Marzban Exporter: https://marzban-exporter.$DOMAIN"
