# Marantau

Game dagang kapal multipemain. Tampilan di **GitHub Pages**, server & database di **Supabase**.

- Main: https://dmsandris.github.io/marantau/
- Versi lama (Apps Script) tetap ada di `legacy-gs/` sebagai rujukan.

## Cara kerjanya (singkat)

| Bagian | Tempat | Isi |
|---|---|---|
| Tampilan game | `web/` → GitHub Pages | HTML/JS game (sama dengan versi Apps Script) |
| Jembatan | `web/mt-supabase.js` | mengubah panggilan lama `google.script.run` → Supabase |
| Logika & data | `supabase/migrations/*.sql` → Supabase | pasar, kapal, misi, bank, multiplayer, login |
| Tes | `test/` | database tiruan di komputer, dijalankan sebelum deploy |

Setiap kali ada perubahan yang di-*push* ke branch `main`:
- perubahan di `web/` → workflow **Deploy web** menerbitkan ulang situs (±1 menit);
- perubahan di `supabase/migrations/` → workflow **Deploy database** menjalankan semua tes,
  lalu mengirim SQL ke Supabase dalam **satu transaksi** (kalau ada error, tidak ada yang berubah).

Status bisa dilihat di tab **Actions** repo ini (hijau = berhasil, merah = gagal; klik untuk detail).

## Pengaturan sekali saja

1. **GitHub Pages**: Settings → Pages → *Build and deployment* → Source = **GitHub Actions**.
2. **Secret database**: Settings → Secrets and variables → Actions → *New repository secret*
   - Name: `SUPABASE_DB_URL`
   - Secret: dari Supabase → tombol **Connect** → *Session pooler* → salin URI,
     ganti `[YOUR-PASSWORD]` dengan password database kamu.
   - Password ini hanya disimpan di GitHub Secrets. Jangan ditaruh di file atau chat.
3. **Supabase Auth**: Authentication → Sign In / Providers → Email → matikan **Confirm email**.

## Kalau deploy database otomatis gagal (cadangan manual)

1. Di komputer: `npm run sql` → menghasilkan `dist/marantau_all.sql`
   (atau unduh dari rilis/berkas yang diberikan Claude).
2. Supabase → SQL Editor → New query → tempel seluruh isi file → **Run**.
Aman dijalankan berulang kali: data pemain tidak dihapus.

## Untuk pengembang (atau Claude)

```bash
npm install
npm test          # semua tes database (PGlite)
npm run dev       # build + server lokal tiruan Supabase di http://localhost:8787
npm run build     # hasil situs di dist/
```

Aturan porting dan kontrak antar-modul: lihat `PORTING.md`.

Keamanan:
- `web/config.js` hanya berisi URL + *publishable key* (memang aman untuk publik).
- Tabel ada di schema `game` yang tidak bisa diakses browser; browser hanya bisa memanggil
  fungsi `public.api_*`. Tujuh di antaranya boleh tanpa login (judul, kota, arketipe, cek username).
- Jangan pernah commit `service_role`/secret key atau password database.
