# Tide v91 — Pacu Selat: gulir tidak lompat, sorotan kapal tidak berpindah

Hanya klien (`PacuSelat.html`, `PacuSelatHost.html`). Server dan migrasi tidak berubah.

## Masalah
1. **Sorotan kapal berpindah sendiri (laptop).** Menyorot kapal yang belum dimiliki (mis. Bahtera Petir Selat) kembali ke Sekoci Kayu Standar tiap 3–5 detik. Penyebabnya: tiap pembaruan status (poll 4 detik), kode mereset sorotan bila kapal tidak ada di daftar milik.
2. **Layar menggulir ke atas sendiri (HP, Safari iPhone).** Tiap pembaruan, seluruh isi tab dibangun ulang. Tinggi halaman menyusut sesaat, dan Safari iOS melempar posisi gulir ke atas.

## Perbaikan
- Sorotan hanya di-reset bila id kapal tidak dikenal. Kapal belum dimiliki boleh disorot.
- Setiap render tab (arena, galangan, bengkel, rekor, dan render keseluruhan) mencatat posisi gulir sebelum membangun ulang, lalu mengembalikannya.
- Host tidak lagi memanggil `PacuSelat.update` bila status yang didorong sama persis dengan sebelumnya (poll 4 detik yang tidak membawa perubahan tidak membangun ulang layar).

## Uji
- Peramban (viewport HP, 15 detik di Galangan): sorotan Bahtera Petir Selat bertahan, gulir 300 px bertahan. Sebelum perbaikan, sorotan kembali ke Sekoci Kayu Standar.
- Gulir ke atas di Safari iOS tidak bisa ditiru di Chromium. Perbaikannya mengembalikan posisi gulir setelah tiap render, tetapi mohon dicoba di iPhone.
- `test/0109-pacu-selat.test.js` lulus.
