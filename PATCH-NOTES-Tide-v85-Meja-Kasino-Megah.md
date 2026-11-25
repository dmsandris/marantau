# Tide v85 · Meja Kasino Megah

Perbaikan dari uji GM atas Tide v84 (Kasino Mutiara). Hanya klien (`web/src/Kasino.html`), tanpa migrasi.

## Huruf angka
- Semua angka di kasino (gold di tangan, brankas, chip, taruhan, catatan, skor, papan roulette) memakai Cinzel tebal dengan angka sejajar, sama seperti HUD game. Sebelumnya jatuh ke huruf mesin ketik (monospace).

## Tampilan meja
- Semua meja kini berbentuk meja sungguhan: rel kayu berpaku kuningan, beludru hijau dengan cahaya lampu, lambang mutiara samar, tulisan emas melengkung di beludru.
- Lingkar **TARUHAN** dengan tumpukan chip sesuai nominal (Duel Dadu, Blackjack), ikut berubah saat chip dipilih.
- **Duel Dadu Bandar**: papan nama Bandar & Kapten, cangkir kulit berbingkai kuningan yang dikocok saat menunggu, lalu diangkat dan dadu dilempar jatuh-memantul. Medali VS dan skor bulat; pemenang menyala.
- **Blackjack**: kotak sepatu kartu di pojok, kartu dibagi meluncur dari sepatu dengan urutan kapten–bandar–kapten–bandar, kartu tertutup dibalik saat bandar membuka, kartu baru mengikuti. Skor bulat (merah bila bust, emas bila Blackjack, hijau untuk pemenang).
- **Slot** berdiri di atas meja beludru.

## Roulette Mutiara
- Roda baru: cincin angka, cincin kantong bersekat kuningan, kerucut kayu berjeruji, mangkuk dengan lintasan bola terpisah dan 8 berlian pemantul. Tengah roda menampilkan angka hasil dengan warna (merah/hitam/hijau).
- **Gerak bola diperbaiki**: roda dan bola dipercepat halus sejak tombol ditekan; saat hasil server tiba, sudut bola relatif terhadap roda mengikuti kurva Hermite kubik (kecepatan tersambung tanpa sentakan, berhenti tepat di kantong hasil), roda melambat konstan, bola turun dari lintasan ke kantong sambil memantul. Tidak ada lagi bola berbalik arah atau berhenti lalu meloncat. Diuji: bola selalu berhenti tepat di kantong angka yang dikirim server (selisih < 0,02°).
- Papan seperti meja asli: kolom ◆ (kantong bandar, tidak bisa dipasang), baris 3-6-9…36 di atas. Di ponsel papan 3 kolom dan layar menggulir ke roda saat berputar.
- **Taruhan tetap di papan** setelah putaran (seperti meja sungguhan). Tombol baru **2× Semua**; Batal & Kosongkan tetap.
- Kotak taruhan yang menang berkedip; pesan hasil menyebut berapa taruhan yang kena dan total bayaran.
- Riwayat 10 angka terakhir di bawah roda.
