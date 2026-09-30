/**
 * TreasureService.gs — Fase 5 (Exploration & Treasure)
 * ------------------------------------------------------------------
 * Dua tanggung jawab:
 *   1. Decode clue treasure map (Hidden Knowledge Pairing) - buku
 *      dengan SpecialEffect yang cocok (lihat TreasureData.gs) membuka
 *      clueFull, tanpa buku cuma clueHint yang samar.
 *   2. Aksi Dig/Retrieve (api_digTreasure) - consumable, mirip pola
 *      Governor's Missive (MissionService.gs): perlu merapat di kota
 *      yang tepat, roll hasil risk/reward, treasure map SELALU habis
 *      terpakai (baik berhasil maupun jebakan).
 *
 * 4 kemungkinan hasil (rollDigOutcome_):
 *   - big_gold    : hasil besar, makin mungkin kalau clue sudah di-decode.
 *   - small_gold  : hasil kecil/sedang, hasil paling umum.
 *   - rare_item   : gold sedang + artifact acak (kalau ada yang belum dimiliki).
 *   - false_map   : jebakan kecil - tidak ada gold, kapal kena sedikit
 *                   kerusakan Condition (memakai ShipUpgradeService yang
 *                   sudah ada dari Fase 3c, bukan mekanik baru).
 * Decoded (punya buku yang cocok) menggeser peluang menjauh dari
 * false_map dan lebih ke big_gold/rare_item - insentif nyata untuk
 * Hidden Knowledge Pairing, bukan cuma flavor text.
 * ------------------------------------------------------------------
 */

