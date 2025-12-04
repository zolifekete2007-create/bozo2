#!/usr/bin/env bash
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'
CHECK="${GREEN}[OK]${NC}"
ERR="${RED}[ERR]${NC}"
INFO="${BLUE}[INFO]${NC}"

set -e
export DEBIAN_FRONTEND=noninteractive

if [[ $EUID -ne 0 ]]; then
  echo -e "${ERR} Rootként futtasd!"
  exit 1
fi

echo -e "${YELLOW}Mit szeretnél telepíteni?${NC}"
echo -e "  1 - Node-RED"
echo -e "  2 - Apache2 + MariaDB + PHP + phpMyAdmin"
echo -e "  3 - MQTT (Mosquitto)"
echo -e "  4 - mc (Midnight Commander)"
echo -e "  5 - MINDENT telepít"
echo
read -rp "Választás (pl. 1 vagy 1 2 3): " CHOICES

NODE_RED=0
LAMP=0
MQTT=0
MC=0

if echo "$CHOICES" | grep -qw "5"; then
  NODE_RED=1
  LAMP=1
  MQTT=1
  MC=1
fi

for c in $CHOICES; do
  case "$c" in
    1) NODE_RED=1 ;;
    2) LAMP=1 ;;
    3) MQTT=1 ;;
    4) MC=1 ;;
    5) ;;
    *) echo -e "${YELLOW}[!] Ismeretlen opció: $c${NC}" ;;
  esac
done

if [[ $NODE_RED -eq 0 && $LAMP -eq 0 && $MQTT -eq 0 && $MC -eq 0 ]]; then
  echo -e "${ERR} Nem választottál semmit."
  exit 0
fi

echo -e "${INFO} Rendszer frissítése..."
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget unzip ca-certificates gnupg lsb-release

if [[ $NODE_RED -eq 1 ]]; then
  echo -e "${INFO} Node-RED telepítése..."
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    npm install -g --unsafe-perm node-red
    echo -e "${CHECK} Node-RED telepítve."
    SERVICE="/etc/systemd/system/node-red.service"
    if [[ ! -f "$SERVICE" ]]; then
      cat >"$SERVICE" <<'UNIT'
[Unit]
Description=Node-RED
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/env node-red
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
      systemctl daemon-reload
    fi
    read -rp "Induljon automatikusan bootkor? (y/n): " NR
    if [[ "$NR" =~ ^[Yy]$ ]]; then
      systemctl enable --now node-red
      echo -e "${CHECK} Node-RED engedélyezve."
    fi
  else
    echo -e "${ERR} Node.js vagy npm nem telepített – kihagyva."
  fi
fi

if [[ $LAMP -eq 1 ]]; then
  echo -e "${INFO} LAMP csomagok telepítése..."
  apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql \
    php-mbstring php-zip php-gd php-json php-curl
  systemctl enable apache2 mariadb
  systemctl start apache2 mariadb
  echo -e "${CHECK} Apache2 + MariaDB fut."

  echo -e "${INFO} MariaDB user létrehozása (user / user123)"
  mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

  echo -e "${INFO} phpMyAdmin telepítése..."
  cd /tmp
  wget -q -O phpmyadmin.zip https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
  unzip -q phpmyadmin.zip
  rm -rf /usr/share/phpmyadmin
  mv phpMyAdmin-*-all-languages /usr/share/phpmyadmin
  mkdir -p /usr/share/phpmyadmin/tmp
  chmod 777 /usr/share/phpmyadmin/tmp

  cat >/etc/apache2/conf-available/phpmyadmin.conf <<'APACHECONF'
Alias /phpmyadmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
    Options FollowSymLinks
    DirectoryIndex index.php
    Require all granted
</Directory>
APACHECONF

  a2enconf phpmyadmin
  systemctl reload apache2
fi

if [[ $MQTT -eq 1 ]]; then
  echo -e "${INFO} MQTT (Mosquitto) telepítése..."
  apt-get install -y mosquitto mosquitto-clients
  mkdir -p /etc/mosquitto/conf.d
  cat >/etc/mosquitto/conf.d/local.conf <<'MQTT'
listener 1883
allow_anonymous true
MQTT
  systemctl enable mosquitto
  systemctl restart mosquitto
  echo -e "${CHECK} MQTT fut a 1883 porton."
fi

if [[ $MC -eq 1 ]]; then
  echo -e "${INFO} mc telepítése..."
  apt-get install -y mc
  echo -e "${CHECK} mc telepítve (indítás: mc)"
fi

echo
echo -e "${GREEN}Telepítés befejezve.${NC}"
echo
