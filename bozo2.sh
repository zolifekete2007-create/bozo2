#!/usr/bin/env bash

# ====== Színek ======
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
WARN="${YELLOW}!${NC}"

set -e
export DEBIAN_FRONTEND=noninteractive

# --- Root ellenőrzés ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${CROSS} Ezt a scriptet rootként kell futtatni!${NC}"
  echo "Használd így: sudo bash install.sh"
  exit 1
fi

echo -e "${MAGENTA}"
echo '╔══════════════════════════════════════════════════════════════╗'
echo '║  Node-RED + Apache2 + MariaDB + phpMyAdmin + MQTT + mc      ║'
echo '╚══════════════════════════════════════════════════════════════╝'
echo -e "${NC}"

# --- IP cím detektálása ---
IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$IP_ADDR" ] && IP_ADDR="szerver-ip"

#########################################
# MENÜ – MIT TELEPÍTSEN A SCRIPT?
#########################################

INSTALL_NODE_RED=0
INSTALL_LAMP=0          # Apache2 + MariaDB + PHP + phpMyAdmin
INSTALL_MQTT=0          # Mosquitto
INSTALL_MC=0

echo -e "${CYAN}Mit szeretnél telepíteni?${NC}"
echo -e "  ${YELLOW}1${NC} - Node-RED (ha van node + npm)"
echo -e "  ${YELLOW}2${NC} - Apache2 + MariaDB + PHP + phpMyAdmin"
echo -e "  ${YELLOW}3${NC} - MQTT szerver (Mosquitto)"
echo -e "  ${YELLOW}4${NC} - mc (Midnight Commander)"
echo -e "  ${YELLOW}5${NC} - Mindent telepít"
echo
read -rp "Választás (pl. 1 3 4): " CHOICES </dev/tty || CHOICES=""

if echo "$CHOICES" | grep -qw "5"; then
  INSTALL_NODE_RED=1
  INSTALL_LAMP=1
  INSTALL_MQTT=1
  INSTALL_MC=1
fi

for c in $CHOICES; do
  case "$c" in
    1) INSTALL_NODE_RED=1 ;;
    2) INSTALL_LAMP=1 ;;
    3) INSTALL_MQTT=1 ;;
    4) INSTALL_MC=1 ;;
    5) ;; # már kezeltük
    *) echo -e "${WARN} Ismeretlen opció: $c (kihagyva)" ;;
  esac
done

if [[ $INSTALL_NODE_RED -eq 0 && $INSTALL_LAMP -eq 0 && $INSTALL_MQTT -eq 0 && $INSTALL_MC -eq 0 ]]; then
  echo -e "${CROSS} Nem választottál semmit, kilépek."
  exit 0
fi

#########################################
# 1️⃣ Rendszer frissítés + alap csomagok
#########################################
echo -e "${BLUE}1. Rendszer frissítése és alap eszközök telepítése${NC}"
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget unzip ca-certificates gnupg lsb-release

#########################################
# 2️⃣ Node-RED
#########################################
if [[ $INSTALL_NODE_RED -eq 1 ]]; then
  echo -e "${BLUE}2. Node-RED telepítés${NC}"
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    npm install -g --unsafe-perm node-red

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
Environment="NODE_OPTIONS=--max_old_space_size=256"

[Install]
WantedBy=multi-user.target
UNIT
      systemctl daemon-reload
    fi

    read -rp "Induljon a Node-RED automatikusan bootkor? (y/n): " NR_AUTO </dev/tty || NR_AUTO="n"
    if [[ "$NR_AUTO" =~ ^[Yy]$ ]]; then
      systemctl enable --now node-red
    fi
  else
    echo -e "${WARN} Node.js vagy npm nincs telepítve, Node-RED kihagyva."
  fi
fi

#########################################
# 3️⃣ Apache2 + MariaDB + PHP + phpMyAdmin
#########################################
if [[ $INSTALL_LAMP -eq 1 ]]; then
  echo -e "${BLUE}3. Apache2 + MariaDB + PHP + phpMyAdmin telepítés${NC}"
  apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql \
    php-mbstring php-zip php-gd php-json php-curl
  systemctl enable --now apache2 mariadb

  # MariaDB user létrehozása
  mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

  # phpMyAdmin telepítés
  cd /tmp
  wget -q -O phpmyadmin.zip https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
  unzip -q phpmyadmin.zip
  rm phpmyadmin.zip
  rm -rf /usr/share/phpmyadmin
  mv phpMyAdmin-*-all-languages /usr/share/phpmyadmin
  mkdir -p /usr/share/phpmyadmin/tmp
  chown -R www-data:www-data /usr/share/phpmyadmin
  chmod 777 /usr/share/phpmyadmin/tmp

  # Apache config phpMyAdminhoz
  cat >/etc/apache2/conf-available/phpmyadmin.conf <<'APACHECONF'
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
    Options FollowSymLinks
    DirectoryIndex index.php
    AllowOverride All
    Require all granted
</Directory>
APACHECONF

  a2enconf phpmyadmin
  systemctl reload apache2
fi

#########################################
# 4️⃣ MQTT (Mosquitto)
#########################################
if [[ $INSTALL_MQTT -eq 1 ]]; then
  echo -e "${BLUE}4. MQTT (Mosquitto) telepítés${NC}"
  apt-get install -y mosquitto mosquitto-clients
  mkdir -p /etc/mosquitto/conf.d
  cat >/etc/mosquitto/conf.d/local.conf <<'MQTTCONF'
listener 1883
allow_anonymous true
MQTTCONF
  systemctl enable --now mosquitto
fi

#########################################
# 5️⃣ mc (Midnight Commander)
#########################################
if [[ $INSTALL_MC -eq 1 ]]; then
  echo -e "${BLUE}5. mc telepítés${NC}"
  apt-get install -y mc
fi

#########################################
# Összegzés – egyszerű
#########################################
echo
echo -e "${GREEN}Telepítés befejezve.${NC}"
echo
