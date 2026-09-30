# MTFace v2 — spesifikasi data penampilan kapten (Tide v14)

Objek `appearance` (disimpan server, dibersihkan oleh `game.appearance_clean` & `MTFace.sanitize`).
Semua field opsional; nilai tak dikenal -> default. Data lama (v1) harus tetap tampil wajar.

| field      | tipe / rentang | default | arti |
|------------|----------------|---------|------|
| fem        | 0 / 1          | 0       | 0 pria, 1 wanita |
| skin       | int 0..7       | 2       | warna kulit (0..5 = warna v1, 6 sangat terang, 7 sangat gelap) |
| hair       | int 0..9       | 0       | warna rambut (0..5 = warna v1: hitam, coklat tua, coklat, coklat kemerahan, abu, merah; 6 pirang madu, 7 putih perak, 8 hitam kebiruan, 9 kastanye) |
| hairStyle  | int 0..13      | 0       | pria: 0 Pendek,1 Belah samping,2 Klimis,3 Acak,4 Gondrong,5 Botak,6 Kuncir,7 Undercut,8 Keriting,9 Gimbal,10 Jambul tinggi,11 Cepak,12 Ikal panjang,13 Konde pria. wanita: 0 Sanggul,1 Panjang,2 Kepang,3 Pendek,4 Poni,5 Kuncir,6 Bob,7 Keriting,8 Kepang dua,9 Gelombang,10 Pixie,11 Cepol ganda,12 Sibak samping,13 Gimbal |
| facial     | int 0..9       | 0       | (pria saja) 0 Bersih,1 Kumis,2 Jenggot tipis,3 Brewok,4 Kumis tebal,5 Janggut kambing,6 Jambang,7 Janggut kepang,8 Kumis melintir,9 Berewok tipis |
| eyes       | int 0..4       | 0       | bentuk mata: 0 Sedang,1 Sipit,2 Lebar,3 Tajam,4 Sayu |
| iris       | int 0..5       | 0       | warna mata: 0 Coklat,1 Hitam,2 Hazel,3 Hijau,4 Biru,5 Abu |
| brows      | int 0..3       | 0       | alis: 0 Normal,1 Tebal,2 Tipis,3 Tegas |
| head       | string         | 'arch'  | arch, none, hijab, peci, blangkon, bandana, tricorne, kapten, bicorne, plumed, udeng, iket, caping, serban, beret, kupluk, brim, bowler, ikat, tudung |
| outfit     | string         | 'arch'  | arch, jas_kapten, mantel, rompi, kemeja, beskap, kebaya, koko, kulit, seragam, pelaut, jubah |
| cloth      | int 0..9       | 0       | warna pakaian: 0 = warna bawaan pakaian/archetype, 1..9 palet |
| eye        | string         | 'arch'  | arch, none, patch, monocle, glasses, halfmoon |
| ear        | string         | 'arch'  | arch, none, hoop, hoop2, pearl, stud |
| neck       | string         | 'arch'  | arch, none, scarf, chain, pearls, medallion, jabot, tooth, masker |
| mark       | string         | 'none'  | none, scar_cheek, scar_eye, tattoo, freckles, mole, warpaint |
| item       | string         | 'arch'  | arch, none, pipe, parrot, spyglass, sword |
| seed       | int 0..999999  | 0       | variasi kecil (bentuk rahang dsb.) |

`'arch'` = ikuti bawaan archetype (merchant, navigator, pirate, explorer, gambler, smuggler, diplomat, adventurer).
Bawaan archetype (head / outfit-gaya / aksesori):
- merchant: peci, jas saudagar merah-emas, neck chain
- navigator: tricorne, jas navigator biru, (none)
- pirate: bandana, mantel gelap merah, eye patch + ear hoop
- explorer: brim (topi lebar), jaket khaki, neck scarf
- gambler: bowler, jas ungu, item: kartu di topi (khusus arch)
- smuggler: tudung, mantel gelap, neck masker
- diplomat: blangkon, jas gelap, eye glasses
- adventurer: ikat (ikat kepala), jaket hijau, (none)

NPC (ap.role: syahbandar, saudagar, pustakawan, tukang, bankir, lapau, gudang, bajak) memakai ROLE_OUTFIT seperti v1.
Opsi render tambahan (opts): bg(false = transparan), bgColors, arch, fat, clown, medals, frame(bool), size-agnostic viewBox 0 0 100 100.

MTFace API wajib: svg(ap, opts), defaults(name, arch), npc(seedStr, role, forceFem), sanitize(a),
SKIN, HAIR (array warna hex), IRIS, CLOTH (10 warna, index 0 = null/bawaan),
HAIR_M, HAIR_F, FACIAL, EYES, IRIS_N, BROWS (label array),
HEADS, OUTFITS, EYEWEAR, EARS, NECKS, MARKS, ITEMS (array [id, label]),
ARCH_OUTFIT.
