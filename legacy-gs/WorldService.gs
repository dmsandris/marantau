/**
 * WorldService.gs
 * ------------------------------------------------------------------
 * Data dunia yang SAMA untuk semua pemain (shared world) - Cities,
 * dan nanti Market/Missions global di fase berikutnya.
 *
 * getCities() dipanggil di HAMPIR setiap refresh state (game load,
 * travel, dll), padahal datanya jarang berubah - jadi di-cache pakai
 * CacheService supaya game state loading lebih ringan/cepat ("smooth"),
 * terutama kalau nanti banyak pemain sekaligus. Cache otomatis
 * kadaluarsa 5 menit, dan langsung di-invalidate begitu admin mengedit
 * sheet Cities (lihat onEdit di Code.gs) - jadi update foto/nama kota
 * tetap terasa instan buat admin, tanpa bikin sheet dibaca ulang terus
 * menerus untuk tiap pemain.
 * ------------------------------------------------------------------
 */

var WorldService = (function () {
  var CACHE_KEY = 'worldservice_cities_v3';
  var CACHE_TTL_SECONDS = 300;
  // PERFORMANCE (strategyinstant.md - client-side reference-data caching):
  // Cities jarang berubah tapi sebelumnya dikirim PENUH di SETIAP
  // api_getGameState(). Sekarang server cuma kirim versi (angka kecil),
  // array kota lengkap di-cache di localStorage BROWSER dan cuma
  // diambil ulang lewat api_getCities() kalau versinya beda - lihat
  // resolveCitiesThenApply_() di JavaScript.html.
  var VERSION_CACHE_KEY = 'worldservice_cities_version_v1';
  var VERSION_CACHE_TTL_SECONDS = 21600; // 6 jam - maksimum TTL CacheService

  // Flavor singkat per Type kota, terinspirasi cara Tradewinds 2 memberi
  // kepribadian ke tiap pelabuhan (TradeHub/Agricultural/Remote dst) -
  // ditampilkan di scene utama (lihat JavaScript.html renderScene()).
  var CITY_TYPE_FLAVOR = {
    TradeHub: 'Pelabuhan sibuk tempat semua rute berpotongan - harga stabil, pilihan barang lengkap.',
    Agricultural: 'Lumbung wilayah ini - hasil bumi murah, barang mewah harus didatangkan dari luar.',
    Remote: 'Jauh dari jalur ramai - harga lebih mahal, tapi lebih sedikit persaingan pedagang.',
    Capital: 'Kota besar yang penuh sukacita - pasar paling lengkap, harga adil dan stabil untuk semua.',
    Outlaw: 'Sarang penyamun - kapal dagang menuju sini nyaris pasti dicegat bajak laut di tengah jalan. Senjata di sini selalu lebih murah dari kota manapun.',
    FallenCapital: 'Ibu kota lama yang sudah tumbang - reruntuhan megah dengan banyak yang perlu dibenahi. Papan misi paling ramai di sini, meski bayarannya seadanya.'
  };

  function getCities() {
    var cache = CacheService.getScriptCache();
    var cached = cache.get(CACHE_KEY);
    if (cached) {
      try {
        return JSON.parse(cached);
      } catch (e) {
        // Cache korup/format lama - abaikan, baca ulang dari sheet di bawah.
      }
    }

    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Cities');
    var data = sheet.getDataRange().getValues();
    var headers = data[0];
    var cities = [];

    for (var i = 1; i < data.length; i++) {
      var city = {};
      headers.forEach(function (h, idx) { city[h] = data[i][idx]; });
      // ImageUrl kolom baru (lihat migrateFase1Improvements di SetupSheets.gs) -
      // dikonversi ke direct URL khusus gambar (format /thumbnail Google Drive,
      // lebih reliable dari uc?export=view untuk hotlink foto) supaya client
      // bisa langsung pakai sebagai background foto port.
      city.ImageUrl = city.ImageUrl ? driveUrlToDirectImage_(city.ImageUrl) : '';
      city.TypeFlavor = CITY_TYPE_FLAVOR[city.Type] || '';
      cities.push(city);
    }

    cache.put(CACHE_KEY, JSON.stringify(cities), CACHE_TTL_SECONDS);
    return cities;
  }

  /**
   * Versi ringan (bukan array penuh) buat dikirim di SETIAP api_getGameState() -
   * client cuma refetch api_getCities() kalau angka ini beda dari yang
   * tersimpan di localStorage-nya. Auto-generate sekali kalau belum ada,
   * naik tiap kali invalidateCache() dipanggil (admin edit Cities, atau
   * migrateAddCitiesRound2 dkk).
   */
  function getCitiesVersion() {
    var cache = CacheService.getScriptCache();
    var v = cache.get(VERSION_CACHE_KEY);
    if (!v) {
      v = String(Date.now());
      cache.put(VERSION_CACHE_KEY, v, VERSION_CACHE_TTL_SECONDS);
    }
    return v;
  }

  /** Paksa cache Cities di-refresh saat pemanggilan berikutnya, DAN naikkan versi. */
  function invalidateCache() {
    var cache = CacheService.getScriptCache();
    cache.remove(CACHE_KEY);
    cache.put(VERSION_CACHE_KEY, String(Date.now()), VERSION_CACHE_TTL_SECONDS);
  }

  return {
    getCities: getCities,
    getCitiesVersion: getCitiesVersion,
    invalidateCache: invalidateCache
  };
})();
