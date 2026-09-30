/**
 * CommodityData.gs
 * ------------------------------------------------------------------
 * Katalog komoditas dagang untuk Fase 1. Harga dasar per-kota di-seed
 * ke sheet Market oleh SetupSheets.gs (lihat MARKET_SEED_PRICES).
 *
 * `flavor` ditambahkan terinspirasi dari cara Tradewinds 2 memberi
 * kepribadian ke tiap barang dagangan, bukan cuma nama & angka -
 * ditampilkan di panel Market (lihat JavaScript.html).
 * ------------------------------------------------------------------
 */

var COMMODITIES = [
  { id: 'sugar',  name: 'Sugar',  flavor: 'Manis, berat, dan selalu dicari dapur istana.' },
  { id: 'silk',   name: 'Silk',   flavor: 'Halus seperti bisikan, mahal seperti janji bangsawan.' },
  { id: 'spices', name: 'Spices', flavor: 'Aroma yang membuat pedagang jauh rela berlayar.' },
  { id: 'rum',    name: 'Rum',    flavor: 'Bahan bakar kru sekaligus mata uang tidak resmi pelabuhan.' },
  { id: 'tools',  name: 'Tools',  flavor: 'Tidak glamor, tapi setiap pemukiman baru membutuhkannya.' },
  { id: 'arms',   name: 'Arms',   flavor: 'Diperlukan untuk melindungi diri - atau merampas milik orang lain.' }
];

/**
 * Harga dasar per kota. Sengaja dibedakan supaya ada peluang arbitrase
 * dasar (mis. Sugar & Rum murah di Joungjava karena Agricultural,
 * Tools & Arms mahal di Bjorneo karena Remote).
 *
 * Kota baru (lihat migrateAddCitiesRound2() di SetupSheets.gs):
 *   - skitraw: "kota besar penuh sukacita" - SEMUA komoditas tersedia
 *     (barang terlengkap), harga dipatok di sekitar rata-rata kota lain
 *     (pasar yang stabil & adil, bukan yang termurah atau termahal).
 *   - toogood: "kota penyamun" - cuma jual barang kasar (arms/rum/tools/
 *     sugar, TANPA silk/spices yang terlalu mewah untuk kota bandit),
 *     Arms sengaja dipatok jauh lebih murah dari kota manapun (plus
 *     diskon struktural tambahan di MarketService.gs supaya "selalu
 *     lebih murah" tetap benar walau base price di-tweak admin nanti).
 *   - ikn: "ibu kota lama yang tumbang" - semua komoditas masih ada
 *     (sisa infrastruktur ibu kota), tapi harga naik mencerminkan
 *     kelangkaan pasca-runtuh.
 */
var MARKET_SEED_PRICES = {
  sunda_empire: { sugar: 100, silk: 250, spices: 180, rum: 90,  tools: 150, arms: 300 },
  joungjava:    { sugar: 70,  silk: 300, spices: 120, rum: 60,  tools: 180, arms: 340 },
  bjorneo:      { sugar: 110, silk: 280, spices: 220, rum: 100, tools: 220, arms: 380 },
  skitraw:      { sugar: 95,  silk: 280, spices: 175, rum: 85,  tools: 185, arms: 340 },
  toogood:      { sugar: 105, rum: 70,   tools: 200,  arms: 160 },
  ikn:          { sugar: 130, silk: 320, spices: 240, rum: 115, tools: 260, arms: 400 }
};

function getCommodityById(id) {
  for (var i = 0; i < COMMODITIES.length; i++) {
    if (COMMODITIES[i].id === id) return COMMODITIES[i];
  }
  return null;
}

function getAllCommodities() {
  return COMMODITIES.slice();
}
