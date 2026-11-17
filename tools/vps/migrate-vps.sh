#!/usr/bin/env bash
# Jalankan SEMUA migrasi ke Postgres di VM Biznet (deploy ganda Fase 2 + sesudah sync malam).
# Dijalankan dari runner GitHub Actions, di root repo, dengan host SSH "vps" sudah disiapkan.
# - Satu transaksi (gagal = VM tidak berubah), lock_timeout 8 dtk, ulang 3x bila bentrok kunci.
# - `set role postgres` supaya pemilik objek & hak sama dengan deploy ke cloud.
# - Sesudahnya tools/vps/fixups-vps.sql (sebagai supabase_admin): gerbang pre-request & kebijakan Realtime.
set -euo pipefail
cd "$(dirname "$0")/../.."
node tools/combine-sql.js >/dev/null
SQL=dist/marantau_all.sql
# Argumen di-quote (%q): ssh menggabungkan argumen jadi satu baris perintah di shell VM.
psql_vps() { ssh vps "docker exec -i supabase-db psql -U supabase_admin -d postgres -X -q -v ON_ERROR_STOP=1 $(printf '%q ' "$@")"; }

ok=0
for try in 1 2 3; do
  if { echo "set lock_timeout = '8s'; set statement_timeout = 0; set role postgres;"; cat "$SQL"; } | psql_vps > /tmp/vps-migrate.out 2> /tmp/vps-migrate.err; then ok=1; break; fi
  grep -E "ERROR|FATAL|DETAIL|HINT|CONTEXT" /tmp/vps-migrate.err | grep -v NOTICE | head -6 | cut -c1-300 | while IFS= read -r l; do echo "::error::VM: $l"; done
  grep -qiE "lock timeout|deadlock|could not obtain lock" /tmp/vps-migrate.err || break
  echo "::warning::VM: percobaan $try bentrok kunci, ulangi..."; sleep $((try * 10))
done
# WARNING dari blok "exception when others" (mis. kebijakan Realtime) - diperbaiki fixups di bawah.
grep -E '^WARNING' /tmp/vps-migrate.err | sort -u | head -8 | cut -c1-250 | while IFS= read -r l; do echo "::notice::VM migrasi: $l"; done || true
[ "$ok" = 1 ] || { echo "::error::Migrasi ke VM gagal (VM tidak berubah)."; exit 1; }

psql_vps -At < tools/vps/fixups-vps.sql | grep -vE '^$' | while IFS= read -r l; do echo "VM: $l"; done
psql_vps -At -c "select 'VM endpoint aktif: ' || count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'api_%'"
