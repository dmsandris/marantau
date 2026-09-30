/**
 * MarketService.gs
 * ------------------------------------------------------------------
 * Formula harga mengikuti GDD §8.1:
 *   EffectiveBuyPrice  = CurrentPrice x (1 - (TradingBonus% + BookDiscount%))
 *   EffectiveSellPrice = CurrentPrice x (1 + NegotiationBonus%)
 * dengan diminishing-returns curve dari GDD §2.5 (stat/10 = bonus%).
 * BookDiscount% berasal dari buku dengan SpecialEffect 'black_market_discount'
 * (Fase 2, lihat BookService.gs) - hanya memotong harga beli.
 *
 * Shared world: harga di sheet Market SAMA untuk semua pemain -
 * transaksi wajib pakai LockService (GDD §16.2 Risiko 1).
 * ------------------------------------------------------------------
 */

var MarketService = (function () {

  // Bonus tambahan dari buku "Smuggler's Codebook" (SpecialEffect
  // 'black_market_discount', lihat BookService.gs) - hanya memotong
  // harga BELI, tidak memengaruhi harga jual.
  var BLACK_MARKET_EXTRA_DISCOUNT_PERCENT = 5;

  // TooGood = "kota penyamun" - senjata (Arms) SELALU lebih murah di sini,
  // bukan cuma soal base price awal (yang bisa saja di-tweak admin nanti
  // lewat sheet Market) tapi diskon STRUKTURAL permanen di atas diskon
  // Trading/buku manapun. Lihat migrateAddCitiesRound2() di SetupSheets.gs.
  var TOOGOOD_ARMS_DISCOUNT_PERCENT = 20;

  function statToBonusPercent(stat) {
    // Trading/Negotiation 20 -> 2%, 40 -> 4%, ... 100 -> 10% (lihat GDD §2.5)
    return Math.min(stat, 100) / 10;
  }

  function getBuyDiscountPercent_(playerId, tradingBonus) {
    // Fase 5: artifact terpasang bisa memberi keyword 'black_market_discount'
    // yang sama dengan buku "Smuggler's Codebook" - jalur alternatif, sama efeknya.
    var hasDiscount = BookService.hasSpecialEffect(playerId, 'black_market_discount') ||
      ItemService.hasEquippedEffect(playerId, 'black_market_discount');
    var extra = hasDiscount ? BLACK_MARKET_EXTRA_DISCOUNT_PERCENT : 0;
    return tradingBonus + extra;
  }

  /**
   * Fase 4: Reputation sekarang benar-benar memengaruhi harga, bukan
   * cuma akses misi - pedagang kota memberi sedikit diskon/harga lebih
   * baik ke kapten yang sudah dikenal baik (Standing tinggi di kota
   * itu). Dipotong (cap) supaya efeknya tetap kecil-halus, bukan
   * menggantikan pentingnya stat Trading/Negotiation.
   */
  function getReputationBonusPercent_(cityId) {
    var player = PlayerService.getOrCreatePlayer();
    var reputation = MissionService.getReputationForCity(player, cityId);
    var perPoint = getGameConfigNumber_('ReputationMarketBonusPerPoint', 0.05);
    var cap = getGameConfigNumber_('ReputationMarketBonusCap', 10);
    return Math.min(reputation * perPoint, cap);
  }

  function findMarketRowIndex(sheetData, cityId, commodityId) {
    for (var i = 1; i < sheetData.length; i++) {
      if (sheetData[i][0] === cityId && sheetData[i][1] === commodityId) return i;
    }
    return -1;
  }

  /** TooGood: diskon struktural khusus komoditas Arms, lihat konstanta di atas. */
  function getArmsExtraDiscount_(cityId, commodityId) {
    return (cityId === 'toogood' && commodityId === 'arms') ? TOOGOOD_ARMS_DISCOUNT_PERCENT : 0;
  }

  /**
   * Harga beli & jual FINAL untuk satu komoditas di satu kota - SATU
   * sumber kebenaran dipakai getMarketForCity() (display) DAN
   * buy()/sell() (transaksi sungguhan), supaya tidak pernah drift.
   *
   * PENTING - anti-exploit: buyDiscount (dari Trading/buku/reputation)
   * dan negotiationBonus (dari Negotiation/reputation) dulu dihitung
   * independen di sekitar CurrentPrice yang SAMA. Kombinasi trading
   * rendah + negotiation/reputation tinggi bisa membuat sellPrice >
   * buyPrice DI KOTA YANG SAMA - beli lalu langsung jual balik untung
   * instan tanpa risiko. Sekarang sellPrice di-clamp supaya TIDAK
   * PERNAH melebihi buyPrice di kota yang sama (impas paling untung,
   * bukan profit instan). Perbedaan harga ANTAR KOTA (termasuk yang
   * ekstrem karena kelangkaan) TETAP dibiarkan apa adanya - itu
   * memang sumber profit yang sah dari sistem trading ini.
   */
  function computePrices_(cityId, commodityId, currentPrice, buyDiscountPercent, negotiationBonusPercent) {
    var buyPrice = Math.round(currentPrice * (1 - buyDiscountPercent / 100));
    var sellPrice = Math.round(currentPrice * (1 + negotiationBonusPercent / 100));
    sellPrice = Math.min(sellPrice, buyPrice);
    return { buyPrice: buyPrice, sellPrice: sellPrice };
  }

  /* ================= OVERSTOCK (Tide v8) =================
   * Tiap penjualan pemain ke pasar menambah "stok menumpuk" (glut) untuk
   * pasangan kota+komoditas itu - dibagi SEMUA pemain (shared world).
   * Makin menumpuk, HARGA JUAL turun; HARGA BELI TIDAK berubah sama
   * sekali (tidak bisa dimanipulasi pemain). Stok pulih sendiri seiring
   * waktu (peluruhan eksponensial), dan pembelian ke pasar ikut menyerap
   * sebagian stok yang menumpuk.
   *   hargaJual = hargaJualNormal / (1 + glut / OverstockScale)
   *   (dibatasi minimal OverstockFloorPercent % dari harga normal)
   * Konfigurasi opsional di GameConfig: OverstockScale (default 120 unit),
   * OverstockHalfLifeMinutes (default 120), OverstockFloorPercent (default 35).
   */
  var GLUT_KEY = 'mkt_glut_v1';
  var glutMemo_ = null;
  function glutCfg_() {
    return {
      scale: Math.max(10, getGameConfigNumber_('OverstockScale', 120)),
      halfLifeMs: Math.max(5, getGameConfigNumber_('OverstockHalfLifeMinutes', 120)) * 60000,
      floor: Math.min(95, Math.max(5, getGameConfigNumber_('OverstockFloorPercent', 35))) / 100
    };
  }
  function glutMap_() {
    if (glutMemo_) return glutMemo_;
    var raw = null;
    try { raw = PropertiesService.getScriptProperties().getProperty(GLUT_KEY); } catch (e) {}
    try { glutMemo_ = raw ? JSON.parse(raw) : {}; } catch (e) { glutMemo_ = {}; }
    return glutMemo_;
  }
  /** Glut saat ini (sudah diluruhkan ke waktu sekarang). */
  function glutNow_(cityId, commodityId) {
    var e = glutMap_()[cityId + '|' + commodityId];
    if (!e) return 0;
    var cfg = glutCfg_(), dt = Math.max(0, Date.now() - Number(e[1] || 0));
    var g = Number(e[0] || 0) * Math.pow(0.5, dt / cfg.halfLifeMs);
    return g < 0.05 ? 0 : g;
  }
  function setGlut_(cityId, commodityId, g) {
    var map = glutMap_(), key = cityId + '|' + commodityId, now = Date.now(), cfg = glutCfg_();
    if (g < 0.05) delete map[key]; else map[key] = [Math.round(g * 100) / 100, now];
    // buang entri yang sudah pulih supaya properti tetap kecil
    Object.keys(map).forEach(function (k) {
      var e = map[k]; if (Number(e[0]) * Math.pow(0.5, (now - Number(e[1])) / cfg.halfLifeMs) < 0.05) delete map[k];
    });
    PropertiesService.getScriptProperties().setProperty(GLUT_KEY, JSON.stringify(map));
  }
  /** Harga jual satu unit ketika stok menumpuk sebanyak g. */
  function sellUnitAt_(normalSell, g, cfg) {
    return Math.max(Math.round(normalSell * cfg.floor), Math.round(normalSell / (1 + g / cfg.scale)));
  }
  /** Total pendapatan menjual qty unit mulai dari glut g (harga turun per unit yang dijual). */
  function sellRevenue_(normalSell, g, qty, cfg) {
    var sum = 0;
    for (var i = 0; i < qty; i++) sum += sellUnitAt_(normalSell, g + i, cfg);
    return sum;
  }

  /** Harga beli per unit untuk pemain ini di kota ini (dipakai misi Pesanan). 0 = tidak dijual. */
  function quoteBuy(playerId, cityId, commodityId) {
    var marketData = SheetCache.getData('Market');
    var rowIndex = findMarketRowIndex(marketData, cityId, commodityId);
    if (rowIndex === -1) return 0;
    var currentPrice = Math.round(marketData[rowIndex][3] * (1 + WorldEventService.getPriceMultiplierPercent(cityId) / 100));
    var stats = CharacterService.getCharacterStats(playerId);
    var tradingBonus = stats ? statToBonusPercent(stats.Trading) : 0;
    var buyDiscount = getBuyDiscountPercent_(playerId, tradingBonus) + getReputationBonusPercent_(cityId) + getArmsExtraDiscount_(cityId, commodityId);
    return computePrices_(cityId, commodityId, currentPrice, buyDiscount, 0).buyPrice;
  }

  function getMarketForCity(cityId) {
    glutMemo_ = null;
    var playerId = PlayerService.getCurrentPlayerId();
    var stats = CharacterService.getCharacterStats(playerId);
    var tradingBonus = stats ? statToBonusPercent(stats.Trading) : 0;
    var negotiationBonus = stats ? statToBonusPercent(stats.Negotiation) : 0;
    var reputationBonus = getReputationBonusPercent_(cityId);
    var buyDiscount = getBuyDiscountPercent_(playerId, tradingBonus) + reputationBonus;
    negotiationBonus += reputationBonus;

    // Fase 6: World Event ekonomi ('storm_surge'/'harvest_bounty') geser
    // CurrentPrice sheet naik/turun sementara SEBELUM diskon/bonus
    // pemain dihitung - jadi badge "Harga Bagus"/"Mahal" (dibanding
    // BasePrice) otomatis ikut mencerminkan kondisi kota saat ini.
    var eventPricePercent = WorldEventService.getPriceMultiplierPercent(cityId);

    var cargoOwned = {};
    CargoService.getCargo(playerId).forEach(function (c) { cargoOwned[c.commodityId] = c.qty; });
    var ship = ShipService.getShip(playerId);
    var cargoSpaceRemaining = Math.max(0, ship.EffectiveCargo - CargoService.getTotalCargoQty(playerId));

    var data = SheetCache.getData('Market');
    var listings = [];
    var glutCfg = glutCfg_();

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === cityId) {
        var commodityId = data[i][1];
        var basePrice = data[i][2];
        var currentPrice = Math.round(data[i][3] * (1 + eventPricePercent / 100));
        var commodity = getCommodityById(commodityId);
        var itemBuyDiscount = buyDiscount + getArmsExtraDiscount_(cityId, commodityId);
        var prices = computePrices_(cityId, commodityId, currentPrice, itemBuyDiscount, negotiationBonus);
        var glut = glutNow_(cityId, commodityId);
        var sellNormal = prices.sellPrice;
        prices.sellPrice = sellUnitAt_(sellNormal, glut, glutCfg);

        listings.push({
          commodityId: commodityId,
          name: commodity ? commodity.name : commodityId,
          flavor: commodity ? commodity.flavor : '',
          currentPrice: currentPrice,
          buyPrice: prices.buyPrice,
          sellPrice: prices.sellPrice,
          // Tide v8 - overstock: client memakai ini untuk menghitung total jual
          // (harga turun per unit) & badge "Stok menumpuk".
          sellNormal: sellNormal,
          glut: Math.round(glut * 100) / 100,
          glutScale: glutCfg.scale,
          glutFloor: glutCfg.floor,
          overstockPct: sellNormal > 0 ? Math.max(0, Math.round((1 - prices.sellPrice / sellNormal) * 100)) : 0,
          // Dipakai client buat tombol "Max Beli"/"Max Jual" (lihat JavaScript.html).
          ownedQty: cargoOwned[commodityId] || 0,
          // Dipakai client buat badge "Harga Bagus"/"Mahal" - dibandingkan
          // ke BasePrice kota ini (bukan riwayat, jadi selalu tersedia
          // tanpa perlu tracking tambahan). Terinspirasi cara Tradewinds 2
          // memberi sinyal "buy low sell high" ke pemain.
          basePrice: basePrice,
          priceRatio: basePrice > 0 ? Math.round((currentPrice / basePrice) * 100) : 100
        });
      }
    }
    return { items: listings, cargoSpaceRemaining: cargoSpaceRemaining };
  }

  function buy(cityId, commodityId, qty) {
    qty = Math.floor(Number(qty));
    if (!qty || qty <= 0) throw new Error('Jumlah beli tidak valid.');

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);

    try {
      glutMemo_ = null; // baca ulang stok menumpuk SETELAH lock (bisa diubah pemain lain)
      var playerId = PlayerService.getCurrentPlayerId();

      if (LocationService.getCurrentCityId(playerId) !== cityId) {
        throw new Error('Kamu harus berada di kota ini untuk berdagang.');
      }
      if (LocationService.getVoyageState(playerId).inTransit) {
        throw new Error('Kamu sedang berlayar - tidak bisa berdagang sampai kapal merapat.');
      }

      var marketData = SheetCache.getData('Market');
      var rowIndex = findMarketRowIndex(marketData, cityId, commodityId);
      if (rowIndex === -1) throw new Error('Komoditas tidak tersedia di kota ini.');

      var currentPrice = marketData[rowIndex][3];
      currentPrice = Math.round(currentPrice * (1 + WorldEventService.getPriceMultiplierPercent(cityId) / 100));
      var stats = CharacterService.getCharacterStats(playerId);
      var tradingBonus = stats ? statToBonusPercent(stats.Trading) : 0;
      var negotiationBonus = stats ? statToBonusPercent(stats.Negotiation) : 0;
      var buyDiscount = getBuyDiscountPercent_(playerId, tradingBonus) + getReputationBonusPercent_(cityId) +
        getArmsExtraDiscount_(cityId, commodityId);
      var unitPrice = computePrices_(cityId, commodityId, currentPrice, buyDiscount, negotiationBonus).buyPrice;
      var totalCost = unitPrice * qty;

      var player = PlayerService.getOrCreatePlayer();
      if (player.gold < totalCost) {
        throw new Error('Gold tidak cukup. Butuh ' + totalCost + ', kamu punya ' + player.gold + '.');
      }

      var ship = ShipService.getShip(playerId);
      var currentCargoQty = CargoService.getTotalCargoQty(playerId);
      if (currentCargoQty + qty > ship.EffectiveCargo) {
        throw new Error('Kapasitas cargo tidak cukup. Sisa ruang: ' + (ship.EffectiveCargo - currentCargoQty) + '.');
      }

      PlayerService.updatePlayerRow(playerId, { Gold: player.gold - totalCost });
      CargoService.adjustQty(playerId, commodityId, qty);
      // Pembelian menyerap stok yang menumpuk (harga BELI tetap tidak berubah).
      var g0 = glutNow_(cityId, commodityId);
      if (g0 > 0) setGlut_(cityId, commodityId, Math.max(0, g0 - qty));

      var commodity = getCommodityById(commodityId);
      LogService.addLog(playerId,
        'Bought ' + qty + ' unit' + (qty > 1 ? 's' : '') + ' of ' +
        (commodity ? commodity.name : commodityId) + ' for ' + totalCost + ' gold.');

      return { totalCost: totalCost, unitPrice: unitPrice, newGold: player.gold - totalCost };
    } finally {
      lock.releaseLock();
    }
  }

  function sell(cityId, commodityId, qty) {
    qty = Math.floor(Number(qty));
    if (!qty || qty <= 0) throw new Error('Jumlah jual tidak valid.');

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);

    try {
      glutMemo_ = null; // baca ulang stok menumpuk SETELAH lock (bisa diubah pemain lain)
      var playerId = PlayerService.getCurrentPlayerId();

      if (LocationService.getCurrentCityId(playerId) !== cityId) {
        throw new Error('Kamu harus berada di kota ini untuk berdagang.');
      }
      if (LocationService.getVoyageState(playerId).inTransit) {
        throw new Error('Kamu sedang berlayar - tidak bisa berdagang sampai kapal merapat.');
      }

      var marketData = SheetCache.getData('Market');
      var rowIndex = findMarketRowIndex(marketData, cityId, commodityId);
      if (rowIndex === -1) throw new Error('Komoditas tidak tersedia di kota ini.');

      var currentPrice = marketData[rowIndex][3];
      currentPrice = Math.round(currentPrice * (1 + WorldEventService.getPriceMultiplierPercent(cityId) / 100));
      var stats = CharacterService.getCharacterStats(playerId);
      var tradingBonus = stats ? statToBonusPercent(stats.Trading) : 0;
      var negotiationBonus = (stats ? statToBonusPercent(stats.Negotiation) : 0) + getReputationBonusPercent_(cityId);
      var buyDiscount = getBuyDiscountPercent_(playerId, tradingBonus) + getReputationBonusPercent_(cityId) +
        getArmsExtraDiscount_(cityId, commodityId);
      var sellNormal = computePrices_(cityId, commodityId, currentPrice, buyDiscount, negotiationBonus).sellPrice;
      var cfg = glutCfg_(), g = glutNow_(cityId, commodityId);
      var totalRevenue = sellRevenue_(sellNormal, g, qty, cfg);
      var unitPrice = Math.round(totalRevenue / qty);

      CargoService.adjustQty(playerId, commodityId, -qty); // lempar error kalau cargo tidak cukup
      setGlut_(cityId, commodityId, g + qty);

      var player = PlayerService.getOrCreatePlayer();
      PlayerService.updatePlayerRow(playerId, { Gold: player.gold + totalRevenue });

      var commodity = getCommodityById(commodityId);
      LogService.addLog(playerId,
        'Sold ' + qty + ' unit' + (qty > 1 ? 's' : '') + ' of ' +
        (commodity ? commodity.name : commodityId) + ' for ' + totalRevenue + ' gold.');

      return { totalRevenue: totalRevenue, unitPrice: unitPrice, newGold: player.gold + totalRevenue,
        nextSellPrice: sellUnitAt_(sellNormal, g + qty, cfg), overstockPct: sellNormal > 0 ? Math.max(0, Math.round((1 - sellUnitAt_(sellNormal, g + qty, cfg) / sellNormal) * 100)) : 0 };
    } finally {
      lock.releaseLock();
    }
  }

  return {
    getMarketForCity: getMarketForCity,
    quoteBuy: quoteBuy,
    buy: buy,
    sell: sell
  };
})();
