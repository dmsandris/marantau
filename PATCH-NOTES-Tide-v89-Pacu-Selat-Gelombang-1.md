# Tide v89 — Pacu Selat Gelombang 1

Perbaikan tampilan dan rasa main Pacu Selat (konsep: KONSEP-Pacu-Selat-15-Improvement, butir 1, 2, 3, 7, 10, 11).
Fisika, server, dan migrasi **tidak berubah**. Hasil klien tetap sama persis dengan hitungan server.

## Yang berubah

### Tampilan PC (layar lebar ≥ 740 px)
- Kanvas balap lebih tinggi (sampai 68vh / 660 px).
- Tachometer dan knot meter jauh lebih besar (jari-jari sampai 100 px, sebelumnya maks 60 px).
- Tombol oper gigi dan Semburan Oli jadi panel ringkas di kanan bawah. Pelat SEMBURAN di dalam kanvas dihapus karena tombolnya sudah menunjukkan status.
- Teks tombol dipadatkan.

### 1. Lampu oper
- Permata tunggal diganti 5 lampu kuningan di atas tachometer.
- Lampu menyala bertahap saat putaran naik.
- Kelima lampu hijau di daun ✓, emas berkedip di bintang ★, merah sesudah zona hijau.

### 2. Umpan balik oper gigi
- Guncangan kamera singkat dan kilatan warna: emas untuk Sempurna, hijau untuk Tepat, jingga/merah untuk Awal/Telat.
- Getar HP (navigator.vibrate) dengan pola berbeda.
- Tulisan melayang naik dari kapal pemain, lengkap dengan bonus knot yang dihitung dari akselerasi kapal.
- Semua efek dimatikan bila sistem meminta gerak dikurangi (reduced motion).

### 3. Peringatan panas
- Sekitar 0,6 detik sebelum mesin batuk muncul vinyet merah berdenyut, spanduk "♨ PANAS — OPER GIGI SEKARANG!" (atau "LEPAS SEMBURAN!" di gigi 5), dan desis uap.
- Busur panas di tachometer menebal dan berkedip, dan tombol oper ikut menyala merah.
- Rumus peringatan memakai rumus suhu yang sama dengan simulasi.
- Tidak muncul bila ECU sudah anti batuk penuh.

### 7. HP
- Tombol ringkas tetap dua kolom di bawah kanvas.
- Tombol "⇄ jempol" memindahkan Semburan ke sisi jempol kiri atau kanan; tombol di sisi jempol dibuat lebih lebar.
- Pilihan disimpan di perangkat (localStorage `mt_pacu_jempol`).
- Isi tahan Semburan terlihat langsung di tombolnya.

### 10. Menara peringkat P1–P4
- Muncul di kiri atas untuk Adu Kapten dan Pacu Gugur.
- Menampilkan nama, warna lajur, dan jarak ke kapal di depan.
- Kapal yang sudah Finish menampilkan waktunya, dan yang jebol ditandai JEBOL.
- Warna kapten sama di menara, peta mini, dan label kapal: pemain emas, lawan biru / merah muda / ungu.
- Adu langsung: siaran posisi Realtime kini ikut membawa waktu Finish (`f`) dan tanda jebol (`j`). Cadangan RPC tidak berubah.

### 11. Kartu hasil kaya
- Grafik kecepatan-waktu dengan penanda tiap oper gigi, diwarnai menurut mutunya.
- Chip waktu reaksi start (atau tanda curi start) dan selisih terhadap rekor pribadi yang tercatat sebelum balapan.
- Chip pemakaian Semburan.
- Satu kiat dari Yaptob, memilih yang paling berharga: jebol, curi start, oper telat, oper awal, reaksi lambat, Semburan tak dipakai, atau kejar bintang.
- Tombol "PACU LAGI" dipindah ke depan dan dibuat lebih menonjol, dengan pintasan Enter di PC.
- Baris tombol menempel di bawah kartu supaya tidak terpotong.

## Berkas
- `web/src/PacuSelat.html`: modul (CSS, HUD, efek, menara, kartu hasil, tata jempol).
- `web/src/PacuSelatHost.html`: callback `onJempol` dan `tataJempol`, siaran posisi `f`/`j`.

## Uji
- `test/0109-pacu-selat.test.js`: lulus (60 spesifikasi, 45 simulasi JS = SQL, 12 lawan AI).
- Peramban:
  - PC 1440×900: Uji 800 m, Pacu Gugur, dan uji panas sampai jebol.
  - HP 390×844: Uji 800 m.
  - Adu 2 kapten: menara peringkat terisi posisi langsung dan hasil server cocok.
