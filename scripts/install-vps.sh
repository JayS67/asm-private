#!/usr/bin/env bash
# Install a single-database ASM instance from this checkout on Debian/Ubuntu.

set -Eeuo pipefail

APP_DIR=/opt/asm3
CONF_FILE=/etc/asm3.conf
DB_NAME=asm3
DB_USER=asm3
LOCALE=en
DOMAIN=
EMAIL=
ENABLE_TLS=true

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/install-vps.sh --domain asm.example.org --email admin@example.org [options]

Options:
  --domain NAME       Public DNS name for ASM (required)
  --email ADDRESS     Email used for Let's Encrypt notices (required with TLS)
  --locale CODE       Initial ASM locale (default: en)
  --no-tls            Configure HTTP only (intended for private/testing servers)
  --help              Show this help

The installer creates a local PostgreSQL database, initializes ASM, configures
Apache, obtains a Let's Encrypt certificate, and prints a generated admin
password. Run it from the root of an ASM source checkout.
EOF
}

while (( $# )); do
    case "$1" in
        --domain) DOMAIN=${2:-}; shift 2 ;;
        --email) EMAIL=${2:-}; shift 2 ;;
        --locale) LOCALE=${2:-}; shift 2 ;;
        --no-tls) ENABLE_TLS=false; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "Run this installer with sudo." >&2; exit 1; }
[[ -n $DOMAIN ]] || { echo "--domain is required." >&2; usage >&2; exit 2; }
if $ENABLE_TLS && [[ -z $EMAIL ]]; then
    echo "--email is required unless --no-tls is used." >&2
    exit 2
fi
[[ $DOMAIN =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Invalid domain name." >&2; exit 2; }
[[ $LOCALE =~ ^[A-Za-z_]+$ ]] || { echo "Invalid locale code." >&2; exit 2; }

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ -f "$REPO_DIR/src/main.py" && -f "$REPO_DIR/VERSION" ]] || {
    echo "Run the installer from a complete ASM source checkout." >&2
    exit 1
}

if [[ -e $CONF_FILE || -d $APP_DIR ]]; then
    echo "An existing ASM installation was found ($CONF_FILE or $APP_DIR)." >&2
    echo "This installer will not overwrite an installation; back it up and remove it explicitly." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    apache2 certbot libapache2-mod-wsgi-py3 python3-certbot-apache \
    postgresql python3-boto3 python3-lxml python3-memcache python3-openpyxl \
    python3-pil python3-psycopg2 python3-qrcode python3-reportlab \
    python3-requests weasyprint rsync

DB_PASSWORD=$(openssl rand -hex 24)
ADMIN_PASSWORD=$(openssl rand -hex 16)
SCHEME=http
$ENABLE_TLS && SCHEME=https

install -d -o root -g root -m 0755 "$APP_DIR"
rsync -a --delete "$REPO_DIR/src/" "$APP_DIR/"
install -d -o www-data -g www-data -m 0750 /var/lib/asm3/media /var/cache/asm3
install -o www-data -g www-data -m 0640 /dev/null /var/log/asm3.log

runuser -u postgres -- psql -v ON_ERROR_STOP=1 \
    --set=db_user="$DB_USER" --set=db_name="$DB_NAME" --set=db_password="$DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'db_user') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db_name') \gexec
SQL

umask 027
cat > "$CONF_FILE" <<EOF
base_url = $SCHEME://$DOMAIN
service_url = $SCHEME://$DOMAIN/service
locale = $LOCALE
timezone = 0
log_location = /var/log/asm3.log
log_debug = false
db_type = POSTGRESQL
db_host = 127.0.0.1
db_port = 5432
db_username = $DB_USER
db_password = $DB_PASSWORD
db_name = $DB_NAME
deployment_type = wsgi
session_secure_cookie = $ENABLE_TLS
memcached_server = 127.0.0.1:11211
dbfs_store = file
dbfs_filestorage_folder = /var/lib/asm3/media
disk_cache = /var/cache/asm3
email_errors = false
rollup_js = false
smtp_server = { "sendmail": true }
from_address = asm@$DOMAIN
EOF
chown root:www-data "$CONF_FILE"
chmod 0640 "$CONF_FILE"

