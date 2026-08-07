#!/usr/bin/env bash
set -euo pipefail

db_name="opentofu_backend"
db_user="opentofu"
credential_file="/etc/opentofu-backend.env"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-client openssl

if [[ -e "$credential_file" ]]; then
  echo "${credential_file} already exists; refusing to rotate backend credentials." >&2
  exit 1
fi

db_password="$(openssl rand -hex 32)"

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${db_user}'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -c "CREATE ROLE ${db_user} LOGIN PASSWORD '${db_password}'"
fi

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${db_name}'" | grep -q 1; then
  sudo -u postgres createdb --owner "$db_user" "$db_name"
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET listen_addresses = '*'"
hba_file="$(sudo -u postgres psql -Atc 'SHOW hba_file')"
hba_rule="hostssl ${db_name} ${db_user} 192.168.88.0/24 scram-sha-256"
grep -Fqx "$hba_rule" "$hba_file" || printf '%s\n' "$hba_rule" >> "$hba_file"

install -m 0600 /dev/null "$credential_file"
printf 'PG_CONN_STR=postgres://%s:%s@192.168.88.3:5432/%s?sslmode=require\n' \
  "$db_user" "$db_password" "$db_name" > "$credential_file"

systemctl restart postgresql
systemctl enable postgresql

PGPASSWORD="$db_password" psql \
  "host=127.0.0.1 port=5432 dbname=${db_name} user=${db_user} sslmode=require" \
  -v ON_ERROR_STOP=1 -c 'SELECT current_database(), current_user, ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()'
