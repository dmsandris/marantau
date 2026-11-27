# Tide v90 — Adu Kapten: kategori jarak, taruhan, dan Medali Juara 1

Migrasi baru: `supabase/migrations/0114-pacu-selat-hadiah-adu.sql`. Fisika tidak berubah.

## Kategori jarak
Tuan rombongan memilih **400 m / 800 m / 1,4 km** di lobi Adu Kapten.
- Pilihan dibuat sebelum mengajak (dikirim bersama aksi `ajak`).
- Selagi rombongan masih di lobi, tuan bisa menggantinya (aksi baru `jarakRb`). Taruhan ikut berubah.
- Anggota hanya melihat pilihan tuan, dan undangan memuat jarak serta taruhannya.

## Taruhan masuk lomba dan Medali
| Jarak | Taruhan tiap kapten | Medali dasar Juara 1 (2 kapten) |
|---|---|---|
| 400 m | 10.000 Gold | 2 Medali |
| 800 m | 15.000 Gold | 3 Medali |
| 1,4 km | 20.000 Gold | 5 Medali |

Pengali jumlah kapten: 2 kapten ×1, 3 kapten ×2, 4 kapten ×3.
- Gold: Juara 1 membawa seluruh pot (taruhan × jumlah kapten), jadi untung bersih = taruhan × (kapten − 1). Tidak ada Gold yang dicetak server.
- Medali: dasar × (kapten − 1).
- Contoh: 1,4 km dengan 4 kapten, pot 80.000 (untung bersih 60.000 Gold) + 15 Medali.
- Hanya Juara 1 yang menerima. Kapten lain kehilangan taruhan dan tidak dapat Medali. Seri dibagi rata.
- Medali diberikan bila minimal dua catatan masuk. Menang WO hanya mendapat pot.
- Tanpa catatan sama sekali, taruhan dikembalikan.

## Angka bisa diubah GM lewat `game.config`
`PsAduTaruhan400`, `PsAduTaruhan800`, `PsAduTaruhan1400` (Gold) dan `PsAduMedali400`, `PsAduMedali800`, `PsAduMedali1400`.
`PsTaruhan` lama (15.000) tidak dipakai lagi. `MedaliAdu` (1) tidak dipakai di ruang ini, tetapi tetap dipakai Trektrek-an Saga 4.

## Klien
- Pemilih kategori di lobi menampilkan taruhan dan Medali tiap jarak, serta hasil Juara 1 sesuai jumlah kapten.
- Popup undangan menampilkan jarak dan taruhan.
- Kartu hasil menampilkan untung bersih Gold dan Medali.
- Judul balapan memakai "1,4 km".

## Uji
`test/0109-pacu-selat.test.js` diperbarui:
- 800 m dengan 4 kapten: pot 60.000 dan 9 Medali.
- 1,4 km dengan 2 kapten: untung 20.000 dan 5 Medali.
- Menang WO hanya mendapat pot, tanpa Medali.
- Taruhan ikut berubah saat tuan mengganti kategori.
- Tabel dasar, dan 1,4 km dengan 4 kapten = untung 60.000 + 15 Medali.
- `0099_idempotent` lulus.
