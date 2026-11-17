#!/bin/sh
# Dijalankan di VM setelah `docker compose up`. Aman diulang.
# 1) setelan role Marantau  2) sandi role hanya-baca  3) uji asap lewat Envoy.
set -eu
cd "$(dirname "$0")"
set -a; . ./.env; set +a

psql_admin() { docker exec -i supabase-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q "$@"; }

echo "--- Setelan role"
psql_admin < volumes/db/marantau.sql
printf "alter role mt_ops_ro password '%s';\n" "$MT_OPS_RO_PASSWORD" | psql_admin
psql_admin -At -c "select 'Postgres ' || current_setting('server_version') || ' | shared_buffers ' || current_setting('shared_buffers') || ' | max_connections ' || current_setting('max_connections')"
psql_admin -At -c "select 'timeout authenticated: ' || coalesce((select array_to_string(setconfig, ',') from pg_db_role_setting s join pg_roles r on r.oid = s.setrole where r.rolname = 'authenticated'), '-')"

echo "--- Uji asap (jaringan internal Docker)"
curl_in() { docker run --rm --network marantau_default curlimages/curl:8.11.1 -s -o /dev/null -w '%{http_code}' "$@"; }
a=$(curl_in -H "apikey: $ANON_KEY" http://api-gw:8000/auth/v1/health)
r=$(curl_in -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -X POST -H 'Content-Type: application/json' -d '{}' http://api-gw:8000/rest/v1/rpc/api_ping)
echo "auth/v1/health        : $a (harus 200)"
echo "rest/v1/rpc/api_ping  : $r (404 wajar sebelum data dipindah di Fase 2)"
[ "$a" = 200 ] || { echo "Auth tidak sehat"; exit 1; }

echo "--- ANON_KEY (publik, untuk config.js versi uji Fase 2)"
echo "$ANON_KEY"
