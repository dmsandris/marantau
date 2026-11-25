# Tide v86 · Papan Gambler + pengecekan lengkap Kasino di Ops

## Lobi Kasino Mutiara
- Papan **Gambler Hari Ini** (top 3) dan **Gambler Pekan Ini** (top 1, Senin–Minggu WIB) di menu depan, di bawah Bandar.
- Peringkat berdasar **total taruhan**, bukan menang bersih. Alasan: menang bersih dibatasi 2,5 jt/hari sehingga banyak kapten seri di batas, dan angkanya akan membocorkan kuota yang sengaja disembunyikan. Papan hanya menampilkan nama, total taruhan, jumlah ronde, dan penanda "(kamu)".
- Server: `game.ks_papan()` (dari `kasino_daily`, ada indeks baru `kasino_daily_day_idx`), dikirim lewat `ks_status` → `kasino.papan`. Migrasi `0104` diperbarui di tempat (idempotent).

## Panel Ops, tab Kasino (perlu "VPS deploy")
Ditambahkan di atas bagian lama: Alarm statistik per meja (z-score), Gerbang & konfigurasi (semua kunci `Kasino*` + `FiturPenguji`), Blackjack berjalan (umur vs batas detik), Papan gambler (10 teratas + menang bersih, hanya GM), Kuota menang harian per kapten, Ronde menang terbesar, Kapten paling menyimpang (z, min 100 ronde).
Bagian lama tetap: ringkasan, per meja, jejak ronde, per kapten, per hari, audit Edge.

## Tes
`test/0104-kasino-mutiara.test.js`: papan (urutan, 1..3 baris, penanda kamu, tanpa kebocoran net/kuota, batas pekan, data 8 hari lalu tidak ikut) dan semua query Ops baru.
