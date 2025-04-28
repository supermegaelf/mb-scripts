#!/bin/bash

read -p $'\033[32mMarzban Dashboard and SNI: \033[0m' DASHBOARD_DOMAIN
read -p $'\033[32mSub-Site domain: \033[0m' SUB_DOMAIN

apt update && apt install curl gnupg2 ca-certificates lsb-release -y
curl -fsSL https://nginx.org/keys/nginx_signing.key | apt-key add -
echo "deb http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
apt update && apt install nginx -y

mkdir -p /etc/nginx/snippets

cat > /etc/nginx/snippets/ssl.conf << EOF
ssl_certificate /etc/letsencrypt/live/$DASHBOARD_DOMAIN/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/$DASHBOARD_DOMAIN/privkey.pem;
EOF

cat > /etc/nginx/snippets/ssl-sub.conf << EOF
ssl_certificate /etc/letsencrypt/live/$SUB_DOMAIN/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/$SUB_DOMAIN/privkey.pem;
EOF

cat > /etc/nginx/snippets/ssl-params.conf << EOF
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
ssl_session_tickets off;

resolver 8.8.8.8 8.8.4.4;
resolver_timeout 5s;

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
EOF

cat > /etc/nginx/snippets/cloudflare.conf << EOF
#Cloudflare  
  
# - IPv4  
set_real_ip_from 173.245.48.0/20;  
set_real_ip_from 103.21.244.0/22;  
set_real_ip_from 103.22.200.0/22;  
set_real_ip_from 103.31.4.0/22;  
set_real_ip_from 141.101.64.0/18;  
set_real_ip_from 108.162.192.0/18;  
set_real_ip_from 190.93.240.0/20;  
set_real_ip_from 188.114.96.0/20;  
set_real_ip_from 197.234.240.0/22;  
set_real_ip_from 198.41.128.0/17;  
set_real_ip_from 162.158.0.0/15;  
set_real_ip_from 104.16.0.0/13;  
set_real_ip_from 104.24.0.0/14;  
set_real_ip_from 172.64.0.0/13;  
set_real_ip_from 131.0.72.0/22;  
  
# - IPv6  
set_real_ip_from 2400:cb00::/32;  
set_real_ip_from 2606:4700::/32;  
set_real_ip_from 2803:f800::/32;  
set_real_ip_from 2405:b500::/32;  
set_real_ip_from 2405:8100::/32;  
set_real_ip_from 2a06:98c0::/29;  
set_real_ip_from 2c0f:f248::/32;  
  
real_ip_header CF-Connecting-IP;
EOF

rm -f /etc/nginx/conf.d/default.conf

cat > /etc/nginx/conf.d/marzban-dash.conf << EOF
server {
    server_name  dash.$DASHBOARD_DOMAIN;

    listen       8443 ssl;
    http2        on;

    location ~* /(sub|dashboard|api|statics|docs|redoc|openapi.json) {
        proxy_redirect          off;
        proxy_http_version      1.1;
        proxy_pass              http://127.0.0.1:8000;
        proxy_set_header        Upgrade \$http_upgrade;
        proxy_set_header        Connection "upgrade";
        proxy_set_header        Host \$host;
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
    }

    location / {
        return 404;
    }

    include      /etc/nginx/snippets/ssl.conf;
    include      /etc/nginx/snippets/ssl-params.conf;
    include      /etc/nginx/snippets/cloudflare.conf
}
EOF

cat > /etc/nginx/conf.d/sni-site.conf << EOF
server {
    server_name  $DASHBOARD_DOMAIN;

    listen       8444 ssl;
    http2        on;

    gzip         on;

    location / {
        root    /usr/share/nginx/html;
        index   sni.html;
    }

    include      /etc/nginx/snippets/ssl.conf;
    include      /etc/nginx/snippets/ssl-params.conf;
}
EOF

cat > /etc/nginx/conf.d/sub-site.conf << EOF
server {
    server_name  $SUB_DOMAIN;

    listen       8443 ssl;
    http2        on;

    location /sub {
        proxy_redirect          off;
        proxy_http_version      1.1;
        proxy_pass              http://127.0.0.1:8000;
        proxy_set_header        Host \$host;
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
    }

    location / {
        return 401;
    }

    include      /etc/nginx/snippets/ssl-sub.conf;
    include      /etc/nginx/snippets/ssl-params.conf;
    include      /etc/nginx/snippets/cloudflare.conf
}
EOF

wget -q https://raw.githubusercontent.com/supermegaelf/mb-pages/main/sni/sni.html -O /usr/share/nginx/html/sni.html

cat > /tmp/new_http_section << EOF
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    gzip on;
    gzip_disable "msie6";

    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_min_length 256;
    gzip_types
      application/atom+xml
      application/geo+json
      application/javascript
      application/x-javascript
      application/json
      application/ld+json
      application/manifest+json
      application/rdf+xml
      application/rss+xml
      application/xhtml+xml
      application/xml
      font/eot
      font/otf
      font/ttf
      image/svg+xml
      text/css
      text/javascript
      text/plain
      text/xml;

    resolver 8.8.8.8 8.8.4.4;

    include /etc/nginx/conf.d/*.conf;
}
EOF

sed -i '/http {/,/}/d' /etc/nginx/nginx.conf
cat /tmp/new_http_section >> /etc/nginx/nginx.conf
rm /tmp/new_http_section

nginx -t && systemctl restart nginx
marzban restart
