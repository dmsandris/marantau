/**
 * TreasureData.gs — Fase 5 (Exploration & Treasure)
 * ------------------------------------------------------------------
 * Situs harta karun, data-driven sama seperti COMMODITIES di
 * CommodityData.gs. Setiap situs terikat ke SATU CityId yang sudah ada
 * (Cities sheet) - "dig" dilakukan sambil merapat di kota itu, bukan di
 * titik peta baru di luar kota (dipilih supaya tidak perlu mekanik
 * "berlayar ke titik kosong" baru; MapX/MapY kota yang sudah ada sudah
 * cukup untuk memberi rasa lokasi berbeda-beda di dunia).
 *
 * requiresBookKeyword mengacu ke BookCatalog.SpecialEffect (lihat
 * migrateFase5Exploration() di SetupSheets.gs untuk 2 buku decoder baru:
 * 'treasure_decoder_1' untuk situs difficulty 1-2, 'treasure_decoder_2'
 * untuk situs difficulty 3/elite). TANPA buku itu, TreasureService cuma
 * mengembalikan clueHint (samar); DENGAN buku, clueFull terbuka.
 * ------------------------------------------------------------------
 */

var TREASURE_SITES = [
  {
    id: 'site_sunda_reef',
    name: 'Karang Terlantar',
    cityId: 'sunda_empire',
    difficulty: 1,
    requiresBookKeyword: 'treasure_decoder_1',
    clueHint: 'Sesuatu terkubur di karang dangkal tak jauh dari pelabuhan utama Sunda Empire.',
    clueFull: 'Peti besi karatan terkubur sedepa di bawah pasir karang, ditandai bangkai kapal nelayan yang setengah tenggelam sejak dua musim lalu.'
  },
  {
    id: 'site_joungjava_grove',
    name: 'Rimba Sunyi Joungjava',
    cityId: 'joungjava',
    difficulty: 1,
    requiresBookKeyword: 'treasure_decoder_1',
    clueHint: 'Petani setempat bicara soal harta yang dikubur di tepi ladang, dekat pohon tua.',
    clueFull: 'Digali di bawah pohon beringin tunggal di tepi ladang paling utara - akarnya sengaja dibiarkan tumbuh mengelilingi peti supaya tidak dicuri.'
  },
  {
    id: 'site_skitraw_docks',
    name: 'Dermaga Tua Skitraw',
    cityId: 'skitraw',
    difficulty: 2,
    requiresBookKeyword: 'treasure_decoder_1',
    clueHint: 'Rumor pedagang: ada brankas tersembunyi di bawah dermaga tua yang sudah tidak dipakai.',
    clueFull: 'Brankas besi tersembunyi di bawah papan dermaga ketiga dari ujung, diikat rantai ke tiang penyangga supaya tidak hanyut saat pasang.'
  },
  {
    id: 'site_bjorneo_cliffs',
    name: 'Tebing Berkabut Bjorneo',
    cityId: 'bjorneo',
    difficulty: 2,
    requiresBookKeyword: 'treasure_decoder_1',
    clueHint: 'Penduduk lokal menghindari satu gua di tebing - katanya menyimpan sesuatu milik pelaut lama.',
    clueFull: 'Gua di sisi barat tebing, tersembunyi di balik air terjun kecil - peti disegel di ceruk batu paling dalam.'
  },
  {
    id: 'site_toogood_den',
    name: 'Sarang Lama TooGood',
    cityId: 'toogood',
    difficulty: 3,
    requiresBookKeyword: 'treasure_decoder_2',
    clueHint: 'Bekas markas bajak laut yang ditinggalkan - konon penuh jebakan bagi yang tidak siap.',
    clueFull: 'Ruang bawah tanah bekas markas bajak laut, di balik pintu palsu ruang senjata lama - dijaga jebakan mekanis tua yang butuh kehati-hatian ekstra.'
  },
  {
    id: 'site_ikn_ruins',
    name: 'Reruntuhan IKN',
    cityId: 'ikn',
    difficulty: 3,
    requiresBookKeyword: 'treasure_decoder_2',
    clueHint: 'Di antara reruntuhan ibu kota yang tumbang, ada ruang bawah tanah istana yang belum sepenuhnya dijarah.',
    clueFull: 'Ruang perbendaharaan istana lama, tersembunyi di bawah reruntuhan balai kota - sebagian sudah dijarah, tapi bilik terdalam masih tersegel.'
  }
];

function getTreasureSiteById(siteId) {
  for (var i = 0; i < TREASURE_SITES.length; i++) {
    if (TREASURE_SITES[i].id === siteId) return TREASURE_SITES[i];
  }
  return null;
}

function getAllTreasureSites() {
  return TREASURE_SITES.slice();
}
