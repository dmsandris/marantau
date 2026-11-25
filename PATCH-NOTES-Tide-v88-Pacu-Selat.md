# PATCH NOTES — Tide v88 "Pacu Selat"

Sirkuit Selat Lurus di Zentul mendapat wajah dan mesin baru: modul **Pacu Selat Nusantara** (desain Gemini, disetel dan disambungkan Claude), lengkap dengan Galangan Kapal, Bengkel Mesin, Uji Lintasan, Pacu Gugur, dan Adu Kapten **sampai 4 kapten sekaligus, secara langsung**.

Terbuka untuk kapten yang sudah melewati **langkah 40 Mahkota Selat** dan merapat di Zentul.
**Quest Saga 4 tidak berubah**: semua balapan cerita (Turnamen Obor, gerbang bambu, Tembus Jaring, heat IKN) tetap memakai Trektrek-an lama.

## Yang baru untuk pemain

**Arena Pacu**
- **Uji Lintasan 800 m** — gratis 1× per hari game, berikutnya 500 Gold. **Uji Lintasan 1,4 km** — 500 Gold. Masuk Papan Rekor.
- **Pacu Gugur 400 m** — empat babak per pekan: Pariopelan → KapalMber → cangcimen → Yaptob (YusaintJolt). Kalah = gugur sampai Senin. Juara: 12 Oli Hitam + 120.000 Gold.
- **Adu Kapten** — rombongan 2–4 kapten di Dermaga Zentul. Tuan rombongan mengajak, yang lain menerima, lalu tuan memasang obor. Semua kapal berangkat dari jam server yang sama; kapal lawan terlihat bergerak langsung. Taruhan 15.000 Gold per kapten, juara membawa seluruh pot dan +1 Medali. Kalau tak ada yang sampai Finish, taruhan kembali. Maksimal 10 Adu per hari game.

**Galangan Kapal** — 5 kelas kapal pacu: Sekoci Kayu Standar (bawaan), Pencalang Lancang 1,25 jt, Kolek Kilat Zentul 2,1 jt, Lancang Kuning Sultan 3,1 jt, Bahtera Petir Selat 4 jt. Beli sekali, pakai bergantian.

**Bengkel Mesin** — 10 komponen (220 rb s/d 2,4 jt), setelan rasio gigi (Sprint 400 / Seimbang 800 / Panjang 1,4 km), Uji Geber. Mesin yang **jebol** saat balapan harus direparasi (100.000 Gold) sebelum bisa berlomba lagi.

**Medali & Rekor** — tukar Medali (Gigi Jaring, Rantai Biru, Oli Hitam), Papan Rekor 400 m / 800 m / 1,4 km, riwayat 10 pacuan terakhir.

## Penyetelan dari desain Gemini

- **Bug selisih satu tick diperbaiki**: ketukan kini diterapkan sebelum langkah fisika berikutnya, sama persis dengan hitungan server. Diuji di browser: layar 15,408 dtk = server 15,408 dtk.
- **Fisika disetel**: 800 m Sekoci polos ±14,7 dtk, Bahtera Petir 10 komponen ±10,8 dtk (pemain rata-rata). Selisih kelas dan komponen dirapatkan supaya keterampilan oper gigi tetap menentukan. Dorongan start diturunkan supaya daun hijau gigi 1 terasa. Gigi 5 hanya memanas saat Semburan.
- **Adu serentak mengikuti jam server**, bukan jumlah frame, jadi HP lambat tetap sinkron.
- Lawan AI membidik tiap gigi dari undian kapalnya sendiri (tidak lagi sama setiap balapan).
- Kelas 5 kembali bernama **Bahtera Petir Selat**; YusaintJolt tetap kapal pribadi Yaptob.
- Teks **"Finis" menjadi "Finish"**.

## Gerbang GM

| Kunci | Bawaan | Arti |
|---|---|---|
| `PacuSelatOpen` | `0` | `1` = buka untuk semua yang lewat langkah 40. Selama `0`, hanya akun di `FiturPenguji`; yang lain tetap membuka gelanggang lama |
| `PsUjiBiaya` / `PsUjiGratis` | 500 / 1 | biaya Uji Lintasan, jatah gratis Uji 800 per hari game |
| `PsTaruhan` | 15000 | taruhan Adu per kapten |
| `PsAduMaks` | 10 | Adu per kapten per hari game |
| `PsReparasi` | 100000 | reparasi mesin jebol |
| `PsSetorDetik` | 90 | batas setor catatan Adu sesudah meriam |
| `PsUndanganDetik` | 60 | umur ajakan rombongan |
| `PsMulaiJedaMs` | 6000 | jeda dari "Mulai" sampai hitung mundur |
| `PsHarga_<id>` | (kosong) | ganti harga kapal / komponen tanpa ubah kode |
| `GugurTutup`, `GugurHadiahOli`, `GugurHadiahGold`, `MedaliAdu` | — | dipakai bersama gelanggang lama |

## Catatan teknis

- Migrasi `0109-pacu-selat.sql`: tabel `ps_pemain`, `ps_run`, `ps_rekor`, `ps_riwayat`, `ps_gugur`, `ps_room`, `ps_room_anggota`, `ps_kas` (jejak uang). API `api_pacuSelat`.
- Fisika server `game.ps_spesifikasi` / `game.ps_input` / `game.ps_sim` adalah kembaran persis `window.PacuSelat.sim`. Tes `0109` membandingkan 60 spesifikasi, 45 simulasi (log manusia tiruan + log acak), dan 12 balapan lawan AI.
- Realtime: kanal privat `pacu:<room>`, fungsi `public.mt_rt_pacu_ok`, kebijakan "marantau kirim pacu" (juga di `tools/vps/fixups-vps.sql`). Bila kanal belum tersambung, posisi lawan lewat RPC `pos` tiap 0,4 dtk.
- Klien: `web/src/PacuSelat.html` (modul), `web/src/PacuSelatHost.html` (tuan rumah + ajakan), sambungan di `CitiesSaga4.html` (bangunan Sirkuit) dan `JavaScript.html` (inbox).
- Uji browser lokal: Uji 800, Adu 2 kapten, dan Adu 4 kapten (4 browser) berjalan sampai hasil.
- Belum: tanda jasa *Sang Pacu Selat* / *Juara Gelanggang* masih dihitung dari gelanggang lama; Panel Ops belum membaca `ps_kas`.
