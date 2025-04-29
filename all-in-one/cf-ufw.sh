#!/bin/sh

# Fetch latest IP range lists (both v4 and v6) from Cloudflare
curl -s https://www.cloudflare.com/ips-v4 -o /tmp/cf_ips
echo "" >> /tmp/cf_ips
curl -s https://www.cloudflare.com/ips-v6 >> /tmp/cf_ips

# Restrict traffic to ports 8443 (TCP) & 9200 (TCP)
# UFW will skip a subnet if a rule already exists (which it probably does)
for ip in $(cat /tmp/cf_ips); do ufw allow from "$ip" to any port 8443,9200 proto tcp comment 'Cloudflare'; done

# Delete downloaded lists from above
rm /tmp/cf_ips

# Need to reload UFW before new rules take effect
ufw reload
