# Tide v90 — Adu Kapten: kategori jarak dan hadiah tetap

Migrasi baru: `supabase/migrations/0114-pacu-selat-hadiah-adu.sql`. Fisika tidak berubah.

## Kategori jarak
Tuan rombongan memilih **400 m / 800 m / 1,4 km** di lobi Adu Kapten.
- Pilihan dibuat sebelum mengajak (dikirim bersama aksi `ajak`).
- Selagi rombongan masih di lobi, tuan bisa menggantinya (aksi baru `jarakRb`).
- Anggota hanya melihat pilihan tuan. Undangan juga memuat jaraknya.

## Hadiah Juara 1
Hanya Juara 1 yang mendapat hadiah.

| Jarak | Hadiah dasar (2 kapten) |
|---|---|
| 400 m | 10.000 Gold + 2 Rantai Biru |
| 800 m | 15.000 Gold + 3 Rantai Biru |
| 1,4 km | 20.000 Gold + 5 Rantai Biru |

Pengali jumlah kapten: 2 kapten ×1, 3 kapten ×2, 4 kapten ×3.
Contoh: 1,4 km dengan 4 kapten, Juara 1 membawa pulang 60.000 Gold + 15 Rantai Biru.

Aturan tambahan:
- Rantai Biru (`qi_mk_rantai`) masuk langsung ke inventori. Batas muatan tidak berlaku untuk hadiah ini.
- Hadiah baru diberikan bila **minimal dua catatan masuk**. Menang tanpa lawan menyetor (WO) tidak mendapat hadiah.
- Bila ada seri waktu Finish, hadiah dibagi rata.
- Taruhan masuk lomba dihapus. Kunci baru `PsAduTaruhan` = 0, GM masih bisa mengisinya, dan tanpa catatan taruhan tetap dikembalikan.
- `PsTaruhan` (15.000) tidak dipakai lagi.
- Medali Adu di ruang ini dicabut. Medali dari Trektrek-an (Saga 4) tetap.

## Angka bisa diubah GM lewat `game.config`
`PsAduHadiah400`, `PsAduHadiah800`, `PsAduHadiah1400` (Gold) dan `PsAduRantai400`, `PsAduRantai800`, `PsAduRantai1400` (Rantai Biru).

## Klien
- Pemilih kategori di lobi menampilkan hadiah dasar tiap jarak dan hadiah Juara 1 sesuai jumlah kapten.
- Popup undangan menampilkan jarak, kartu hasil menampilkan "+X Gold & +Y Rantai Biru", dan judul balapan memakai "1,4 km".

## Perhatian
- Hadiah dicetak server, tanpa taruhan. Dua akun yang saling adu bisa mengumpulkan Gold dan Rantai, dengan batas `PsAduMaks` (10 adu per hari per pemain).
- 15 Rantai dari satu kemenangan sudah melebihi bahan Warlord (12 Rantai), sehingga jalur Rantai dari Medali dan Sirkuit jadi kurang berarti.
- Batas simpan `WarlordDropMax` (12) tetap berlaku untuk tukar Medali, tetapi tidak untuk hadiah ini.

## Uji
`test/0109-pacu-selat.test.js` diperbarui:
- 800 m dengan 4 kapten: 45.000 Gold + 9 Rantai.
- 1,4 km dengan 2 kapten: 20.000 Gold + 5 Rantai.
- Menang WO tanpa hadiah.
- Ganti kategori oleh tuan, dan penolakan kategori yang tidak dikenal.
- Tabel hadiah dasar, serta 1,4 km dengan 4 kapten = 60.000 Gold + 15 Rantai.
- `0099_idempotent` lulus.
- Peramban: lobi, undangan, dan Adu 1,4 km dua kapten sampai hasil.
