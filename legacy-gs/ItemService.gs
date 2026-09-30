/**
 * ItemService.gs — Fase 5 (Exploration & Treasure)
 * ------------------------------------------------------------------
 * Mengelola ItemCatalog + PlayerInventory untuk ITEM (treasure map,
 * artifact) - sheet PlayerInventory yang sama dengan cargo komoditas
 * (lihat CargoService.gs), dibedakan lewat ItemId yang HANYA ada di
 * ItemCatalog (bukan di COMMODITIES). CargoService.getCargo() sudah
 * di-patch supaya baris item tidak ikut tampil sebagai cargo dagangan.
 *
 * Dua Type item:
 *   - 'treasure_map' : consumable, dipakai TreasureService.digTreasure().
 *                      Effects (JSON): {"siteId":"...","requiresBookKeyword":"..."}
 *   - 'artifact'      : non-consumable, dipasang ke ShipEquipment - DUA
 *                      slot per pemain ('artifact' & 'artifact_2', lihat
 *                      SLOT_KEYS) sejak update slot kedua. Efeknya HANYA
 *                      aktif selagi terpasang (equip memindahkan item dari
 *                      PlayerInventory ke ShipEquipment, bukan menduplikasi).
 *                      Effects (JSON): {"SpecialEffect":"keyword"} - keyword
 *                      yang sama dengan BookService.hasSpecialEffect(),
 *                      supaya ShipService/MarketService cukup cek DUA sumber
 *                      (buku ATAU artifact terpasang) di titik yang sama.
 *                      Dengan 2 slot, KEDUA efek artifact bisa aktif
 *                      bersamaan (mis. cargo_bonus_10 + black_market_discount).
 *
 * PERFORMANCE: katalog di-cache lintas-request (sama pola BookService),
 * jarang berubah - admin edit ItemCatalog di-invalidate lewat onEdit
 * di Code.gs.
 * ------------------------------------------------------------------
 */