var TreasureService = (function () {

  function isDecoded_(playerId, site) {
    return BookService.hasSpecialEffect(playerId, site.requiresBookKeyword);
  }

  /** View satu treasure map (dipakai getPlayerTreasureMapsView + api_getTreasureMapDetail). */
  function describeMapItem_(playerId, item, qty) {
    var effects = ItemService.parseEffects_(item.Effects);
    var site = getTreasureSiteById(effects.siteId);
    if (!site) {
      return {
        itemId: item.ItemId, name: item.Name, qty: qty,
        siteId: null, siteName: 'Lokasi tidak dikenali', cityId: null, cityName: '',
        difficulty: 0, decoded: false, clue: 'Peta ini rusak - lokasinya tidak bisa dibaca.'
      };
    }

    var decoded = isDecoded_(playerId, site);
    var city = LocationService.getCityById(site.cityId);

    return {
      itemId: item.ItemId,
      name: item.Name,
      qty: qty,
      siteId: site.id,
      siteName: site.name,
      cityId: site.cityId,
      cityName: city ? city.Name : site.cityId,
      difficulty: site.difficulty,
      decoded: decoded,
      clue: decoded ? site.clueFull : site.clueHint
    };
  }

  /** View untuk panel Items: semua treasure map yang dimiliki pemain + status decode. */
  function getPlayerTreasureMapsView(playerId) {
    return ItemService.getRawPlayerItems_(playerId)
      .filter(function (row) { return row.item.Type === 'treasure_map'; })
      .map(function (row) { return describeMapItem_(playerId, row.item, row.qty); });
  }

  function getTreasureMapDetail(itemId) {
    var playerId = PlayerService.getCurrentPlayerId();
    var item = ItemService.getItemById(itemId);
    if (!item || item.Type !== 'treasure_map') throw new Error('Item ini bukan treasure map.');
    if (ItemService.getItemQty(playerId, itemId) < 1) throw new Error('Kamu tidak punya peta ini.');
    return describeMapItem_(playerId, item, ItemService.getItemQty(playerId, itemId));
  }

  /** Ambil satu ItemId treasure_map acak dari katalog - dipakai CombatService untuk loot drop. */
  function pickRandomMapItemId_() {
    var maps = ItemService.getItemCatalog().filter(function (it) { return it.Type === 'treasure_map'; });
    if (!maps.length) return null;
    return maps[Math.floor(Math.random() * maps.length)].ItemId;
  }

  function clamp_(n, min, max) { return Math.min(max, Math.max(min, n)); }

  /**
   * Roll hasil dig - pure calculation, tidak menyentuh sheet. Weighted
   * berdasar difficulty situs & status decoded.
   */
  function rollDigOutcome_(site, decoded) {
    var baseGold = getGameConfigNumber_('TreasureDigBaseGold', 350);
    var difficultyMult = site.difficulty;

    // Bobot dasar (persen, total 100): [big_gold, rare_item, small_gold, false_map]
    var weights = decoded ? [30, 20, 40, 10] : [12, 8, 45, 35];
    var roll = Math.random() * 100;
    var outcome;
    if (roll < weights[0]) {
      outcome = 'big_gold';
    } else if (roll < weights[0] + weights[1]) {
      outcome = 'rare_item';
    } else if (roll < weights[0] + weights[1] + weights[2]) {
      outcome = 'small_gold';
    } else {
      outcome = 'false_map';
    }

    if (outcome === 'big_gold') {
      var big = Math.round(baseGold * difficultyMult * (1.6 + Math.random() * 1.2));
      return { outcome: outcome, goldDelta: big };
    }
    if (outcome === 'rare_item') {
      var midGold = Math.round(baseGold * difficultyMult * (0.6 + Math.random() * 0.4));
      return { outcome: outcome, goldDelta: midGold, grantArtifact: true };
    }
    if (outcome === 'small_gold') {
      var small = Math.round(baseGold * difficultyMult * (0.3 + Math.random() * 0.5));
      return { outcome: outcome, goldDelta: small };
    }
    // false_map
    var damage = -Math.round((8 + Math.random() * 10) * clamp_(difficultyMult, 1, 3));
    return { outcome: outcome, goldDelta: 0, conditionDelta: damage };
  }

  function digTreasure(itemId) {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var item = ItemService.getItemById(itemId);
      if (!item || item.Type !== 'treasure_map') throw new Error('Item ini bukan treasure map.');
      if (ItemService.getItemQty(playerId, itemId) < 1) throw new Error('Kamu tidak punya peta ini.');

      var effects = ItemService.parseEffects_(item.Effects);
      var site = getTreasureSiteById(effects.siteId);
      if (!site) throw new Error('Lokasi di peta ini tidak dikenali - peta rusak.');

      if (LocationService.getVoyageState(playerId).inTransit) {
        throw new Error('Kamu sedang berlayar - merapat dulu sebelum menggali.');
      }
      if (LocationService.getCurrentCityId(playerId) !== site.cityId) {
        var city = LocationService.getCityById(site.cityId);
        throw new Error('Peta ini menunjuk ke lokasi dekat ' + (city ? city.Name : site.cityId) + ' - berlayar ke sana dulu.');
      }

      var decoded = isDecoded_(playerId, site);
      var r = rollDigOutcome_(site, decoded);

      // Peta HABIS terpakai apapun hasilnya.
      ItemService.consumeItem(playerId, itemId, 1);

      var player = PlayerService.getOrCreatePlayer();
      var newGold = player.gold;
      if (r.goldDelta) {
        newGold = Math.max(0, player.gold + r.goldDelta);
        PlayerService.updatePlayerRow(playerId, { Gold: newGold });
      }

      var grantedItem = null;
      if (r.grantArtifact) {
        var artifacts = ItemService.getItemCatalog().filter(function (it) { return it.Type === 'artifact'; });
        if (artifacts.length) {
          var pick = artifacts[Math.floor(Math.random() * artifacts.length)];
          ItemService.grantItem(playerId, pick.ItemId, 1);
          grantedItem = { itemId: pick.ItemId, name: pick.Name };
        }
      }

      var newCondition = null;
      if (r.conditionDelta) {
        newCondition = ShipUpgradeService.applyConditionDelta(playerId, r.conditionDelta);
      }

      var message = buildDigMessage_(site, r, grantedItem);
      LogService.addLog(playerId, message);

      return {
        outcome: r.outcome,
        message: message,
        goldDelta: r.goldDelta || 0,
        newGold: newGold,
        grantedItem: grantedItem,
        conditionDelta: r.conditionDelta || 0,
        newCondition: newCondition !== null ? newCondition : ShipService.getShip(playerId).Condition
      };
    } finally {
      lock.releaseLock();
    }
  }

  function buildDigMessage_(site, r, grantedItem) {
    if (r.outcome === 'big_gold') {
      return 'Galian di ' + site.name + ' membuahkan hasil besar - ' + r.goldDelta + ' gold ditemukan terkubur.';
    }
    if (r.outcome === 'rare_item') {
      return grantedItem
        ? 'Galian di ' + site.name + ' menemukan ' + r.goldDelta + ' gold DAN sebuah artifact: "' + grantedItem.name + '"!'
        : 'Galian di ' + site.name + ' menemukan ' + r.goldDelta + ' gold.';
    }
    if (r.outcome === 'small_gold') {
      return 'Galian di ' + site.name + ' menemukan sisa harta sederhana - ' + r.goldDelta + ' gold.';
    }
    return 'Peta ternyata jebakan - galian di ' + site.name + ' memicu perangkap tua, kapal sedikit rusak (' +
      r.conditionDelta + ' Condition), tidak ada harta ditemukan.';
  }

  return {
    getPlayerTreasureMapsView: getPlayerTreasureMapsView,
    getTreasureMapDetail: getTreasureMapDetail,
    pickRandomMapItemId_: pickRandomMapItemId_,
    digTreasure: digTreasure
  };
})();
