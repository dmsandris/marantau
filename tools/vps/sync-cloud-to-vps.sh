#!/usr/bin/env bash
# Fase 2.1 - timpa database VM Biznet dengan salinan Supabase cloud (VM = salinan, boleh ditimpa).
# Dijalankan dari runner, di root repo, sesudah tools/backup/backup-db.sh (ISI berisi db.dump & counts.tsv)
# dan host SSH "vps" sudah disiapkan. Dump dikirim lewat SSH (stdin), tidak pernah disimpan di disk VM.
#
# Urutan: hentikan auth/rest/realtime -> hapus schema game, public, auth -> pg_restore (pemilik objek dipertahankan)
#         -> semua migrasi main (tools/vps/migrate-vps.sh) -> ANALYZE -> setelan role Marantau -> mode pemeliharaan VM
#         -> cocokkan jumlah baris -> nyalakan lagi layanan.
# MAINT=1 (bawaan): VM masuk mode pemeliharaan, hanya akun GM yang bisa main di versi uji.
# Tidak mencetak data apa pun (repo publik) - hanya nama tabel & jumlah.
set -euo pipefail
: "${ISI:?folder dump}"
MAINT="${MAINT:-1}"
cd "$(dirname "$0")/../.."
SH=/opt/marantau/selfhost
# Argumen di-quote (%q): ssh menggabungkan argumen jadi satu baris perintah di shell VM.
psql_vps() { ssh vps "docker exec -i supabase-db psql -U supabase_admin -d postgres -X -q -v ON_ERROR_STOP=1 $(printf '%q ' "$@")"; }
compose() { ssh vps "cd $SH && docker compose $*"; }

nyalakan() {
  compose start auth rest realtime >/dev/null 2>&1 || true
  ssh vps "cd $SH
    for i in \$(seq 1 40); do
      bad=\$(docker compose ps --format '{{.Name}} {{.Health}}' | awk '\$2!=\"healthy\" && \$2!=\"\"{print}')
      [ -z \"\$bad\" ] && break; sleep 5
    done
    docker compose ps --format 'table {{.Name}}\t{{.Status}}'
    [ -z \"\$bad\" ] || { echo \"::error::Belum sehat: \$bad\"; exit 1; }"
  psql_vps -c "notify pgrst, 'reload schema'; notify pgrst, 'reload config'" || true
}
trap 'echo "::warning::Sync berhenti di tengah - layanan dinyalakan lagi."; nyalakan || true' ERR

echo "--- 1. Hentikan auth, rest, realtime (Postgres tetap jalan)"
compose stop auth rest realtime

echo "--- 2. Kosongkan schema game, public, auth"
psql_vps <<'SQL'
set lock_timeout = '30s';
select count(*) as diputus from (
  select pg_terminate_backend(pid) from pg_stat_activity
  where datname = 'postgres' and pid <> pg_backend_pid() and usename not in ('supabase_admin')
) t \gset
drop schema if exists game cascade;
drop schema if exists public cascade;
drop schema if exists auth cascade;
SQL

echo "--- 3. Restore dump cloud ($(du -h "$ISI/db.dump" | cut -f1))"
set +e
ssh vps 'docker exec -i supabase-db pg_restore -U supabase_admin -d postgres' < "$ISI/db.dump" 2> "$ISI/vps-restore-err.txt"
set -e
# Wajar: GRANT ke role yang hanya ada di cloud.
grep -E '^pg_restore: error:' "$ISI/vps-restore-err.txt" | grep -vE 'role "[^"]+" does not exist' > "$ISI/vps-restore-sisa.txt" || true
nrole=$(grep -cE 'role "[^"]+" does not exist' "$ISI/vps-restore-err.txt" || true)
nerr=$(wc -l < "$ISI/vps-restore-sisa.txt")
[ "$nrole" -gt 0 ] && echo "::notice::pg_restore: $nrole GRANT ke role khusus cloud dilewati ($(grep -oE 'role "[^"]+"' "$ISI/vps-restore-err.txt" | sort -u | paste -sd' '))"
if [ "$nerr" -gt 0 ]; then
  head -8 "$ISI/vps-restore-sisa.txt" | cut -c1-300 | while IFS= read -r l; do echo "::error::$l"; done
  echo "::error::pg_restore: $nerr error lain"; false
fi

echo "--- 4. Migrasi main ke VM"
bash tools/vps/migrate-vps.sh

echo "--- 4b. ANALYZE (pg_restore tidak membawa statistik -> tanpa ini rencana query buruk)"
psql_vps -c "analyze"

echo "--- 5. Setelan role Marantau + sandi role hanya-baca"
# marantau.sql dari repo (bukan salinan di VM, yang hanya diperbarui VPS deploy).
psql_vps < deploy/selfhost/volumes/db/marantau.sql
ssh vps "cd $SH && set -a && . ./.env && set +a \
  && printf \"alter role mt_ops_ro password '%s';\n\" \"\$MT_OPS_RO_PASSWORD\" | docker exec -i supabase-db psql -U supabase_admin -d postgres -X -q -v ON_ERROR_STOP=1"

echo "--- 6. Mode pemeliharaan VM: $([ "$MAINT" = 1 ] && echo ON '(hanya GM)' || echo 'tidak diubah (ikut cloud)')"
if [ "$MAINT" = 1 ]; then
  psql_vps -c "insert into game.config (key, value) values ('MaintenanceMode', 'on') on conflict (key) do update set value = 'on'"
fi

echo "--- 7. Cocokkan jumlah baris (VM count(*) vs perkiraan statistik cloud)"
psql_vps -At -F $'\t' > "$ISI/vps-counts.tsv" <<'SQL'
select n.nspname || '.' || c.relname,
       (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text::bigint
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r', 'p') and not c.relispartition
  and (n.nspname in ('game', 'public') or (n.nspname = 'auth' and c.relname in ('users', 'identities', 'refresh_tokens', 'sessions')))
order by 1
SQL
awk -F'\t' '
  NR == FNR { vm[$1] = $2; next }
  { src += $2; t++
    if (!($1 in vm)) { print "::error::Tabel hilang di VM: " $1; bad++; next }
    dst += vm[$1]
    if ($2 > 50 && vm[$1] < $2 * 0.7) { print "::error::" $1 ": VM " vm[$1] " baris (cloud +-" $2 ")"; bad++ } }
  END { printf "::notice::Sync: %d tabel, baris cloud +-%d / VM %d, bermasalah %d\n", t, src, dst, bad
        for (k in vm) if (k ~ /^auth\.(users|refresh_tokens)$|^game\.(players|ships|inventory|player_quests)$/) printf "  %-26s %s\n", k, vm[k]
        exit (bad > 0 ? 1 : 0) }' "$ISI/vps-counts.tsv" "$ISI/counts.tsv"

echo "--- 8. Nyalakan layanan"
trap - ERR
nyalakan
