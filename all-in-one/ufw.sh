#!/bin/bash

apt install ufw -y

ufw allow 443/tcp comment "HTTPS (Reality)"
ufw allow 22/tcp comment "SSH"

ufw enable

mkdir -p /root/scripts && cd /root/scripts

wget -q https://raw.githubusercontent.com/supermegaelf/mb-scripts/main/all-in-one/cf-ufw.sh -O /root/scripts/cf-ufw.sh

chmod +x /root/scripts/cf-ufw.sh

bash /root/scripts/cf-ufw.sh

echo "@daily root /root/scripts/cf-ufw.sh &> /dev/null" | sudo tee -a /etc/crontab

ufw reload
