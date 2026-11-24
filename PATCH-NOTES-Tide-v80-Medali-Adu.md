# Tide v80 · Medali Adu Kapten

**Isi**
- Juara Adu Kapten (Selat Lurus / Sirkuit Zentul) mendapat **1 Medali**. Hanya bila kedua catatan masuk; menang WO (lawan tidak menyetor) tidak dapat medali. Sekali per adu.
- Tukar di lobi Adu Kapten:
  - 25 Medali = 1 Gigi Jaring (hanya saat tahap Warlord terbuka)
  - 35 Medali = 1 Rantai Biru (sama)
  - 10 Medali = 1 Oli Hitam
- Penukaran mengikuti batas simpan Warlord (`WarlordDropMax`, 12) dan ruang muatan kapal.
- Kurs dan hadiah bisa diubah di `game.config`: `MedaliAdu`, `MedaliGigi`, `MedaliRantai`, `MedaliOli`.

**Teknis**
- Migrasi `0099-medali-adu.sql`: tabel `game.medali`, pembungkus `trek_adu_hitung` dan `trek_adu_lobi`, `api_medali(['tukar', 'gigi'|'rantai'|'oli', jumlah])`.
- Klien: kotak Medali di lobi Adu (`Trek.html`).
- Test: `test/0099-medali-adu.test.js`.

**Catatan**
- Medali dihitung mulai dari rilis ini; adu lama tidak dihitung ulang.
