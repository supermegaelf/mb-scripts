#!/bin/bash

echo -e "\033[32mChoose inbound to update:\033[0m"
echo "1) VLESS Reality Steal Oneself"
echo "2) VLESS WS"
read -p $'\033[32mEnter your choice (1 or 2): \033[0m' choice

if [ "$choice" == "1" ]; then
    echo -e "\033[32mChoose remark for VLESS Reality Steal Oneself:\033[0m"
    echo "1) 🇩🇪 Быстрый 🚀"
    echo "2) 🇷🇺 Быстрый 🚀"
    read -p $'\033[32mEnter your choice (1 or 2): \033[0m' remark_choice
    if [ "$remark_choice" == "1" ]; then
        remark="🇩🇪 Быстрый 🚀"
    elif [ "$remark_choice" == "2" ]; then
        remark="🇷🇺 Быстрый 🚀"
    else
        echo "Invalid choice for remark! Please select 1 or 2."
        exit 1
    fi
    read -p $'\033[32mNode domain (e.g., example.com): \033[0m' address_domain
    read -p $'\033[32mMain domain (e.g., example.com): \033[0m' sni_domain
elif [ "$choice" == "2" ]; then
    echo -e "\033[32mChoose remark for VLESS WS:\033[0m"
    echo "1) 🇩🇪 Устойчивый 🛡️"
    echo "2) 🇷🇺 Устойчивый 🛡️"
    read -p $'\033[32mEnter your choice (1 or 2): \033[0m' remark_choice
    if [ "$remark_choice" == "1" ]; then
        remark="🇩🇪 Устойчивый 🛡️"
    elif [ "$remark_choice" == "2" ]; then
        remark="🇷🇺 Устойчивый 🛡️"
    else
        echo "Invalid choice for remark! Please select 1 or 2."
        exit 1
    fi
    read -p $'\033[32mNode domain (e.g., cdn.example.com): \033[0m' address_domain
    read -p $'\033[32mPath (e.g., /2bMC3f7wFbafrCi): \033[0m' user_path
    full_path="${user_path}?ed=2560"
else
    echo "Invalid choice! Please select 1 or 2."
    exit 1
fi

read -p $'\033[32mMySQL password: \033[0m' MySQL_password

container_id=$(docker ps -q -f ancestor=mariadb:lts | head -n 1)
echo "Container ID: $container_id"

if [ -z "$container_id" ]; then
    echo "Container with image mariadb:lts not found or not running."
    exit 1
fi

if [ "$choice" == "1" ]; then
    docker exec -it "$container_id" bash -c "mariadb --default-character-set=utf8mb4 -u marzban -p${MySQL_password} marzban -e \"
    UPDATE hosts 
    SET 
        remark = '${remark}',
        address = '${address_domain}',
        port = 443,
        sni = '${sni_domain}',
        fingerprint = 'chrome'
    WHERE 
        inbound_tag = 'VLESS Reality Steal Oneself';
    \""
elif [ "$choice" == "2" ]; then
    docker exec -it "$container_id" bash -c "mariadb --default-character-set=utf8mb4 -u marzban -p${MySQL_password} marzban -e \"
    UPDATE hosts 
    SET 
        remark = '${remark}',
        address = '${address_domain}',
        port = 8443,
        sni = '${address_domain}',
        host = '${address_domain}',
        security = 'tls',
        fingerprint = 'chrome',
        path = '${full_path}'
    WHERE 
        inbound_tag = 'VLESS WS';
    \""
fi

if [ $? -eq 0 ]; then
    echo "Update is done."
else
    echo "Error occurred during update. Check database logs for details."
    exit 1
fi

marzban restart
