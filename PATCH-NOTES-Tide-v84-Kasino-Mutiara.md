# Tide v84 · Kasino Mutiara (Paradiso)

Konsep: PRD Kasino Mutiara dari pemilik (24 Nov 2026) + `claude/AUDIT-Kasino-Mutiara-2026-11-24.md` (project docs). Keputusan pemilik: batas menang 2,5 jt per **hari nyata**, taruhan maks 100.000, Edge GM −10% s/d +10%, kuota disembunyikan, meja tambahan "Segera hadir", meja dadu bernama **Duel Dadu Bandar**. Gold tidak pernah bisa dibeli dengan uang asli.

## Untuk pemain
- Kartu **Bank Paradiso** punya pintu baru **Masuk Kasino** (di bawah brankas; kartu VIP quest tetap di atas). Pintu terkunci bila masih ada cicilan Moneylender, dan mati saat kapal berlayar.
- **Lobi Kasino Mutiara**: gold di tangan, brankas (tidak tersentuh), bandar, 4 meja, 5 meja "Segera hadir" (Besar/Kecil, Hi-Lo, Adu Gasing, Baccarat, Undian Kerang), dan **Catatan Kasino** (12 ronde terakhir + total selisih).
- Taruhan seragam: chip 100 / 500 / 1rb / 2,5rb / 5rb, isi sendiri (100–100.000), tombol ½, 2×, Max. Nilai taruhan diingat per perangkat.
- **Duel Dadu Bandar**: 2 dadu lawan 2 dadu, menang 1:1, seri kembali.
- **Roulette Mutiara**: papan lengkap — angka 1–36 (35:1), tiga lusin (2:1), merah/hitam, genap/ganjil, 1–18/19–36 (1:1). Chip bisa disebar ke beberapa tempat sekaligus (maks 16), tombol Batal, Kosongkan, Ulangi. Kantong ◆ mutiara milik bandar (tidak bisa dipasang). Di ponsel papan angka 3 kolom.
- **Blackjack**: 6 dek dikocok ulang tiap ronde, bandar berhenti di 17, Blackjack 3:2, bandar mengintip As/10, Hit / Stand / Double (dua kartu pertama). Ronde yang ditinggal: stand otomatis setelah 120 detik, atau saat berlayar. Penghitung waktu tampil di meja.
- **Slot Mutiara**: tuas bisa ditarik (seret) atau tekan Spasi. Tabel bayar baru: 3 Mutiara 50×, 3 Jangkar 30×, 3 Kompas 20×, 3 Bir 12×, 3 Kerang 6×, 2 Mutiara 3×, 1 Mutiara 1× (taruhan kembali).
- Setelah menang bersih menyentuh batas harian, bandar menutup meja diam-diam sampai 00:00 WIB. Angka batas tidak pernah tampil.
- Lapau Paradiso punya gosip kasino baru.

## Server (`0104-kasino-mutiara.sql`)
- Tabel `game.kasino_round` (money trace per ronde: `gold_before`, `bet_amount`, `payout_amount`, `net_delta`, `gold_after`, `edge_applied`, `capped`, `state_json`), `game.kasino_daily` (ringkasan harian per kapten untuk cek kuota & jeda O(1)), `game.kasino_edge_audit`.
- `api_kasino`: `status`, `dadu`, `roulette`, `slot`, `bj`, `bjact`. Semua hasil dihitung server; kartu tertutup bandar & sepatu tidak pernah dikirim. Nonce ganda mengembalikan hasil ronde yang sama.
- Penjaga urut: `KasinoOpen` (FiturPenguji ikut), era Pasir `kini`, kota `paradiso`, tidak berlayar/tidak ada pertempuran, tanpa utang Moneylender, kuota harian. Lalu per meja `KasinoOpen<Meja>`, taruhan `KasinoMinBet`..`KasinoMaxBet`, gold di tangan cukup, satu ronde Blackjack aktif, jeda `KasinoJedaMs` (700 ms).
- **Edge** per meja `KasinoEdge<Meja>` (−0,10..+0,10). Tabel bayar tidak berubah; Edge diterapkan lewat peluang:
  - Dadu: peluang seri 146/1296, peluang menang non-seri `(1 − e/(1−t))/2`.
  - Roulette: e ≥ 0 → kantong 0 muncul dengan peluang e; e < 0 → bola diarahkan ke kantong terbaik taruhan kapten dengan peluang `−e / EV terbaik`.
  - Slot: RTP dasar gulungan 1,1018 (bobot 2/2/3/7/7 dari 21); dengan peluang `1 − (1−e)/R0` hasil diganti kombinasi kalah.
  - Blackjack: "dorongan kartu" k dari tabel kalibrasi `tools/sim-kasino.js` (1,5 jt tangan per titik, basic strategy). Aturan dasar (k = 0) ≈ Edge +1%.
