/**
 * MissionService.gs
 * ------------------------------------------------------------------
 * Fase 4 - Missions & Reputation, dirombak di Tide v8.
 *
 * Papan misi per kota di-generate DETERMINISTIK dari seed
 * cityId + gameDay + offerIndex (seededRandom_ di Utils.gs), jadi semua
 * pemain melihat papan yang sama pada hari-game yang sama.
 *
 * DUA JENIS MISI (Tide v8):
 *   - 'courier'  (Titipan)  : barang titipan LANGSUNG dimuat ke kapal saat
 *                             misi diterima. Tugasmu hanya mengantar ke
 *                             kota tujuan.
 *   - 'procure'  (Pesanan)  : pemberi misi memesan barang yang HANYA boleh
 *                             dibeli di satu pulau tertentu (SourceCityId).
 *                             Beli di sana lewat tombol "Beli Pesanan",
 *                             lalu bawa pulang ke pemberi misi.
 *
 * MUATAN MISI TERKUNCI: barang misi disimpan terpisah dari palka biasa
 * (kolom LoadedQty di PlayerMissions), BUKAN di PlayerInventory. Karena
 * itu barang misi otomatis tidak bisa dijual ke pasar, dipasang di Bursa,
 * dititip ke gudang, maupun hilang dirampas bajak laut. Muatan misi tetap
 * MEMAKAN ruang palka (lihat CargoService.getTotalCargoQty).
 *
 * Reputation (Players.Reputation, JSON per CityId) membuka tier penawaran
 * yang lebih baik - lihat MISSION_OFFER_TIERS.
 * ------------------------------------------------------------------
 */

var MISSION_OFFER_TIERS = [
  { minReputation: 0,  label: 'Muatan Standar',        qtyRange: [3, 8],   rewardPerUnitRange: [15, 25] },
  { minReputation: 5,  label: 'Kontrak Terpercaya',     qtyRange: [6, 12],  rewardPerUnitRange: [25, 38] },
  { minReputation: 15, label: 'Kontrak Elite Gubernur', qtyRange: [10, 18], rewardPerUnitRange: [38, 55] }
];

/** Kolom sheet PlayerMissions (1-based). Kolom 10-12 ditambahkan Tide v8. */
var PM_COL = { PlayerId: 1, MissionId: 2, Status: 3, AcceptedAt: 4, CityId: 5, CommodityId: 6, Qty: 7, DeliverToCityId: 8, Reward: 9, Type: 10, SourceCityId: 11, LoadedQty: 12 };
var PM_HEADERS_V8 = ['PlayerId', 'MissionId', 'Status', 'AcceptedAt', 'CityId', 'CommodityId', 'Qty', 'DeliverToCityId', 'Reward', 'Type', 'SourceCityId', 'LoadedQty'];

