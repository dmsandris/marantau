# Tide v87 · Batas menang harian kasino bisa diubah dari Panel GM

- **Panel GM → Kasino Mutiara:** kolom "Batas menang bersih per hari nyata" (100.000 s/d 100.000.000 gold), catatan perubahan wajib, konfirmasi sebelum simpan, riwayat perubahan. Berlaku langsung, termasuk sisa hari ini. Tidak tampil ke pemain.
- **Server:** aksi `['limit', angka, catatan]` di `api_gmKasino`, khusus GM, tercatat di tabel baru `game.kasino_limit_audit` dan log GM. Config yang diubah: `KasinoMenangHarian`.
- **Ops (perlu "VPS deploy"):** tab Kasino tidak lagi memakai angka 2,5 jt tetap. Merah/kuning di "Per kapten" mengikuti batas aktif, catatan ikut berubah, ada blok "Audit perubahan batas menang harian". Penjaga: ambang "Menang besar" = maks(5 jt, 2× batas), teks konteks AI tidak lagi menyebut 2,5 jt.
- **Tes:** `0104` memeriksa hak GM, validasi rentang dan catatan, audit, batas tidak bocor ke pemain, Ops membaca batas baru.
