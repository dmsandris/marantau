# Backup harian database (Fase 0)

Workflow `.github/workflows/backup-db.yml` — tiap hari 03:17 WIB, atau manual: **Actions → Backup database → Run workflow**.

Alur: `pg_dump` (schema `game`, `public`, `auth` + tabel & 3 kebijakan `realtime.messages`) → tar → tes restore ke Postgres kosong di runner (cocokkan jumlah baris) → enkripsi `age` → upload ke Google Drive `marantau-backup/supabase/marantau-db-YYYY-MM-DD.tar.age` → hapus file > 30 hari.

Repo publik: dump tidak pernah jadi artifact/commit. Log hanya berisi ukuran & jumlah.

## Persiapan sekali (pemilik)

### 1. Kunci enkripsi `age`
```
winget install FiloSottile.age      # Windows  (Mac: brew install age)
age-keygen -o marantau-backup-kunci.txt
```
- Baris `Public key: age1...` → GitHub secret **`BACKUP_AGE_RECIPIENT`**.
- File `marantau-backup-kunci.txt` = **kunci privat**. Simpan di password manager + 1 salinan offline. Jangan diunggah ke repo/Drive yang sama. Hilang = backup tidak bisa dibuka.

### 2. Izin Google Drive (`rclone`, akses hanya ke file buatan rclone)
```
winget install Rclone.Rclone        # Windows (Mac: brew install rclone). Lalu tutup & buka lagi PowerShell.
rclone authorize drive "eyJzY29wZSI6ImRyaXZlLmZpbGUifQ"
```
Browser terbuka → login akun Google tujuan backup → Izinkan. Terminal mencetak token JSON `{"access_token":...}`.

GitHub secret **`RCLONE_CONF`** diisi:
```
[gdrive]
type = drive
scope = drive.file
token = {"access_token":"...","token_type":"Bearer","refresh_token":"...","expiry":"..."}
```
Folder `marantau-backup/supabase` dibuat otomatis oleh rclone di My Drive.

### 3. Pasang secret
GitHub repo → Settings → Secrets and variables → Actions → New repository secret: `BACKUP_AGE_RECIPIENT`, `RCLONE_CONF`.

### 4. Uji
Actions → Backup database → Run workflow. Hijau = file `.tar.age` muncul di Drive.

## Membuka backup
```
age -d -i marantau-backup-kunci.txt -o marantau-db-2026-11-18.tar marantau-db-2026-11-18.tar.age
tar -xf marantau-db-2026-11-18.tar      # db.dump, realtime-messages.sql, counts.tsv, manifest.txt
```
Restore ke Postgres Supabase (self-host/baru): `pg_restore -d <URL> --no-owner db.dump`, lalu `psql <URL> -f realtime-messages.sql` (bila kebijakan belum ada). Contoh restore ke Postgres polos: `tools/backup/restore-test.sh`.

## Bila gagal
GitHub mengirim email ke pemilik saat run terjadwal gagal. Penyebab umum: token rclone dicabut (ulangi langkah 2), `SUPABASE_DB_URL` berubah, Supabase sedang lambat (jalankan ulang manual).
