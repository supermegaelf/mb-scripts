#!/bin/bash

read -p $'\033[32mGrafana, Prometheus and Marzban Exporter domain: \033[0m' DOMAIN

# Запрос настроек для Marzban Exporter
read -p $'\033[32mMarzban panel URL (например, https://your-marzban-panel.com): \033[0m' MARZBAN_URL
read -p $'\033[32mMarzban username: \033[0m' MARZBAN_USERNAME
read -s -p $'\033[32mMarzban password: \033[0m' MARZBAN_PASSWORD
echo

SERVER_IP=$(hostname -I | awk '{print $1}')

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

# Добавляем конфигурацию для Marzban Exporter
cat <<EOF > /etc/nginx/conf.d/marzban-exporter.conf
server {
    server_name marzban-exporter.$DOMAIN;

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

echo "Checking Nginx configuration..."
if nginx -t; then
    systemctl restart nginx
else
    echo "Nginx configuration test failed. Please check /etc/nginx/conf.d/ files."
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
    networks:
      - monitoring

  prometheus:
    image: prom/prometheus
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    restart: unless-stopped
    ports:
      - 127.0.0.1:9090:9090
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prom_data:/prometheus
    networks:
      - monitoring

  marzban-exporter:
    image: marzban-exporter:local
    container_name: marzban-exporter
    restart: unless-stopped
    ports:
      - 127.0.0.1:9100:9090
    environment:
      - MARZBAN_BASE_URL=$MARZBAN_URL
      - MARZBAN_USERNAME=$MARZBAN_USERNAME
      - MARZBAN_PASSWORD=$MARZBAN_PASSWORD
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge

volumes:
  grafana-storage:
    external: true
  prom_data:
    external: true
EOF

cat <<EOF > /opt/monitoring/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
      - targets: []
      scheme: http
      timeout: 10s
      api_version: v2

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 15s
    scrape_timeout: 10s

  - job_name: 'marzban'
    static_configs:
      - targets: ['marzban-exporter:9090']
    scrape_interval: 30s
    scrape_timeout: 10s
EOF

docker volume create grafana-storage
docker volume create prom_data

# Клонируем и собираем Marzban Exporter
cd /opt/monitoring/
git clone https://github.com/kutovoys/marzban-exporter.git
cd marzban-exporter

# Создаем .env файл с настройками
cat <<EOF > .env
MARZBAN_URL=$MARZBAN_URL
MARZBAN_USERNAME=$MARZBAN_USERNAME
MARZBAN_PASSWORD=$MARZBAN_PASSWORD
SCRAPE_INTERVAL=30s
EOF

# Собираем образ
docker build -t marzban-exporter:local .

cd /opt/monitoring/
docker compose -f /opt/monitoring/docker-compose.yml up -d

# Настройка UFW с правильными портами
ufw allow from 172.17.0.0/16 to any port 9100 proto tcp comment "Marzban Exporter - Docker Network 1"
ufw allow from 172.18.0.0/16 to any port 9100 proto tcp comment "Marzban Exporter - Docker Network 2"
ufw allow from 172.19.0.0/16 to any port 9100 proto tcp comment "Marzban Exporter - Docker Network 3"
ufw allow from 127.0.0.1 to any port 9090 proto tcp comment "Local Prometheus Access"
ufw allow from 127.0.0.1 to any port 9100 proto tcp comment "Local Prometheus to Marzban Exporter"
ufw reload

# Ждем немного, чтобы контейнеры запустились
sleep 10

if docker ps | grep -q grafana && docker ps | grep -q prometheus && docker ps | grep -q marzban-exporter; then
    echo "All services are running."
    echo ""
    echo "Services status:"
    echo "- Grafana: $(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep grafana | awk '{print $2}')"
    echo "- Prometheus: $(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep prometheus | awk '{print $2}')"
    echo "- Marzban Exporter: $(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep marzban-exporter | awk '{print $2}')"
else
    echo "Some services failed to start. Checking details..."
    echo ""
    echo "Docker containers:"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    echo ""
    echo "Check logs with:"
    echo "- docker logs prometheus"
    echo "- docker logs grafana"
    echo "- docker logs marzban-exporter"
    exit 1
fi

echo ""
echo "Done! Access URLs:"
echo "- Prometheus: https://prometheus.$DOMAIN"
echo "- Grafana: https://grafana.$DOMAIN"
echo "- Marzban Exporter: https://marzban-exporter.$DOMAIN"
