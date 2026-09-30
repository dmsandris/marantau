/**
 * ArchetypeData.gs
 * ------------------------------------------------------------------
 * 8 starting archetype - lihat GDD §2.3. Ini HANYA starting advantage
 * + perk permanen. Stat bisa berubah jauh lewat Books nanti (Fase 2).
 *
 * `bio` ditambahkan terinspirasi dari cara Tradewinds 2 memperkenalkan
 * tiap karakter pre-made dengan cerita singkat sebelum dipilih, bukan
 * cuma daftar bonus stat kering - lihat TRADEWINDS2_RESEARCH.md.
 * ------------------------------------------------------------------
 */

var BASE_STATS = {
  Trading: 35, Negotiation: 35, Navigation: 35,
  Sailing: 35, Combat: 35, Luck: 15, Knowledge: 5
};

var ARCHETYPES = [
  {
    id: 'merchant', name: 'The Merchant',
    tagline: 'Naluri dagang sejak lahir.',
    bio: 'Lahir di keluarga pedagang kain di Sunda Empire, kamu belajar menawar sebelum belajar berenang. Buku besar dan neraca timbangan lebih akrab di tanganmu daripada pedang.',
    bonuses: { Trading: 15 },
    perkName: 'Market Sense',
    perkDesc: 'Setiap masuk kota baru, melihat 1 barang dengan perubahan harga terbesar.'
  },
  {
    id: 'navigator', name: 'The Navigator',
    tagline: 'Mengenal laut lebih baik dari daratan.',
    bio: 'Dari kecil kamu dibesarkan di atas geladak, membaca bintang dan arus lebih fasih daripada membaca peta darat. Kapten mana pun akan berebut punya juru mudi sepertimu.',
    bonuses: { Navigation: 15 },
    perkName: 'Sea Reader',
    perkDesc: '-10% peluang terkena sea event berbahaya.'
  },
  {
    id: 'pirate', name: 'The Pirate',
    tagline: 'Dulunya bukan orang baik-baik.',
    bio: 'Bendera hitam pernah jadi rumahmu sebelum kamu memutuskan berhenti - atau begitu ceritanya. Reputasi lama masih mengikuti, dan tidak semua orang percaya kamu sudah berubah.',
    bonuses: { Combat: 15 },
    perkName: 'Intimidation',
    perkDesc: 'Pirate encounter membuka opsi negosiasi khusus.'
  },
  {
    id: 'explorer', name: 'The Explorer',
    tagline: 'Mengejar peta, bukan gold.',
    bio: 'Gold cuma bahan bakar untuk mendanai pelayaran berikutnya. Yang kamu kejar adalah pulau yang belum ada di peta manapun, dan legenda yang belum ada yang membuktikan benar.',
    bonuses: { Luck: 10, Navigation: 10 },
    perkName: 'Treasure Hunter',
    perkDesc: 'Akurasi treasure clue lebih tinggi.'
  },
  {
    id: 'gambler', name: 'The Gambler',
    tagline: 'Semua atau tidak sama sekali.',
    bio: 'Kapal ini sendiri dimenangkan lewat taruhan kartu di pelabuhan yang lebih baik dilupakan. Hidup aman itu membosankan - kamu lebih suka taruhan besar dengan risiko yang sepadan.',
    bonuses: { Luck: 10 },
    perkName: 'High Roller',
    perkDesc: 'Reward event langka +30%, tapi event negatif juga +20%.'
  },
  {
    id: 'smuggler', name: 'The Smuggler',
    tagline: 'Kenal orang-orang yang tepat.',
    bio: 'Ada pintu belakang di setiap pelabuhan yang kamu tahu caranya masuk, dan orang-orang di sana lebih percaya kamu daripada percaya pejabat kota. Untung besar datang dengan risiko yang sepadan.',
    bonuses: { Negotiation: 10 },
    perkName: 'Underworld Connections',
    perkDesc: 'Black Market lebih murah, tapi reputasi dari misi walikota -20%.'
  },
  {
    id: 'diplomat', name: 'The Diplomat',
    tagline: 'Kata-kata adalah senjata terbaik.',
    bio: 'Dibesarkan di lingkaran istana sebelum memilih laut lepas, kamu tahu persis bagaimana bicara dengan gubernur dan bangsawan. Pintu yang tertutup untuk orang lain, terbuka untukmu.',
    bonuses: { Negotiation: 10 },
    perkName: 'Silver Tongue',
    perkDesc: 'Peluang negosiasi saat combat lebih tinggi.',
    startingReputationBonus: 5
  },
  {
    id: 'adventurer', name: 'The Adventurer',
    tagline: 'Generalist yang siap segalanya.',
    bio: 'Kamu belum tahu jadi apa nanti - pedagang, pemburu harta, atau legenda laut - dan itu justru yang membuatmu berangkat. Serba bisa, tidak istimewa di satu hal, tapi tidak lemah di manapun.',
    bonuses: { Sailing: 10, Combat: 5 },
    perkName: 'Bold Sailor',
    perkDesc: '-10% waktu perjalanan di rute berisiko (aktif setelah Ship System, Fase 3).'
  }
];

function getArchetypeById(id) {
  for (var i = 0; i < ARCHETYPES.length; i++) {
    if (ARCHETYPES[i].id === id) return ARCHETYPES[i];
  }
  return null;
}
