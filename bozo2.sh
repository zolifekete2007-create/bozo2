#!/usr/bin/env bash

set -e
export DEBIAN_FRONTEND=noninteractive

WHITE='\033[1;37m'
NC='\033[0m'
CHECK="${WHITE}[OK]${NC}"
CROSS="${WHITE}[ERR]${NC}"

# Root ellenőrzés
if [[ $EUID -ne 0 ]]; then
  echo -e "${CROSS} Ezt a scriptet rootként kell futtatni!"
  exit 1
fi

IP_ADDR=$(hostname -I | awk '{print $1}')
[ -z "$IP_ADDR" ] && IP_ADDR="szerver-ip"

INSTALL_NODE_RED=0
INSTALL_LAMP=0
INSTALL_MQTT=0
INSTALL_MC=0

echo -e "${WHITE}Mit szeretnél telepíteni?${NC}"
echo " 0 - Mindent"
echo " 1 - Node-RED"
echo " 2 - Apache + MariaDB + phpMyAdmin"
echo " 3 - MQTT (Mosquitto)"
echo " 4 - mc"
echo

read -rp "Opciók: " CHOICES </dev/tty

if echo "$CHOICES" | grep -qw 0; then
  INSTALL_NODE_RED=1
  INSTALL_LAMP=1
  INSTALL_MQTT=1
  INSTALL_MC=1
fi

for c in $CHOICES; do
  case "$c" in
    1) INSTALL_NODE_RED=1;;
    2) INSTALL_LAMP=1;;
    3) INSTALL_MQTT=1;;
    4) INSTALL_MC=1;;
  esac
done

echo "Frissítés..."
apt-get update -y
apt-get upgrade -y
echo -e "$CHECK Frissítve."

echo "Alap csomagok telepítése..."
apt-get install -y curl wget unzip ca-certificates
echo -e "$CHECK Telepítve."

# Node-RED
if [[ $INSTALL_NODE_RED -eq 1 ]]; then
  echo "Node-RED telepítése..."
  if command -v node >/dev/null && command -v npm >/dev/null; then
    npm install -g --unsafe-perm node-red

    cat >/etc/systemd/system/node-red.service <<EOF
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
EOF

    systemctl daemon-reload
    systemctl enable --now node-red
    echo -e "$CHECK Node-RED kész."
  else
    echo "Node.js és npm nem található — Node-RED kihagyva."
  fi
fi

# Apache + MariaDB + phpMyAdmin
if [[ $INSTALL_LAMP -eq 1 ]]; then
  echo "LAMP telepítése..."
  apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql php-mbstring php-zip php-json php-curl

  systemctl enable apache2 mariadb
  systemctl start apache2 mariadb

  mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost';
FLUSH PRIVILEGES;
EOF

  echo "phpMyAdmin telepítése..."
  cd /tmp
  wget -q -O pma.zip https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
  unzip -q pma.zip
  rm -rf /usr/share/phpmyadmin
  mv phpMyAdmin-* /usr/share/phpmyadmin

  cat >/etc/apache2/conf-available/phpmyadmin.conf <<EOF
Alias /phpmyadmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
  Require all granted
</Directory>
EOF

  a2enconf phpmyadmin
  systemctl reload apache2

  echo -e "$CHECK LAMP kész."
fi

# MQTT
if [[ $INSTALL_MQTT -eq 1 ]]; then
  echo "Mosquitto telepítése..."
  apt-get install -y mosquitto mosquitto-clients
  systemctl enable --now mosquitto
  echo -e "$CHECK MQTT kész."
fi

# mc
if [[ $INSTALL_MC -eq 1 ]]; then
  echo "mc telepítése..."
  apt-get install -y mc
  echo -e "$CHECK mc kész."
fi

echo
echo -e "${WHITE}Telepítés kész.${NC}"
echo

[[ $INSTALL_NODE_RED -eq 1 ]] && echo "Node-RED:      http://$IP_ADDR:1880"
[[ $INSTALL_LAMP -eq 1     ]] && echo "phpMyAdmin:    http://$IP_ADDR/phpmyadmin"
[[ $INSTALL_MQTT -eq 1     ]] && echo "MQTT:          $IP_ADDR:1883"
[[ $INSTALL_MC -eq 1       ]] && echo "mc:            parancs: mc"

echo
