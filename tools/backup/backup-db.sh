#!/usr/bin/env bash
# Backup database Marantau (Supabase) -> satu arsip tar di $WORK.
# Isi arsip: db.dump (pg_dump custom: schema game, public, auth),
#            realtime-messages.sql (tabel + 3 kebijakan Realtime), counts.tsv, manifest.txt
# Butuh: DB (connection string), WORK (folder kerja), TANGGAL (YYYY-MM-DD, WIB).
# Tidak mencetak data apa pun ke log (repo publik) - hanya ukuran & jumlah.
set -euo pipefail
: "${DB:?DB kosong}" "${WORK:?}" "${TANGGAL:?}"
umask 077
mkdir -p "$WORK/isi"
cd "$WORK/isi"

# Jumlah baris per tabel (dipakai tes restore). Diambil tepat sebelum dump;
# tabel yang sibuk (presence, chat) boleh beda sedikit.
psql "$DB" -X -At -F $'\t' -v ON_ERROR_STOP=1 > counts.tsv <<'SQL'
select format('select %L, count(*) from %I.%I', n.nspname || '.' || c.relname, n.nspname, c.relname)
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r', 'p') and not c.relispartition
  and (n.nspname in ('game', 'public') or (n.nspname = 'auth' and c.relname in ('users', 'identities', 'refresh_tokens', 'sessions')))
order by 1
\gexec
SQL

pg_dump "$DB" -Fc -Z 6 --lock-wait-timeout=60s -n game -n public -n auth -f db.dump
pg_dump "$DB" -s -t realtime.messages --lock-wait-timeout=60s -f realtime-messages.sql

pol=$(grep -c '^CREATE POLICY' realtime-messages.sql || true)
[ "$pol" -ge 3 ] || { echo "::error::Kebijakan Realtime hanya $pol (harusnya >= 3)"; exit 1; }

{
  echo "tanggal_wib=$TANGGAL"
  echo "dibuat_utc=$(date -u +%FT%TZ)"
  echo "commit=${GITHUB_SHA:-lokal}"
  echo "pg_dump=$(pg_dump --version)"
  echo "server=$(psql "$DB" -X -At -c 'show server_version')"
  echo "tabel=$(wc -l < counts.tsv)"
  echo "baris=$(awk -F'\t' '{s+=$2} END {print s+0}' counts.tsv)"
  echo "kebijakan_realtime=$pol"
  sha256sum db.dump realtime-messages.sql counts.tsv
} > manifest.txt

tar -cf "$WORK/marantau-db-$TANGGAL.tar" db.dump realtime-messages.sql counts.tsv manifest.txt
echo "::notice::Dump OK: $(du -h db.dump | cut -f1) | $(grep -E '^(tabel|baris)=' manifest.txt | tr '\n' ' ')| kebijakan Realtime $pol"
