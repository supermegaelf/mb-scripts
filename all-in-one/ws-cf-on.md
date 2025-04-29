### 1. DNS

| Type  | Name          | IPv4 address      | Proxy status |
| ----- | ------------- | ----------------- | ------------ |
| A     | cdn           | server_public_ip  | ON           |

### 2. Nginx

```
nano /etc/nginx/snippets/cloudflare.conf
```

Вставить:

```
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
```

CDN-камуфляж:

```
nano /etc/nginx/conf.d/cdn-site.conf
```

Вставить:

```
    include      /etc/nginx/snippets/cloudflare.conf;
```

Перезапустить Nginx:

```
nginx -t && systemctl restart nginx
```

### 3. Ограничить доступ к VLESS WS через CF

```
nano /root/cf-ufw.sh
```

Вставить:

```
#!/bin/sh

while ufw status | grep -q 'Cloudflare.*8443'; do
    ufw status | grep 'Cloudflare' | grep '8443' | head -n 1 | awk '{print $5}' | xargs -I {} ufw --force delete allow from {} to any port 8443 proto tcp
done

if ! curl -s https://www.cloudflare.com/ips-v4 -o /tmp/cf_ips; then
    echo "Error: Failed to download IPv4 ranges" >&2
    exit 1
fi
echo "" >> /tmp/cf_ips
if ! curl -s https://www.cloudflare.com/ips-v6 >> /tmp/cf_ips; then
    echo "Error: Failed to download IPv6 ranges" >&2
    exit 1
fi

for ip in $(cat /tmp/cf_ips); do
    ufw allow from "$ip" to any port 8443 proto tcp comment 'Cloudflare'
done

rm -f /tmp/cf_ips

ufw reload
```

```
chmod +x /root/cf-ufw.sh
bash cf-ufw.sh
```

### 4. Удалить старые правила UFW:

```
ufw status | grep -q '8443/tcp.*Anywhere' && ufw delete allow 8443/tcp
ufw status | grep -q '8443/tcp (v6).*Anywhere (v6)' && ufw delete allow 8443/tcp proto ipv6
```

### 5. Добавить обновление правил в cron:

```
if ! grep -q "/root/cf-ufw.sh" /etc/crontab; then
    echo "5 3 * * * root /root/cf-ufw.sh &> /dev/null" | sudo tee -a /etc/crontab
fi
systemctl restart cron
```