var MissionService = (function () {

  var TYPE_LABEL = { courier: 'Titipan', procure: 'Pesanan', legacy: 'Kiriman' };

  function getSheet_() {
    return SheetCache.getSheet('PlayerMissions');
  }

  /** Pastikan header kolom v8 ada (aman diulang, tanpa perlu migrasi manual). */
  function ensureHeaders_() {
    var sh = getSheet_();
    var width = Math.max(sh.getLastColumn(), 1);
    var head = sh.getRange(1, 1, 1, width).getValues()[0];
    if (head.indexOf('Type') !== -1 && head.indexOf('LoadedQty') !== -1) return;
    sh.getRange(1, 1, 1, PM_HEADERS_V8.length).setValues([PM_HEADERS_V8]);
    SheetCache.invalidate('PlayerMissions');
  }

  function getActiveMissionRow_(playerId) {
    var data = SheetCache.getData('PlayerMissions');
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId && data[i][2] === 'active') {
        var r = data[i];
        var type = String(r[PM_COL.Type - 1] || '') || 'legacy';
        return {
          rowIndex: i + 1,
          missionId: r[1],
          status: r[2],
          acceptedAt: r[3],
          cityId: r[4],
          commodityId: r[5],
          qty: Number(r[6]) || 0,
          deliverToCityId: r[7],
          reward: Number(r[8]) || 0,
          type: type,
          sourceCityId: String(r[PM_COL.SourceCityId - 1] || ''),
          loadedQty: Number(r[PM_COL.LoadedQty - 1]) || 0
        };
      }
    }
    return null;
  }

  function cityName_(cityId) {
    var c = cityId ? LocationService.getCityById(cityId) : null;
    return c ? c.Name : (cityId || '');
  }

  function toClientState_(active) {
    if (!active) return { hasActive: false };
    var commodity = getCommodityById(active.commodityId);
    return {
      hasActive: true,
      type: active.type,
      typeLabel: TYPE_LABEL[active.type] || 'Misi',
      commodityId: active.commodityId,
      commodityName: commodity ? commodity.name : active.commodityId,
      qty: active.qty,
      loadedQty: active.type === 'legacy' ? 0 : active.loadedQty,
      originCityId: active.cityId,
      originCityName: cityName_(active.cityId),
      sourceCityId: active.sourceCityId || '',
      sourceCityName: active.sourceCityId ? cityName_(active.sourceCityId) : '',
      deliverToCityId: active.deliverToCityId,
      deliverToCityName: cityName_(active.deliverToCityId),
      reward: active.reward
    };
  }

  function getMissionState(playerId) {
    return toClientState_(getActiveMissionRow_(playerId));
  }

  /** Jumlah unit muatan misi (terkunci) yang sedang memakan ruang palka. */
  function getMissionLoad(playerId) {
    var a = getActiveMissionRow_(playerId);
    return a && a.type !== 'legacy' ? a.loadedQty : 0;
  }

  /** Reputation-lite pemain untuk satu kota (dipakai UI scene & gating papan misi). */
  function getReputationForCity(player, cityId) {
    var reputation = {};
    try { reputation = JSON.parse(player.reputation || '{}'); } catch (e) { reputation = {}; }
    return reputation[cityId] || 0;
  }

  /**
   * IKN = "ibu kota lama yang tumbang": papan paling ramai (5 penawaran),
   * tapi reward dipotong (bayaran seadanya).
   */
  function tiersForCity_(cityId) {
    // Tier dasar muncul DUA kali (satu Titipan + satu Pesanan) supaya kapten
    // baru langsung bisa memilih kedua jenis misi.
    var base = [MISSION_OFFER_TIERS[0]].concat(MISSION_OFFER_TIERS);
    if (cityId !== 'ikn') return base;
    return base.concat([
      { minReputation: 0, label: 'Muatan Standar', qtyRange: [3, 8], rewardPerUnitRange: [15, 25] },
      { minReputation: 0, label: 'Muatan Standar', qtyRange: [3, 8], rewardPerUnitRange: [15, 25] }
    ]);
  }

  /** World Event sosial menggeser reward di atas multiplier dasar kota. */
  function rewardMultiplierForCity_(cityId) {
    var base = cityId === 'ikn' ? 0.6 : 1;
    var eventPercent = WorldEventService.getRewardMultiplierPercent(cityId);
    return base * (1 + eventPercent / 100);
  }

  /** Peta harga dasar pasar: { cityId: { commodityId: basePrice } } (hanya barang yang dijual di kota itu). */
  function marketBaseMap_() {
    var data = SheetCache.getData('Market'), map = {};
    for (var i = 1; i < data.length; i++) {
      var c = data[i][0], k = data[i][1];
      if (!c || !k) continue;
      (map[c] = map[c] || {})[k] = Number(data[i][2]) || 0;
    }
    return map;
  }

  /** Jenis misi untuk tiap slot papan: slot 0 selalu Titipan, slot 1 selalu Pesanan, sisanya acak. */
  function typeForSlot_(idx, rng) {
    if (idx === 0) return 'courier';
    if (idx === 1) return 'procure';
    return rng() < 0.5 ? 'courier' : 'procure';
  }

  function getMissionBoard(cityId) {
    var player = PlayerService.getOrCreatePlayer();
    var reputation = getReputationForCity(player, cityId);
    var gameDay = TimeService.getCurrentGameDay();

    var otherCities = WorldService.getCities().filter(function (c) { return c.CityId !== cityId; });
    var commodities = getAllCommodities();
    var tiers = tiersForCity_(cityId);
    var rewardMultiplier = rewardMultiplierForCity_(cityId);
    var bases = marketBaseMap_();

    var offers = tiers.map(function (tier, idx) {
      var rng = seededRandom_(cityId + '|' + gameDay + '|' + idx + '|v8');
      var type = typeForSlot_(idx, rng);
      var qty = tier.qtyRange[0] + Math.floor(rng() * (tier.qtyRange[1] - tier.qtyRange[0] + 1));
      var rewardPerUnit = tier.rewardPerUnitRange[0] + Math.floor(rng() * (tier.rewardPerUnitRange[1] - tier.rewardPerUnitRange[0] + 1));
      var commodity = commodities[Math.floor(rng() * commodities.length)];
      var offer = {
        offerIndex: idx,
        type: type,
        typeLabel: TYPE_LABEL[type],
        label: tier.label,
        minReputation: tier.minReputation,
        unlocked: reputation >= tier.minReputation,
        qty: qty
      };

      if (type === 'procure') {
        // Pulau sumber: kota LAIN yang benar-benar menjual barang ini.
        var sources = otherCities.filter(function (c) { return bases[c.CityId] && bases[c.CityId][commodity.id]; });
        if (!sources.length) {
          commodity = commodities.filter(function (k) { return otherCities.some(function (c) { return bases[c.CityId] && bases[c.CityId][k.id]; }); })[0] || commodity;
          sources = otherCities.filter(function (c) { return bases[c.CityId] && bases[c.CityId][commodity.id]; });
        }
        var src = sources.length ? sources[Math.floor(rng() * sources.length)] : null;
        var basePrice = src ? bases[src.CityId][commodity.id] : 100;
        offer.commodityId = commodity.id;
        offer.commodityName = commodity.name;
        offer.sourceCityId = src ? src.CityId : null;
        offer.sourceCityName = src ? src.Name : '???';
        offer.deliverToCityId = cityId;                         // antar kembali ke pemberi misi
        offer.deliverToCityName = cityName_(cityId);
        // Imbalan = ganti modal (harga dasar di pulau sumber + 10%) + upah jerih payah.
        offer.reward = Math.max(1, Math.round(qty * (basePrice * 1.1 + rewardPerUnit * 1.4 * rewardMultiplier)));
        offer.estCost = Math.round(qty * basePrice);
      } else {
        var deliverTo = otherCities.length ? otherCities[Math.floor(rng() * otherCities.length)] : null;
        offer.commodityId = commodity.id;
        offer.commodityName = commodity.name;
        offer.sourceCityId = null;
        offer.deliverToCityId = deliverTo ? deliverTo.CityId : null;
        offer.deliverToCityName = deliverTo ? deliverTo.Name : '???';
        // Upah antar: tarif tier + sedikit dari nilai barang yang dipercayakan.
        var anyBase = 0;
        Object.keys(bases).forEach(function (c) { if (bases[c][commodity.id]) anyBase = Math.max(anyBase, bases[c][commodity.id]); });
        offer.reward = Math.max(1, Math.round(qty * (rewardPerUnit * 1.5 + (anyBase || 150) * 0.12) * rewardMultiplier));
      }
      return offer;
    });

    return { offers: offers, reputationHere: reputation, gameDay: gameDay };
  }

  function freeHold_(playerId) {
    var ship = ShipService.getShip(playerId);
    return (Number(ship && ship.EffectiveCargo) || 0) - CargoService.getTotalCargoQty(playerId);
  }

  function acceptNewMission(cityId, offerIndex) {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();

      if (getActiveMissionRow_(playerId)) {
        throw new Error('Kamu masih punya misi aktif - selesaikan atau batalkan dulu.');
      }
      if (LocationService.getCurrentCityId(playerId) !== cityId) {
        throw new Error('Kamu harus berada di kota ini untuk menerima misi.');
      }
      if (LocationService.getVoyageState(playerId).inTransit) {
        throw new Error('Kamu sedang berlayar.');
      }

      var board = getMissionBoard(cityId);
      var offer = board.offers[offerIndex];
      if (!offer) throw new Error('Penawaran misi tidak ditemukan - papan mungkin sudah berganti hari.');
      if (!offer.unlocked) {
        throw new Error('Reputasimu di kota ini belum cukup (butuh Standing ' + offer.minReputation +
          ', kamu punya ' + board.reputationHere + ').');
      }
      if (!offer.deliverToCityId) throw new Error('Tidak ada kota tujuan untuk misi saat ini.');
      if (offer.type === 'procure' && !offer.sourceCityId) throw new Error('Tidak ada pulau yang menjual barang pesanan ini.');

      var loaded = 0;
      if (offer.type === 'courier') {
        var free = freeHold_(playerId);
        if (free < offer.qty) {
          throw new Error('Palka tidak cukup untuk barang titipan (butuh ' + offer.qty + ' ruang, sisa ' + Math.max(0, free) + '). Jual atau titip barang dulu.');
        }
        loaded = offer.qty; // barang titipan langsung dimuat
      }

      ensureHeaders_();
      var missionId = Utilities.getUuid();
      getSheet_().appendRow([
        playerId, missionId, 'active', TimeService.getCurrentGameDay(),
        cityId, offer.commodityId, offer.qty, offer.deliverToCityId, offer.reward,
        offer.type, offer.sourceCityId || '', loaded
      ]);
      SheetCache.invalidate('PlayerMissions');

      if (offer.type === 'courier') {
        LogService.addLog(playerId, 'Menerima titipan ' + offer.qty + ' ' + offer.commodityName + ' untuk diantar ke ' +
          offer.deliverToCityName + ' (imbalan ' + offer.reward + ' gold). Barang titipan sudah dimuat ke kapal.');
      } else {
        LogService.addLog(playerId, 'Menerima pesanan ' + offer.qty + ' ' + offer.commodityName + ' - beli di ' +
          offer.sourceCityName + ', antar ke ' + offer.deliverToCityName + ' (imbalan ' + offer.reward + ' gold).');
      }
      return getMissionState(playerId);
    } finally {
      lock.releaseLock();
    }
  }

  /**
   * Misi Pesanan: beli barang pesanan di pulau sumber. Harga = harga beli
   * pasar untuk pemain ini (diskon Trading/buku/reputasi tetap berlaku).
   * Barang langsung masuk muatan misi (terkunci), bukan palka biasa.
   */
  function buyForMission() {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var active = getActiveMissionRow_(playerId);
      if (!active) throw new Error('Tidak ada misi aktif.');
      if (active.type !== 'procure') throw new Error('Misi ini bukan pesanan barang.');
      var need = active.qty - active.loadedQty;
      if (need <= 0) throw new Error('Barang pesanan sudah lengkap. Antar ke ' + cityName_(active.deliverToCityId) + '.');
      if (LocationService.getVoyageState(playerId).inTransit) throw new Error('Kamu sedang berlayar.');
      if (LocationService.getCurrentCityId(playerId) !== active.sourceCityId) {
        throw new Error('Barang pesanan ini hanya boleh dibeli di ' + cityName_(active.sourceCityId) + '.');
      }
      var unit = MarketService.quoteBuy(playerId, active.sourceCityId, active.commodityId);
      if (!unit) throw new Error('Barang ini sedang tidak dijual di kota ini.');
      var total = unit * need;
      var player = PlayerService.getOrCreatePlayer();
      if (player.gold < total) throw new Error('Gold tidak cukup. Butuh ' + total + ' untuk ' + need + ' unit, kamu punya ' + player.gold + '.');
      var free = freeHold_(playerId);
      if (free < need) throw new Error('Palka tidak cukup (butuh ' + need + ' ruang, sisa ' + Math.max(0, free) + ').');

      PlayerService.updatePlayerRow(playerId, { Gold: player.gold - total });
      getSheet_().getRange(active.rowIndex, PM_COL.LoadedQty).setValue(active.qty);
      SheetCache.invalidate('PlayerMissions');
      var commodity = getCommodityById(active.commodityId);
      LogService.addLog(playerId, 'Membeli ' + need + ' ' + (commodity ? commodity.name : active.commodityId) + ' pesanan di ' +
        cityName_(active.sourceCityId) + ' seharga ' + total + ' gold (muatan misi, terkunci).');
      return { bought: need, unitPrice: unit, totalCost: total, newGold: player.gold - total, mission: getMissionState(playerId) };
    } finally {
      lock.releaseLock();
    }
  }

  function abandonMission() {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var active = getActiveMissionRow_(playerId);
      if (!active) throw new Error('Tidak ada misi aktif untuk dibatalkan.');

      var note = '';
      if (active.type === 'procure' && active.loadedQty > 0) {
        // Barang pesanan sudah kamu bayar sendiri - kembali jadi barang dagang biasa.
        CargoService.adjustQty(playerId, active.commodityId, active.loadedQty);
        note = ' Barang yang sudah dibeli (' + active.loadedQty + ') kembali ke palka biasa.';
      } else if (active.type === 'courier') {
        note = ' Barang titipan dikembalikan ke pemiliknya.';
      }
      var sh = getSheet_();
      sh.getRange(active.rowIndex, PM_COL.Status).setValue('abandoned');
      if (active.type !== 'legacy') sh.getRange(active.rowIndex, PM_COL.LoadedQty).setValue(0);
      SheetCache.invalidate('PlayerMissions');
      LogService.addLog(playerId, 'Membatalkan misi.' + note);

      return { hasActive: false, note: note.trim() };
    } finally {
      lock.releaseLock();
    }
  }

  function completeMission() {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var active = getActiveMissionRow_(playerId);
      if (!active) throw new Error('Tidak ada misi aktif.');

      if (LocationService.getVoyageState(playerId).inTransit) {
        throw new Error('Kamu masih berlayar - belum bisa menyerahkan misi.');
      }
      if (LocationService.getCurrentCityId(playerId) !== active.deliverToCityId) {
        throw new Error('Kamu belum sampai di ' + cityName_(active.deliverToCityId) + '.');
      }
      var commodity = getCommodityById(active.commodityId);
      var cname = commodity ? commodity.name : active.commodityId;

      if (active.type === 'legacy') {
        // Misi lama (sebelum v8): pemain membawa barangnya sendiri dari palka.
        var owned = CargoService.getCargo(playerId).filter(function (c) { return c.commodityId === active.commodityId; })[0];
        if (!owned || owned.qty < active.qty) throw new Error('Cargo tidak cukup - butuh ' + active.qty + ' ' + cname + '.');
        CargoService.adjustQty(playerId, active.commodityId, -active.qty);
      } else if (active.loadedQty < active.qty) {
        throw new Error(active.type === 'procure'
          ? 'Barang pesanan belum dibeli. Beli dulu di ' + cityName_(active.sourceCityId) + '.'
          : 'Muatan titipan tidak lengkap.');
      }

      var player = PlayerService.getOrCreatePlayer();
      var reputation = {};
      try { reputation = JSON.parse(player.reputation || '{}'); } catch (e) { reputation = {}; }
      reputation[active.deliverToCityId] = (reputation[active.deliverToCityId] || 0) + 1;

      PlayerService.updatePlayerRow(playerId, {
        Gold: player.gold + active.reward,
        Reputation: JSON.stringify(reputation)
      });

      var sh = getSheet_();
      sh.getRange(active.rowIndex, PM_COL.Status).setValue('completed');
      if (active.type !== 'legacy') sh.getRange(active.rowIndex, PM_COL.LoadedQty).setValue(0);
      SheetCache.invalidate('PlayerMissions');

      LogService.addLog(playerId, 'Misi selesai di ' + cityName_(active.deliverToCityId) + ': ' + active.qty + ' ' + cname +
        ' diserahkan, imbalan ' + active.reward + ' gold.');

      return { reward: active.reward, cityId: active.deliverToCityId, type: active.type };
    } finally {
      lock.releaseLock();
    }
  }

  return {
    getMissionState: getMissionState,
    getMissionBoard: getMissionBoard,
    getMissionLoad: getMissionLoad,
    acceptNewMission: acceptNewMission,
    buyForMission: buyForMission,
    abandonMission: abandonMission,
    completeMission: completeMission,
    getReputationForCity: getReputationForCity
  };
})();
