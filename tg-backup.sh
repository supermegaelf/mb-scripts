#!/bin/bash

MYSQL_USER=""
MYSQL_PASSWORD=""
TG_BOT_TOKEN=""
TG_CHAT_ID=""

if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
    read -p $'\033[32mMySQL username (default is marzban, press Enter to use default): \033[0m' MYSQL_USER
    MYSQL_USER=${MYSQL_USER:-marzban}
    read -sp $'\033[32mMySQL password: \033[0m' MYSQL_PASSWORD
    echo
    read -p $'\033[32mTelegram Bot Token: \033[0m' TG_BOT_TOKEN
    read -p $'\033[32mTelegram Chat ID: \033[0m' TG_CHAT_ID

    if [ -z "$MYSQL_USER" ]; then
        echo "Error: MySQL username cannot be empty"
        exit 1
    fi
    if [ -z "$MYSQL_PASSWORD" ]; then
        echo "Error: MySQL password cannot be empty"
        exit 1
    fi
    if [[ ! "$TG_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        echo "Error: Invalid Telegram Bot Token format"
        exit 1
    fi
    if [[ ! "$TG_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
        echo "Error: Invalid Telegram Chat ID format"
        exit 1
    fi

    sed -i "s/MYSQL_USER=\"\"/MYSQL_USER=\"$MYSQL_USER\"/" "$0"
    sed -i "s/MYSQL_PASSWORD=\"\"/MYSQL_PASSWORD=\"$MYSQL_PASSWORD\"/" "$0"
    sed -i "s/TG_BOT_TOKEN=\"\"/TG_BOT_TOKEN=\"$TG_BOT_TOKEN\"/" "$0"
    sed -i "s/TG_CHAT_ID=\"\"/TG_CHAT_ID=\"$TG_CHAT_ID\"/" "$0"

    if ! grep -q "/root/scripts/tg-backup.sh" /etc/crontab; then
        echo "0 */1 * * * root /bin/bash /root/scripts/tg-backup.sh >/dev/null 2>&1" | tee -a /etc/crontab
    fi
fi

if [ -z "$MYSQL_USER" ]; then
    echo "Error: MySQL username cannot be empty"
    exit 1
fi

if [ -z "$MYSQL_PASSWORD" ]; then
    echo "Error: MySQL password cannot be empty"
    exit 1
fi

if [[ ! "$TG_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    echo "Error: Invalid Telegram Bot Token format"
    exit 1
fi

if [[ ! "$TG_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
    echo "Error: Invalid Telegram Chat ID format"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
if [ ! -d "$TEMP_DIR" ]; then
    echo "Error: Failed to create temporary directory"
    exit 1
fi
BACKUP_FILE="$TEMP_DIR/backup-marzban.tar.gz"

MYSQL_CONTAINER_NAME="marzban-mariadb-1"
if ! docker ps -q -f name="$MYSQL_CONTAINER_NAME" | grep -q .; then
    echo "Error: Container $MYSQL_CONTAINER_NAME is not running"
    rm -rf "$TEMP_DIR"
    exit 1
fi

databases_marzban=$(docker exec $MYSQL_CONTAINER_NAME mariadb -h 127.0.0.1 --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" -e "SHOW DATABASES;" 2>/tmp/marzban_error.log | tr -d "| " | grep -v Database)
if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve marzban databases"
    cat /tmp/marzban_error.log
    rm -rf "$TEMP_DIR" /tmp/marzban_error.log
    exit 1
fi
rm -f /tmp/marzban_error.log

SHOP_CONTAINER_NAME="marzban-shop-db-1"
databases_shop=""
if docker ps -q -f name="$SHOP_CONTAINER_NAME" | grep -q .; then
    databases_shop=$(docker exec $SHOP_CONTAINER_NAME mariadb -h 127.0.0.1 --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" -e "SHOW DATABASES;" 2>/tmp/shop_error.log | tr -d "| " | grep -v Database)
    if [ $? -ne 0 ]; then
       0082        echo "Error: Failed to retrieve shop databases"
        cat /tmp/shop_error.log
        rm -rf "$TEMP_DIR" /tmp/shop_error.log
        exit 1
    fi
    rm -f /tmp/shop_error.log
else
    echo "Warning: Container $SHOP_CONTAINER_NAME not found, skipping shop database dump"
fi

mkdir -p /var/lib/marzban/mysql/db-backup/

for db in $databases_marzban; do
    if [[ "$db" == "marzban" ]]; then
        docker exec $MYSQL_CONTAINER_NAME mariadb-dump -h 127.0.0.1 --force --opt --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" --databases $db > /var/lib/marzban/mysql/db-backup/$db.sql
    fi
done

if [ -n "$databases_shop" ]; then
    for db in $databases_shop; do
        if [[ "$db" == "shop" ]]; then
            docker exec $SHOP_CONTAINER_NAME mariadb-dump -h 127.0.0.1 --force --opt --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" --databases $db > /var/lib/marzban/mysql/db-backup/$db.sql
        fi
    done
fi

tar --exclude='/var/lib/marzban/mysql/*' \
    --exclude='/var/lib/marzban/logs/*' \
    --exclude='/var/lib/marzban/access.log*' \
    --exclude='/var/lib/marzban/error.log*' \
    --exclude='/var/lib/marzban/xray-core/*' \
    -cf "$TEMP_DIR/backup-marzban.tar" \
    -C / \
    /opt/marzban/.env \
    /opt/marzban/ \
    /var/lib/marzban/ \
    $([ -f /root/marzban-shop/.env ] && echo "/root/marzban-shop/.env")
tar -rf "$TEMP_DIR/backup-marzban.tar" -C / /var/lib/marzban/mysql/db-backup/*
gzip "$TEMP_DIR/backup-marzban.tar"

curl -F chat_id="$TG_CHAT_ID" \
     -F document=@"$BACKUP_FILE" \
     https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument \
&& rm -rf /var/lib/marzban/mysql/db-backup/*

rm -rf "$TEMP_DIR"
