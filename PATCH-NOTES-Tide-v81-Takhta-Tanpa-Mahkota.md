# Tide v81 · Saga 4 Bagian II "Takhta Tanpa Mahkota" (langkah 41–60)

Konsep: `claude/KONSEP-Saga4-Bagian-II-Takhta-Tanpa-Mahkota.md` v1.5 · Rencana: `claude/PLAN-Coding-Saga4-Bagian-II.md`.

## Untuk pemain
- Ending Bagian I (langkah 40) tetap seperti sebelumnya dan kini menjadi *fake ending*. **3 hari game** kemudian, pelikan Ratu Marlya datang lagi: stempel Kumis Hitam memancarkan suar M.A.R.I.E.
- **20 langkah baru** (Q20 Suar di Gagang Stempel, Q21 Mahkota di Dasar Palung, Q22 Takhta Tanpa Mahkota). Pembukaan langkah 41, 47, dan 57 berbeda sesuai pilihan stempel, pilihan Marlya, dan nasib Tedsky dari saga sebelumnya.
- **Navy Pemerintah Dunia** mencegat pelayaran (langkah 42–59), Tier 1–4:
  - 100% di pelayaran ke tujuan langkah, 50% di pelayaran lain.
  - Kabur, suap, dan runding dikunci.
  - Kalah = terseret pulang. Gold dan muatan tetap aman.
  - Tier 4 = dua kapal dalam satu pencegatan.
  - Menang memberi Gold Proporsional + 1–8 Keping Rantau. Setelah 40 Keping dari Navy dalam satu hari game, Keping turun jadi 1 per kemenangan.
  - Meriam Warlord ×5 berlaku melawan Navy.
- **Setoran logistik Q21**:
  - Beras untuk nasi ulam Ama Kerang.
  - Besi + Mesiu untuk Tassyaaa.
  - Oli Hitam + Perkakas untuk Yaptob.
  - Emas + Mutiara untuk Marlya.
  - JackDaniels + JhonnyWalker untuk armada Skitraw.
  - Ransum 300 Beras / 300 Ikan Asin / 150 Tuak, boleh dicicil dengan progress bar.
- **Battle Akhir Bersama** di Teluk Dalam Rantai Lama:
  - Trektrek-an Kilat bersama Barisan Pacu.
  - KPD Tembok Utara dan Selatan.
  - Tiga kapal Algojo, dengan sekutu ikut menembak.
  - Sovereign Mahkota 3 fase (Marlya meruntuhkan perisai, Black Pearl menahan salvo, lalu seluruh aliansi menembak).
  - Kalah atau mundur bisa dilanjutkan dari gelombang terakhir. HP kapal induk tersimpan.
- **Ending sinematik penuh**: pilihan nasib Mahkota Karam, adegan karam, Teluk Dalam berangin, bunga untuk Andry, lalu credit bergulir "Saga Keempat — Lengkap".
- Hadiah:
  - 1,5 jt / 2 jt / 2,5 jt gold.
  - Tanda jasa *Pemecah Blokade*, *Penjaga Janji Rantai Lama*, *Penakluk Sovereign*.
  - Gelar *Penumbang Mahkota*.
  - Rupa Kedai **Layar Hitam-Emas "Takhta Bebas"** (diberikan, tidak dijual).

## Akses
- Gerbang baru `Mahkota2Open` (default `0`). `FiturPenguji` ikut membuka.
- Untuk uji: `update game.config set value = 'abuy,samuelroyy' where key = 'FiturPenguji';`
- Saga 4 Bagian I tetap tertutup bagi pemain baru selama `MahkotaOpen = 0`.

## Teknis
- Migrasi `0100-mahkota2.sql`. Progres disimpan di baris terpisah `player_quests.quest_id = 'mahkota2'` (step 0–20 = langkah 41–60). Baris `mahkota` tidak disentuh, jadi `mk_tamat` (step ≥ 40) dan semua yang bergantung padanya tetap berjalan: Sirkuit, Adu Kapten, Set Jaring Putus, Mesin Jolt dilepas.
- Bungkus (akhiran `_mk2`): `mk_state` (klien tetap melihat satu quest 1–60), `api_mahkota` (aksi langkah 41+ → `game.mk2_act`), `kd_enc` (Navy), `api_resolveCombat` (kabur dikunci, kapal kedua T4, Keping), `quest_boss_defeated` (rangkaian 8 gelombang), `quest_combat_end` (HP kapal induk tersimpan), `kd_req_ok`.
- Kenop: `Mk2JedaHari` 3, `Mk2GoldQ20/21/22`, `MkNavyPct` 50, `MkNavyHp1..4`, `MkNavyDmgKali`, `MkNavyKepingCap` 40, `MkFlagshipHp` 6000, `Mk2BossDmgKali`.
- Alat GM: `select game.admin_mahkota2('username', 47);` (langkah 40–60).
- Klien:
  - `Mahkota.html`: 20 kartu baru, setoran, cicilan, perang, epilog2 + credit.
  - `CinemaMahkota2.html` baru, berisi 7 adegan.
  - `JavaScript.html`: wajah & label Navy di layar tempur.
  - `BalaiKongsi.html`: kartu quest tidak tertimpa render berkala.
  - Sinematik kedatangan Bagian II memakai kunci `mt_seen_mk2c_*`, jadi ikut tersimpan di Buku Adegan.
- Tes: `test/0100-mahkota2.test.js`. Seluruh suite lulus, termasuk `0099_idempotent`.

## Beda dari konsep (disengaja)
- Trektrek-an Kilat dimainkan **sebelum** duel KPD Tembok Utara (membuka barikade), bukan di antara dua duel. Alasannya, mesin tempur tidak bisa menyisipkan balapan di tengah rangkaian pertempuran.
- Sinematik kedatangan langkah 47 diputar **setelah** kapal sandar, bukan 1,5 detik sebelumnya, karena Navy bisa mencegat di detik kedatangan dan kedua layar akan bertumpuk.
- Langkah 55 tanpa sinematik terpisah: pertempurannya adalah pencegatan Navy Tier 4 itu sendiri.
