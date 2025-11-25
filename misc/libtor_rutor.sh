#!/bin/bash

set -e

USERNAME=${1:-$SUDO_USER}
NODE_VERSION=${2:-20}

if [ -z "$USERNAME" ]; then
    echo "Usage: sudo $0 <username>"
    exit 1
fi

echo "Configure HTTP authentication for ruTorrent."
read -rp "Enter username for ruTorrent HTTP auth [default: $USERNAME]: " RUTORRENT_HTTP_USER
RUTORRENT_HTTP_USER=${RUTORRENT_HTTP_USER:-$USERNAME}

# validate passwords
while true; do
    read -rsp "Enter password for user '$RUTORRENT_HTTP_USER': " RUTORRENT_HTTP_PASS_1
    echo
    read -rsp "Confirm password: " RUTORRENT_HTTP_PASS_2
    echo
    if [ "$RUTORRENT_HTTP_PASS_1" = "$RUTORRENT_HTTP_PASS_2" ] && [ -n "$RUTORRENT_HTTP_PASS_1" ]; then
        break
    else
        echo "Passwords do not match or are empty. Please try again."
    fi
done

apt update && apt upgrade -y

# dependencies
apt install -y build-essential pkg-config libssl-dev libcurl4-openssl-dev \
    libtorrent-rasterbar-dev nginx php-fpm php-cli php-curl php-xmlrpc \
    php-json php-mbstring php-zip php-gd php-xml unzip git apache2-utils

# htpasswd file for rutorrent
HTPASSWD_FILE="/etc/nginx/.rutorrent_htpasswd"
htpasswd -bBc "$HTPASSWD_FILE" "$RUTORRENT_HTTP_USER" "$RUTORRENT_HTTP_PASS_1"
chmod 640 "$HTPASSWD_FILE"
chown root:www-data "$HTPASSWD_FILE"

# libtorrent
apt install -y python3-libtorrent

# rutor
cd /var/www/html
if [ ! -d rutorrent ]; then
    git clone https://github.com/Novik/ruTorrent.git rutorrent
fi
chown -R www-data:www-data rutorrent
apt install -y rtorrent

# auth nginx for rutorrent
cat >/etc/nginx/sites-available/rutorrent <<EOF
server {
        listen 80;
        server_name _;
        root /var/www/html;

        index index.php index.html;
        access_log /var/log/nginx/rutorrent_access.log;
        error_log /var/log/nginx/rutorrent_error.log;

        location /rutorrent {
                auth_basic "Restricted ruTorrent";
                auth_basic_user_file $HTPASSWD_FILE;

                try_files \$uri \$uri/ /rutorrent/index.php;

                location ~ \.php\$ {
                        include snippets/fastcgi-php.conf;
                        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                        fastcgi_pass unix:/var/run/php/php-fpm.sock;
                }
        }

        # Other locations on this server remain public
}
EOF

ln -sf /etc/nginx/sites-available/rutorrent /etc/nginx/sites-enabled/rutorrent
rm -f /etc/nginx/sites-enabled/default
systemctl reload nginx

echo "Installation complete."
echo "ruTorrent is available at http://<your-server-ip>/rutorrent"
echo "HTTP auth user: $RUTORRENT_HTTP_USER"

# config as a service on startup
read -rp "Would you like to configure rTorrent to start on boot for user '$USERNAME'? [y/N]: " ENABLE_RT_SERVICE

if [[ "$ENABLE_RT_SERVICE" =~ ^[Yy]$ ]]; then
# min config ifnone exists
sudo -u "$USERNAME" bash <<'EOF'
mkdir -p "$HOME/.config/rtorrent"
if [ ! -f "$HOME/.rtorrent.rc" ]; then
    cat >"$HOME/.rtorrent.rc" <<EORC
directory = ~/downloads
session = ~/.session
port_range = 50000-50010
port_random = no
use_udp_trackers = yes
EORC
fi
mkdir -p "$HOME/downloads" "$HOME/.session"
EOF

# systemd service 
cat >/etc/systemd/system/rtorrent@"$USERNAME".service <<EOF
[Unit]
Description=rTorrent for user %i
After=network.target

[Service]
Type=simple
User=%i
WorkingDirectory=/home/%i
ExecStart=/usr/bin/rtorrent
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "rtorrent@$USERNAME.service"
    systemctl start "rtorrent@$USERNAME.service"

    echo "rTorrent has been configured to start on boot for user '$USERNAME'."
    echo "You can manage it with: systemctl [start|stop|status] rtorrent@$USERNAME"
else
    echo "Skipping rTorrent startup service configuration."
fi