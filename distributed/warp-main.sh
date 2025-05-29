#!/bin/bash

wget -q -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh w <<EOF
1
1

1
EOF

cat > "/var/lib/marzban/xray_config.json" <<EOF
{
  "log": {
    "access": "/var/lib/marzban/access.log",
    "error": "/var/lib/marzban/error.log",
    "loglevel": "debug",
    "dnsLog": true
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "ip": ["geoip:private"],
        "outboundTag": "BLOCK",
        "type": "field"
      },
      {
        "type": "field",
        "outboundTag": "IPv4",
        "domain": ["geosite:google"]
      },
      {
        "protocol": ["bittorrent"],
        "outboundTag": "BLOCK",
        "type": "field"
      },
      {
        "outboundTag": "WARP",
        "domain": [
          "geosite:reddit",
          "geosite:openai",
          "geosite:tiktok",
          "full:*.vsco.co",
          "domain:perplexity.ai",
          "domain:spotify.com"
        ],
        "type": "field"
      }
    ]
  },
  "inbounds": [
    {
      "tag": "Shadowsocks TCP",
      "listen": "0.0.0.0",
      "port": 1080,
      "protocol": "shadowsocks",
      "settings": {
        "clients": [],
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "DIRECT"
    },
    {
      "protocol": "blackhole",
      "tag": "BLOCK"
    },
    {
      "tag": "IPv4",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "ForceIPv4"
      }
    },
    {
      "tag": "WARP",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 40000
          }
        ]
      }
    }
  ]
}
EOF

marzban restart
