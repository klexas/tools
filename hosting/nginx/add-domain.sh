#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: sudo $0 <domain> [web_root] [email] [--no-ssl]"
	echo
	echo "  domain    : Required. e.g. example.com"
	echo "  web_root  : Optional. Default: /var/www/<domain>/public_html"
	echo "  email     : Optional. Used for Let's Encrypt registration"
	echo "  --no-ssl  : Optional. Skip Let's Encrypt and HTTPS config"
	exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
	echo "This script must be run as root (use sudo)." >&2
	exit 1
fi

DOMAIN="${1:-}"
WEB_ROOT="${2:-}"
EMAIL="${3:-}"
NO_SSL="false"

# detect --no-ssl anywhere in args
for arg in "$@"; do
	if [[ "$arg" == "--no-ssl" ]]; then
		NO_SSL="true"
	fi
done

if [[ -z "${DOMAIN}" ]]; then
	usage
fi

if [[ -z "${WEB_ROOT}" || "${WEB_ROOT}" == "--no-ssl" ]]; then
	WEB_ROOT="/var/www/${DOMAIN}/public_html"
fi

NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF="${NGINX_AVAILABLE}/${DOMAIN}"

echo "Domain     : ${DOMAIN}"
echo "Web root   : ${WEB_ROOT}"
echo "Email      : ${EMAIL:-<none>}"
echo "Use SSL    : $([[ "${NO_SSL}" == "true" ]] && echo "no" || echo "yes")"
echo

read -p "Continue and create configuration? [y/N]: " CONTINUE
CONTINUE=${CONTINUE:-N}
if [[ ! "${CONTINUE}" =~ ^[Yy]$ ]]; then
	echo "Aborted."
	exit 1
fi

mkdir -p "${WEB_ROOT}"
chown -R www-data:www-data "$(dirname "${WEB_ROOT}")"
chmod -R 755 "$(dirname "${WEB_ROOT}")"

if [[ ! -f "${WEB_ROOT}/index.html" ]]; then
	cat > "${WEB_ROOT}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<title>Welcome to ${DOMAIN}</title>
	<style>
		body { font-family: system-ui, sans-serif; margin: 2rem; }
	</style>
	</head>
<body>
	<h1>It works!</h1>
	<p>This is the default page for <strong>${DOMAIN}</strong>.</p>
	<p>Web root: <code>${WEB_ROOT}</code></p>
</body>
</html>
EOF
fi

if [[ -f "${NGINX_CONF}" ]]; then
	echo "nginx config for ${DOMAIN} already exists at ${NGINX_CONF}."
else
	cat > "${NGINX_CONF}" <<EOF
server {
		listen 80;
		listen [::]:80;

		server_name ${DOMAIN} www.${DOMAIN};

		root ${WEB_ROOT};
		index index.html index.htm index.nginx-debian.html;

		access_log /var/log/nginx/${DOMAIN}_access.log;
		error_log  /var/log/nginx/${DOMAIN}_error.log;

		location / {
				try_files \$uri \$uri/ =404;
		}
}
EOF
fi

ln -sf "${NGINX_CONF}" "${NGINX_ENABLED}/${DOMAIN}"

echo "Testing nginx configuration..."
nginx -t

echo "Reloading nginx..."
systemctl reload nginx

if [[ "${NO_SSL}" == "false" ]]; then
	if command -v certbot >/dev/null 2>&1; then
		echo
		echo "Requesting Let's Encrypt certificate via certbot..."
		if [[ -n "${EMAIL}" ]]; then
			certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}" || {
				echo "certbot failed; keeping HTTP-only configuration."
				exit 0
			}
		else
			certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" --non-interactive --agree-tos --register-unsafely-without-email || {
				echo "certbot failed; keeping HTTP-only configuration."
				exit 0
			}
		fi

		echo "SSL configured for ${DOMAIN}. nginx will be reloaded by certbot."
	else
		echo
		echo "certbot not found; skipping automatic SSL."
		echo "To enable HTTPS later, install certbot and run:"
		echo "  sudo certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
	fi
else
	echo "Skipping SSL setup as requested (--no-ssl)."
fi

echo
echo "Done. Point your DNS A record to this server's IP and test:"
echo "  http://${DOMAIN}/"