- Batas menang `KasinoMenangHarian` (2,5 jt) per hari nyata WIB (`game.hr_today()`); bayaran dipotong ke sisa kuota (`capped`).
- `api_gmKasino`: `status` (gerbang, Edge, statistik + alarm RTP berbasis skor-z > 4σ setelah `KasinoAlarmMinRonde` ronde, menang bersih hari ini, audit), `edge` (wajib catatan, tercatat di audit), `gate`.
- `th_sail_guard` dibungkus: berlayar menyelesaikan ronde Blackjack aktif (stand).
- Kunci state `kasino` di `api_getGameState` hanya `{on:true}` (tanpa angka).

## Akses
- **`KasinoOpen` bawaan `0`.** Uji dulu lewat `FiturPenguji` (mis. `abuy`), lalu buka dari Panel GM → Kasino Mutiara → centang "dibuka untuk semua pemain".

## Panel GM (`GmKasino.html`)
- Bagian **Kasino Mutiara**: sakelar kasino & per meja, Edge per meja (slider + angka, label Sink / Netral / Pencetak gold), Catatan Perubahan wajib, konfirmasi ganda untuk Edge negatif, statistik per meja (RTP nyata vs target, z), menang bersih hari ini, riwayat Edge.

## Panel Ops
- Tab baru **Kasino**: ringkasan (sink/faucet/bersih bandar), per meja (RTP nyata vs target), jejak ronde dengan saringan kapten/meja/status, per kapten (merah bila menyentuh batas), per hari 30 hari, audit Edge.
- **Aliran dana** memuat kategori *Menang kasino* / *Kalah kasino* (kelompok Kasino) dari `kasino_round`, plus kolom `kasino_bersih` per kapten. Kasino tidak menulis `player_log` per ronde.
- **Penjaga**: aturan baru *Ritme kasino seperti mesin* (≥ 40 ronde/menit) dan *Menang besar di kasino* (≥ 5 jt bersih atau ≥ 2× kena batas); konteks AI menyebut Kasino Mutiara.
- Perlu **VPS deploy** (berkas `deploy/selfhost/ops/` berubah, Dockerfile menyalin `kasino.js`).

## Tes
- `test/0104-kasino-mutiara.test.js`: gerbang & penguji, kota/laut/utang, batas taruhan, nonce ganda, jeda, Edge tidak bocor, roulette (bayaran, larangan 0), slot (RTP enumerasi = 1,1018, RTP efektif = 1 − Edge), money trace, Blackjack (kartu tertutup, sepatu, double, kedaluwarsa, berlayar), kuota harian (potong, tutup, buka besok, per kapten), tanpa batas kalah, meja ditutup, GM (edge, audit, gate), Monte Carlo benih tetap, kalibrasi Blackjack, query Panel Ops.
- Hasil Monte Carlo (6.000 ronde): Dadu RTP 0,959 / 1,006 / 1,054 dan Roulette 0,937 / 1,000 / 1,048 untuk Edge +5% / 0 / −5%.
