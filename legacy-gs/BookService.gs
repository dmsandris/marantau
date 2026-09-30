/**
 * BookService.gs — Fase 2 (Books & Knowledge)
 * ------------------------------------------------------------------
 * Katalog buku (BookCatalog) sepenuhnya data-driven lewat sheet - admin
 * bisa tambah/edit buku langsung di Google Sheets tanpa ubah kode sama
 * sekali (lihat seedBookCatalog() di SetupSheets.gs untuk contoh format).
 *
 * Model progresi: setiap buku hanya bisa dibeli SEKALI per pemain
 * (permanen, tidak stackable). Begitu dibeli, StatEffects-nya langsung
 * ditambahkan permanen ke CharacterStats pemain - ini yang bikin stat
 * pemain bisa naik jauh di luar archetype awal (roadmap Fase 2).
 *
 * SpecialEffect adalah keyword bebas (string) yang dicek service lain
 * lewat hasSpecialEffect() - lihat pemakaiannya di MarketService.gs
 * (black_market_discount) dan ShipService.gs (cargo_bonus_10).
 *
 * PERFORMANCE: getBookCatalog() jarang berubah (cuma kalau admin edit
 * sheet) tapi dipanggil SANGAT sering (setiap getShip() lewat
 * hasSpecialEffect, plus tiap buka Library) - jadi di-cache lintas
 * request pakai CacheService (sama pola dengan WorldService.getCities),
 * bukan cuma SheetCache per-request. TTL 5 menit, auto-invalidate begitu
 * admin edit sheet BookCatalog (lihat onEdit di Code.gs).
 * ------------------------------------------------------------------
 */

var BookService = (function () {
  var CATALOG_CACHE_KEY = 'bookservice_catalog_v1';
  var CATALOG_CACHE_TTL_SECONDS = 300;

  function getBookCatalog() {
    var cache = CacheService.getScriptCache();
    var cached = cache.get(CATALOG_CACHE_KEY);
    if (cached) {
      try { return JSON.parse(cached); } catch (e) { /* cache korup, baca ulang di bawah */ }
    }

    var sheet = SheetCache.getSheet('BookCatalog');
    var data = SheetCache.getData('BookCatalog');
    var headers = data[0];
    var books = [];

    for (var i = 1; i < data.length; i++) {
      var book = {};
      headers.forEach(function (h, idx) { book[h] = data[i][idx]; });
      books.push(book);
    }

    cache.put(CATALOG_CACHE_KEY, JSON.stringify(books), CATALOG_CACHE_TTL_SECONDS);
    return books;
  }

  /** Paksa cache katalog buku di-refresh saat pemanggilan berikutnya. */
  function invalidateCatalogCache() {
    CacheService.getScriptCache().remove(CATALOG_CACHE_KEY);
  }

  function getBookById(bookId) {
    var catalog = getBookCatalog();
    for (var i = 0; i < catalog.length; i++) {
      if (catalog[i].BookId === bookId) return catalog[i];
    }
    return null;
  }

  function getPlayerBookIds(playerId) {
    var data = SheetCache.getData('PlayerBooks');
    var ids = [];

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) ids.push(data[i][1]);
    }
    return ids;
  }

  /**
   * State lengkap untuk panel Library: buku yang sudah dimiliki (di kota
   * manapun bisa dilihat), dan buku baru yang dijual DI KOTA INI saja
   * (Source === cityId) ditambah buku 'any' (pedagang buku keliling,
   * dijual di semua kota).
   */
  function getLibraryState(playerId, cityId) {
    var catalog = getBookCatalog();
    var ownedIds = getPlayerBookIds(playerId);
    var ownedSet = {};
    ownedIds.forEach(function (id) { ownedSet[id] = true; });

    var owned = [];
    var available = [];

    catalog.forEach(function (book) {
      if (ownedSet[book.BookId]) {
        owned.push(book);
      } else if (book.Source === 'any' || book.Source === cityId) {
        available.push(book);
      }
    });

    return { owned: owned, available: available };
  }

  function parseStatEffects_(raw) {
    if (!raw) return {};
    try {
      var parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (e) {
      return {};
    }
  }

  /** Tambahkan StatEffects (delta) secara permanen ke CharacterStats pemain. */
  function applyStatEffects_(playerId, effects) {
    var sheet = SheetCache.getSheet('CharacterStats');
    var data = SheetCache.getData('CharacterStats');
    var headers = data[0];

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        Object.keys(effects).forEach(function (statKey) {
          var col = headers.indexOf(statKey);
          if (col >= 0) {
            var newVal = Number(data[i][col]) + Number(effects[statKey]);
            sheet.getRange(i + 1, col + 1).setValue(newVal);
          }
        });
        SheetCache.invalidate('CharacterStats');
        return;
      }
    }
    throw new Error('CharacterStats untuk pemain ini tidak ditemukan.');
  }

  function buyBook(bookId) {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);

    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var book = getBookById(bookId);
      if (!book) throw new Error('Buku tidak dikenali: ' + bookId);

      var cityId = LocationService.getCurrentCityId(playerId);
      if (book.Source !== 'any' && book.Source !== cityId) {
        throw new Error('Buku ini tidak dijual di kota ini.');
      }
      if (LocationService.getVoyageState(playerId).inTransit) {
        throw new Error('Kamu sedang berlayar - tidak bisa mengunjungi Library sampai kapal merapat.');
      }

      var ownedIds = getPlayerBookIds(playerId);
      if (ownedIds.indexOf(bookId) !== -1) {
        throw new Error('Kamu sudah punya buku ini.');
      }

      var player = PlayerService.getOrCreatePlayer();
      var price = Number(book.Price) || 0;
      if (player.gold < price) {
        throw new Error('Gold tidak cukup. Butuh ' + price + ', kamu punya ' + player.gold + '.');
      }

      var effects = parseStatEffects_(book.StatEffects);
      applyStatEffects_(playerId, effects);

      var booksSheet = SheetCache.getSheet('PlayerBooks');
      booksSheet.appendRow([playerId, bookId, TimeService.getCurrentGameDay()]);
      SheetCache.invalidate('PlayerBooks');

      PlayerService.updatePlayerRow(playerId, { Gold: player.gold - price });

      LogService.addLog(playerId, 'Purchased "' + book.Name + '" for ' + price + ' gold.');

      return { newGold: player.gold - price, book: book };
    } finally {
      lock.releaseLock();
    }
  }

  /** Daftar keyword SpecialEffect dari semua buku yang dimiliki pemain. */
  function getActiveSpecialEffects(playerId) {
    var ownedIds = getPlayerBookIds(playerId);
    if (!ownedIds.length) return [];

    var catalog = getBookCatalog();
    var effects = [];
    ownedIds.forEach(function (id) {
      var matches = catalog.filter(function (b) { return b.BookId === id; });
      var book = matches.length ? matches[0] : null;
      if (book && book.SpecialEffect) effects.push(book.SpecialEffect);
    });
    return effects;
  }

  function hasSpecialEffect(playerId, keyword) {
    return getActiveSpecialEffects(playerId).indexOf(keyword) !== -1;
  }

  return {
    getBookCatalog: getBookCatalog,
    invalidateCatalogCache: invalidateCatalogCache,
    getBookById: getBookById,
    getLibraryState: getLibraryState,
    buyBook: buyBook,
    getActiveSpecialEffects: getActiveSpecialEffects,
    hasSpecialEffect: hasSpecialEffect
  };
})();
