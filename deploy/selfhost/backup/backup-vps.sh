#!/usr/bin/env bash
# Backup database server Biznet (rencana 1.7). Dijalankan systemd sebagai user marantau.
#   backup-vps.sh backup        -> dump, enkripsi age, simpan lokal 7 hari, upload Google Drive (30 hari)
#   backup-vps.sh restore-test  -> backup + tes restore ke Postgres sementara (container postgres:17)
# Format arsip sama dengan Fase 0 (tools/backup/backup-db.sh): db.dump, realtime-messages.sql,
# counts.tsv, manifest.txt. Bedanya di VM jumlah baris dihitung count(*) asli.
# Status ditulis ke /opt/marantau/backup/status.json (dibaca Panel Ops).
set -euo pipefail
MODE="${1:-backup}"
BK=/opt/marantau/backup
REQ=$BK/req
CONF="$HOME/.config/marantau"
SELF=/opt/marantau/selfhost
REMOTE="${MT_BACKUP_REMOTE:-gdrive:marantau-backup/vps}"
TANGGAL=$(TZ=Asia/Jakarta date +%F)
JAM=$(TZ=Asia/Jakarta date +%H%M)
STATUS=$BK/status.json
umask 077

rm -f "$REQ/$MODE"   # permintaan dari Panel Ops sudah diterima
WORK=$(mktemp -d /tmp/mt-backup.XXXXXX)
cleanup() { docker rm -f mt-restore-test >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

now() { date -u +%FT%TZ; }
setst() { # setst key value [key value ...]  (nilai string)
  local tmp; tmp=$(mktemp "$BK/.status.XXXX")
  local cur='{}'; [ -s "$STATUS" ] && cur=$(cat "$STATUS")
  local args=() expr='.'
  while [ $# -ge 2 ]; do args+=(--arg "$1" "$2"); expr="$expr | .$1 = \$$1"; shift 2; done
  printf '%s' "$cur" | jq "${args[@]}" "$expr" > "$tmp" && chmod 644 "$tmp" && mv "$tmp" "$STATUS"
}
tg() {
  local tok chat
  tok=$(sed -n 's/^OPS_TELEGRAM_TOKEN=//p' "$SELF/.env" 2>/dev/null || true)
  chat=$(sed -n 's/^OPS_TELEGRAM_CHAT_ID=//p' "$SELF/.env" 2>/dev/null || true)
  [ -n "$tok" ] && [ -n "$chat" ] || return 0
  curl -s -m 10 -o /dev/null "https://api.telegram.org/bot$tok/sendMessage" \
    --data-urlencode "chat_id=$chat" --data-urlencode "text=$1" || true
}
fail() {
  trap - ERR; set +e
  setst running "" lastResult "gagal" lastError "$1" lastRun "$(now)"
  tg "❌ Marantau: backup VM gagal - $1"
  echo "GAGAL: $1" >&2
  exit 1
}
trap 'fail "baris $LINENO: perintah gagal"' ERR

setst running "$MODE" runStarted "$(now)"
psqlx() { docker exec -i supabase-db psql -U supabase_admin -d postgres -X -At -v ON_ERROR_STOP=1 "$@"; }
dumpx() { docker exec -i supabase-db pg_dump -U supabase_admin -d postgres --lock-wait-timeout=60s "$@"; }

docker inspect -f '{{.State.Running}}' supabase-db 2>/dev/null | grep -q true || fail "container supabase-db tidak jalan"
[ -s "$CONF/age-recipient.txt" ] || fail "kunci publik age belum dipasang ($CONF/age-recipient.txt)"
[ -s "$CONF/rclone.conf" ] || fail "rclone.conf belum dipasang ($CONF/rclone.conf)"

# ---- 1. dump ----
mkdir -p "$WORK/isi"; cd "$WORK/isi"
psqlx -F $'\t' > counts.tsv <<'SQL'
select n.nspname || '.' || c.relname,
       (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text::bigint
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r', 'p') and not c.relispartition
  and (n.nspname in ('game', 'public') or (n.nspname = 'auth' and c.relname in ('users', 'identities', 'refresh_tokens', 'sessions')))
order by 1
SQL
dumpx -Fc -Z 6 -n game -n public -n auth > db.dump
dumpx -s -t realtime.messages > realtime-messages.sql
pol=$(grep -c '^CREATE POLICY' realtime-messages.sql || true)
tabel=$(wc -l < counts.tsv)
baris=$(awk -F'\t' '{s+=$2} END {print s+0}' counts.tsv)
{
  echo "sumber=vps-biznet"
  echo "tanggal_wib=$TANGGAL"
  echo "dibuat_utc=$(now)"
  echo "server=$(psqlx -c 'show server_version')"
  echo "tabel=$tabel"
  echo "baris=$baris"
  echo "kebijakan_realtime=$pol"
  sha256sum db.dump realtime-messages.sql counts.tsv
} > manifest.txt
f="marantau-vps-db-$TANGGAL-$JAM.tar"
tar -cf "$WORK/$f" db.dump realtime-messages.sql counts.tsv manifest.txt

# ---- 2. enkripsi & simpan lokal 7 hari ----
age -R "$CONF/age-recipient.txt" -o "$WORK/$f.age" "$WORK/$f"
size=$(stat -c %s "$WORK/$f.age")
install -m 644 "$WORK/$f.age" "$BK/$f.age"
find "$BK" -maxdepth 1 -name 'marantau-vps-db-*.tar.age' -mtime +7 -delete

# ---- 3. upload Google Drive (30 hari) ----
R="rclone --config $CONF/rclone.conf --retries 3 --low-level-retries 5"
$R copyto "$WORK/$f.age" "$REMOTE/$f.age"
rsz=$($R size --json "$REMOTE/$f.age" | jq -r .bytes)
[ "$rsz" = "$size" ] || fail "ukuran di Drive ($rsz) beda dengan lokal ($size)"
$R delete "$REMOTE" --min-age 30d --drive-use-trash=false || true
ndrive=$($R lsf "$REMOTE" | wc -l)

hsize=$(numfmt --to=iec --suffix=B "$size")
setst running "" lastResult "ok" lastError "" lastRun "$(now)" lastOk "$(now)" file "$f.age" size "$hsize" \
  tables "$tabel" rows "$baris" realtimePolicies "$pol" driveFiles "$ndrive"
echo "Backup OK: $f.age $hsize, $tabel tabel, $baris baris, kebijakan Realtime $pol, Drive $ndrive file"

# ---- 4. tes restore (mingguan / atas permintaan) ----
if [ "$MODE" = restore-test ]; then
  setst running "restore-test"
  cp "$SELF/backup/restore-test.sh" "$WORK/isi/"
  chmod -R a+rwX "$WORK/isi"; chmod 755 "$WORK"
  docker rm -f mt-restore-test >/dev/null 2>&1 || true
  docker run -d --name mt-restore-test --memory 700m -e POSTGRES_PASSWORD=tes \
    -v "$WORK/isi:/isi" postgres:17 >/dev/null
  for i in $(seq 1 60); do docker exec mt-restore-test pg_isready -U postgres -h localhost >/dev/null 2>&1 && break; sleep 2; done
  sleep 3
  set +e
  out=$(docker exec -e TARGET=postgresql://postgres:tes@localhost/postgres -e ISI=/isi mt-restore-test bash /isi/restore-test.sh 2>&1)
  rc=$?
  set -e
  note=$(printf '%s\n' "$out" | grep -E '^::(notice|error)::' | sed -E 's/^::[a-z]+:://' | head -6 | paste -sd'|' | cut -c1-600)
  echo "$out" | tail -20
  if [ $rc -eq 0 ]; then
    setst running "" restoreTest "OK" restoreAt "$(now)" restoreNote "$note"
  else
    setst running "" restoreTest "GAGAL" restoreAt "$(now)" restoreNote "$note"
    tg "❌ Marantau: tes restore backup VM GAGAL - $note"
    exit 1
  fi
fi