runuser -u www-data -- env ASM3_CONF="$CONF_FILE" PYTHONPATH="$APP_DIR" ASM_APP_DIR="$APP_DIR" ASM_LOCALE="$LOCALE" \
    python3 - <<'PY'
import os
import asm3.db
import asm3.dbupdate

dbo = asm3.db.get_database()
dbo.locale = os.environ["ASM_LOCALE"]
dbo.installpath = os.environ["ASM_APP_DIR"] + "/"
if not dbo.has_structure():
    # Initialize locally without fetching the optional hosted report catalogue.
    asm3.dbupdate.install_db_structure(dbo)
    asm3.dbupdate.install_db_views(dbo)
    asm3.dbupdate.install_default_data(dbo)
    asm3.dbupdate.install_db_sequences(dbo)
    asm3.dbupdate.install_db_stored_procedures(dbo)
    asm3.dbupdate.install_default_templates(dbo)
    asm3.dbupdate.install_default_onlineforms(dbo)
PY

ADMIN_HASH=$(ADMIN_PASSWORD=$ADMIN_PASSWORD python3 - <<'PY'
import base64
import hashlib
import os

salt = base64.b64encode(os.urandom(16)).decode("ascii")
iterations = 10000
digest = hashlib.pbkdf2_hmac("sha1", os.environ["ADMIN_PASSWORD"].encode(), salt.encode(), iterations).hex()
print(f"pbkdf2:sha1:{salt}:{iterations}:{digest}")
PY
)
PGPASSWORD=$DB_PASSWORD psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 --set=admin_hash="$ADMIN_HASH" <<'SQL'
UPDATE users SET Password = :'admin_hash' WHERE UserName = 'user';
UPDATE users SET DisableLogin = 1 WHERE UserName = 'guest';
SQL

cat > /etc/apache2/sites-available/asm3.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ErrorLog \${APACHE_LOG_DIR}/asm3-error.log
    CustomLog \${APACHE_LOG_DIR}/asm3-access.log combined

    WSGIDaemonProcess asm3 user=www-data group=www-data python-path=$APP_DIR
    WSGIProcessGroup asm3
    WSGIScriptAlias / $APP_DIR/main.py/
    Alias /static $APP_DIR/static

    <Directory $APP_DIR>
        Require all granted
    </Directory>
</VirtualHost>
EOF

cat > /etc/cron.daily/asm3 <<EOF
#!/bin/sh
cd $APP_DIR
ASM3_CONF=$CONF_FILE python3 cron.py all >/dev/null 2>&1
EOF
chmod 0755 /etc/cron.daily/asm3

a2dissite 000-default >/dev/null || true
a2ensite asm3 >/dev/null
a2enmod wsgi headers >/dev/null
apache2ctl configtest
systemctl enable --now postgresql apache2
systemctl reload apache2

if $ENABLE_TLS; then
    certbot --apache --non-interactive --agree-tos --redirect \
        --domain "$DOMAIN" --email "$EMAIL"
fi

install -m 0600 /dev/null /root/asm3-install-credentials.txt
cat > /root/asm3-install-credentials.txt <<EOF
URL: $SCHEME://$DOMAIN/
Username: user
Password: $ADMIN_PASSWORD
Database: $DB_NAME
Database user: $DB_USER
Database password: $DB_PASSWORD
EOF

cat <<EOF

ASM installation complete.

URL:      $SCHEME://$DOMAIN/
Username: user
Password: $ADMIN_PASSWORD

Credentials were also written to /root/asm3-install-credentials.txt (mode 0600).
Sign in now, create a named administrator, and store the credentials securely.
Back up PostgreSQL and /var/lib/asm3/media before adding production data.
EOF
