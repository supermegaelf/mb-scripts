#!/bin/bash

read -p $'\033[32mMain domain: \033[0m' domain

cat > /etc/nginx/conf.d/redirect.conf << EOL
server {
    listen 443 ssl;
    server_name redirect.$domain;

    root /var/www/redirect;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    include /etc/nginx/snippets/ssl.conf;
    include /etc/nginx/snippets/ssl-params.conf;
}
EOL

nginx -t && systemctl restart nginx

sudo mkdir -p /var/www/redirect
wget -q https://raw.githubusercontent.com/supermegaelf/sub-redirect/main/index.html -O /var/www/redirect/index.html

sudo chown -R www-data:www-data /var/www/redirect
sudo chmod -R 755 /var/www/redirect

echo "Replace 'example.com' with '$domain' in sub file: /var/lib/marzban/templates/subscription/index.html"
read -p $'\033[32mProceed? (y/n): \033[0m' confirm

if [ "$confirm" != "y" ]; then
    echo "Operation aborted."
    exit 1
fi

marzban restart