var ItemService = (function () {
  var CATALOG_CACHE_KEY = 'itemservice_catalog_v1';
  var CATALOG_CACHE_TTL_SECONDS = 300;
  // Dua slot equipment - 'artifact' dipertahankan sebagai nama slot 1
  // (backward-compat dengan baris ShipEquipment yang sudah ada dari v1
  // single-slot), 'artifact_2' adalah slot kedua yang baru.
  var SLOT_KEYS = ['artifact', 'artifact_2'];

  function getItemCatalog() {
    var cache = CacheService.getScriptCache();
    var cached = cache.get(CATALOG_CACHE_KEY);
    if (cached) {
      try { return JSON.parse(cached); } catch (e) { /* cache korup, baca ulang di bawah */ }
    }

    var data = SheetCache.getData('ItemCatalog');
    var headers = data[0];
    var items = [];

    for (var i = 1; i < data.length; i++) {
      if (!data[i][0]) continue;
      var item = {};
      headers.forEach(function (h, idx) { item[h] = data[i][idx]; });
      items.push(item);
    }

    cache.put(CATALOG_CACHE_KEY, JSON.stringify(items), CATALOG_CACHE_TTL_SECONDS);
    return items;
  }

  function invalidateCatalogCache() {
    CacheService.getScriptCache().remove(CATALOG_CACHE_KEY);
  }

  function getItemById(itemId) {
    var catalog = getItemCatalog();
    for (var i = 0; i < catalog.length; i++) {
      if (catalog[i].ItemId === itemId) return catalog[i];
    }
    return null;
  }

  function parseEffects_(raw) {
    if (!raw) return {};
    try {
      var parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (e) {
      return {};
    }
  }

  /** Qty item tertentu di PlayerInventory (0 kalau tidak punya). */
  function getItemQty(playerId, itemId) {
    var data = SheetCache.getData('PlayerInventory');
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId && data[i][1] === itemId) return Number(data[i][2]) || 0;
    }
    return 0;
  }

  /** delta boleh negatif. Sama semantik dengan CargoService.adjustQty tapi khusus ItemId. */
  function adjustItemQty_(playerId, itemId, delta) {
    var sheet = SheetCache.getSheet('PlayerInventory');
    var data = SheetCache.getData('PlayerInventory');

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId && data[i][1] === itemId) {
        var newQty = Number(data[i][2]) + delta;
        if (newQty < 0) throw new Error('Jumlah item tidak boleh negatif.');
        sheet.getRange(i + 1, 3).setValue(newQty);
        SheetCache.invalidate('PlayerInventory');
        return newQty;
      }
    }

    if (delta < 0) throw new Error('Kamu tidak punya item ini.');
    sheet.appendRow([playerId, itemId, delta]);
    SheetCache.invalidate('PlayerInventory');
    return delta;
  }

  function grantItem(playerId, itemId, qty) {
    qty = qty || 1;
    return adjustItemQty_(playerId, itemId, qty);
  }

  function consumeItem(playerId, itemId, qty) {
    qty = qty || 1;
    return adjustItemQty_(playerId, itemId, -qty);
  }

  /** Semua baris PlayerInventory milik pemain yang ItemId-nya dikenali ItemCatalog (qty > 0). */
  function getRawPlayerItems_(playerId) {
    var data = SheetCache.getData('PlayerInventory');
    var catalog = getItemCatalog();
    var catalogMap = {};
    catalog.forEach(function (it) { catalogMap[it.ItemId] = it; });

    var out = [];
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId && Number(data[i][2]) > 0 && catalogMap[data[i][1]]) {
        out.push({ item: catalogMap[data[i][1]], qty: Number(data[i][2]) });
      }
    }
    return out;
  }

  function getEquippedRow_(playerId, slotKey) {
    var data = SheetCache.getData('ShipEquipment');
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId && data[i][1] === slotKey) {
        return { rowIndex: i + 1, itemId: data[i][2] };
      }
    }
    return null;
  }

  /** Semua slot equipment pemain, urut sesuai SLOT_KEYS - null di slot yang kosong. */
  function getEquippedRows_(playerId) {
    return SLOT_KEYS.map(function (slotKey) {
      var row = getEquippedRow_(playerId, slotKey);
      return row ? { slotKey: slotKey, rowIndex: row.rowIndex, itemId: row.itemId } : { slotKey: slotKey, rowIndex: null, itemId: null };
    });
  }

  function getEquippedArtifactId(playerId) {
    // Back-compat: dipakai kode lama yang cuma butuh SATU id (mis. cek
    // cepat) - kembalikan dari slot pertama yang terisi.
    var rows = getEquippedRows_(playerId);
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].itemId) return rows[i].itemId;
    }
    return null;
  }

  function getEquippedArtifactIds(playerId) {
    return getEquippedRows_(playerId).filter(function (r) { return r.itemId; }).map(function (r) { return r.itemId; });
  }

  /** Keyword SpecialEffect dari SEMUA artifact yang SEDANG terpasang (bisa 0/1/2 keyword, deduplikasi). */
  function getEquippedSpecialEffects(playerId) {
    var seen = {};
    getEquippedArtifactIds(playerId).forEach(function (itemId) {
      var item = getItemById(itemId);
      if (!item) return;
      var effects = parseEffects_(item.Effects);
      if (effects.SpecialEffect) seen[effects.SpecialEffect] = true;
    });
    return Object.keys(seen);
  }

  function hasEquippedEffect(playerId, keyword) {
    return getEquippedSpecialEffects(playerId).indexOf(keyword) !== -1;
  }

  /** View untuk panel Items: daftar artifact yang dimiliki (di cargo) + status KEDUA slot. */
  function getPlayerArtifactsView(playerId) {
    var equippedRows = getEquippedRows_(playerId);
    var equippedIds = equippedRows.map(function (r) { return r.itemId; });

    var owned = getRawPlayerItems_(playerId)
      .filter(function (row) { return row.item.Type === 'artifact'; })
      .map(function (row) {
        var effects = parseEffects_(row.item.Effects);
        return {
          itemId: row.item.ItemId,
          name: row.item.Name,
          value: Number(row.item.Value) || 0,
          specialEffect: effects.SpecialEffect || '',
          qty: row.qty
        };
      });

    var equippedSlots = equippedRows.map(function (r) {
      if (!r.itemId) return { slotKey: r.slotKey, itemId: null };
      var item = getItemById(r.itemId);
      if (!item) return { slotKey: r.slotKey, itemId: null };
      var eqEffects = parseEffects_(item.Effects);
      return {
        slotKey: r.slotKey,
        itemId: item.ItemId,
        name: item.Name,
        specialEffect: eqEffects.SpecialEffect || ''
      };
    });

    return { owned: owned, equippedSlots: equippedSlots, slotsFull: equippedIds.filter(Boolean).length >= SLOT_KEYS.length };
  }

  /**
   * Pasang artifact ke slot kosong pertama (slot 1 lalu slot 2). Kalau
   * kedua slot sudah penuh, minta pemain copot salah satu dulu lewat
   * unequipArtifact(slotKey) - tidak auto-replace supaya tidak ada
   * artifact yang "hilang tanpa sengaja" dari aksi yang niatnya cuma pasang.
   */
  function equipArtifact(itemId) {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var item = getItemById(itemId);
      if (!item || item.Type !== 'artifact') throw new Error('Item ini bukan artifact yang bisa dipasang.');
      if (getItemQty(playerId, itemId) < 1) throw new Error('Kamu tidak punya artifact ini di cargo.');

      var rows = getEquippedRows_(playerId);
      if (rows.some(function (r) { return r.itemId === itemId; })) {
        throw new Error('Artifact ini sudah terpasang.');
      }

      var emptySlot = rows.filter(function (r) { return !r.itemId; })[0];
      if (!emptySlot) throw new Error('Kedua slot equipment sudah penuh - copot salah satu dulu.');

      SheetCache.getSheet('ShipEquipment').appendRow([playerId, emptySlot.slotKey, itemId]);
      SheetCache.invalidate('ShipEquipment');
      consumeItem(playerId, itemId, 1);
      LogService.addLog(playerId, 'Equipped the artifact "' + item.Name + '" to the ship.');

      return getPlayerArtifactsView(playerId);
    } finally {
      lock.releaseLock();
    }
  }

  /** slotKey wajib diisi kalau ada >1 slot terisi - lihat api_unequipArtifact() di Code.gs. */
  function unequipArtifact(slotKey) {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var rows = getEquippedRows_(playerId).filter(function (r) { return r.itemId; });
      if (!rows.length) throw new Error('Tidak ada artifact yang terpasang.');

      var target = slotKey ? rows.filter(function (r) { return r.slotKey === slotKey; })[0] : rows[0];
      if (!target) throw new Error('Slot itu sedang kosong.');

      SheetCache.getSheet('ShipEquipment').deleteRow(target.rowIndex);
      SheetCache.invalidate('ShipEquipment');
      grantItem(playerId, target.itemId, 1);

      var item = getItemById(target.itemId);
      LogService.addLog(playerId, 'Unequipped the artifact "' + (item ? item.Name : target.itemId) + '".');

      return getPlayerArtifactsView(playerId);
    } finally {
      lock.releaseLock();
    }
  }

  /** Jual item non-consumable (artifact) ke harga flat ItemCatalog.Value - tidak fluktuatif seperti Market. */
  function sellItem(itemId, qty) {
    qty = Math.max(1, Math.floor(Number(qty) || 1));
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var item = getItemById(itemId);
      if (!item) throw new Error('Item tidak dikenali: ' + itemId);
      if (getEquippedArtifactIds(playerId).indexOf(itemId) !== -1) {
        throw new Error('Copot dulu artifact ini sebelum dijual.');
      }
      if (getItemQty(playerId, itemId) < qty) throw new Error('Jumlah item tidak cukup.');

      var gold = Math.round((Number(item.Value) || 0) * qty);
      consumeItem(playerId, itemId, qty);

      var player = PlayerService.getOrCreatePlayer();
      PlayerService.updatePlayerRow(playerId, { Gold: player.gold + gold });
      LogService.addLog(playerId, 'Sold ' + qty + 'x "' + item.Name + '" for ' + gold + ' gold.');

      return { newGold: player.gold + gold, goldEarned: gold };
    } finally {
      lock.releaseLock();
    }
  }

  /**
   * Toko peta - treasure map yang punya ItemCatalog.Source === cityId
   * (atau 'any') DAN ItemCatalog.Price terisi bisa dibeli langsung,
   * pola sama dengan BookService "dijual di kota ini". Kolom Price/Source
   * ditambahkan lewat migrateFase5TreasureShop() di SetupSheets.gs -
   * item lama tanpa kolom itu (Price kosong) otomatis TIDAK muncul di
   * toko, tetap loot-only seperti sebelumnya.
   */
  function getTreasureMapShop(cityId) {
    return getItemCatalog().filter(function (it) {
      return it.Type === 'treasure_map' && it.Price && Number(it.Price) > 0 &&
        (it.Source === cityId || it.Source === 'any');
    }).map(function (it) {
      return { itemId: it.ItemId, name: it.Name, price: Number(it.Price) };
    });
  }

  function buyTreasureMap(itemId) {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var item = getItemById(itemId);
      if (!item || item.Type !== 'treasure_map') throw new Error('Item ini bukan treasure map.');
      if (!item.Price || Number(item.Price) <= 0) throw new Error('Peta ini tidak dijual di sini.');

      var price = Number(item.Price);
      var player = PlayerService.getOrCreatePlayer();
      if (player.gold < price) throw new Error('Gold tidak cukup - butuh ' + price + ', kamu punya ' + player.gold + '.');

      var newGold = player.gold - price;
      PlayerService.updatePlayerRow(playerId, { Gold: newGold });
      grantItem(playerId, itemId, 1);
      LogService.addLog(playerId, 'Bought "' + item.Name + '" for ' + price + ' gold.');

      return { newGold: newGold, itemId: itemId, name: item.Name };
    } finally {
      lock.releaseLock();
    }
  }

  return {
    getItemCatalog: getItemCatalog,
    invalidateCatalogCache: invalidateCatalogCache,
    getItemById: getItemById,
    getItemQty: getItemQty,
    grantItem: grantItem,
    consumeItem: consumeItem,
    getRawPlayerItems_: getRawPlayerItems_,
    getEquippedArtifactId: getEquippedArtifactId,
    getEquippedArtifactIds: getEquippedArtifactIds,
    hasEquippedEffect: hasEquippedEffect,
    getPlayerArtifactsView: getPlayerArtifactsView,
    equipArtifact: equipArtifact,
    unequipArtifact: unequipArtifact,
    sellItem: sellItem,
    getTreasureMapShop: getTreasureMapShop,
    buyTreasureMap: buyTreasureMap,
    parseEffects_: parseEffects_
  };
})();
