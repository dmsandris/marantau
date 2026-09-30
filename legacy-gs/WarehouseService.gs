/**
 * WarehouseService.gs
 * ------------------------------------------------------------------
 * Disadur dari Tradewinds 2: "Port Authority" tempat pemain bisa titip
 * (beli warehouse) barang di sebuah kota - lihat TRADEWINDS2_RESEARCH.md.
 * Versi kita: titip barang dari cargo kapal ke gudang KOTA TERTENTU
 * (per kota, tidak portable) dengan biaya sekali bayar per unit,
 * ambil kembali gratis kapan saja selama kembali ke kota itu.
 *
 * Berguna untuk: (1) menyiasati kapasitas cargo terbatas saat borong
 * barang murah, (2) menyimpan barang buat nunggu harga bagus tanpa
 * "mengunci" ruang cargo buat trip berikutnya.
 * ------------------------------------------------------------------
 */

var WarehouseService = (function () {

  function getWarehouseContents(playerId, cityId) {
    var data = SheetCache.getData('Warehouse');
    var items = [];

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId && data[i][1] === cityId && data[i][3] > 0) {
        var commodity = getCommodityById(data[i][2]);
        items.push({
          commodityId: data[i][2],
          name: commodity ? commodity.name : data[i][2],
          qty: data[i][3]
        });
      }
    }
    return items;
  }

  function storeItem(cityId, commodityId, qty) {
    qty = Math.floor(Number(qty));
    if (!qty || qty <= 0) throw new Error('Jumlah tidak valid.');

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      if (LocationService.getCurrentCityId(playerId) !== cityId) {
        throw new Error('Kamu harus berada di kota ini untuk titip barang.');
      }
      if (LocationService.getVoyageState(playerId).inTransit) {
        throw new Error('Kamu sedang berlayar.');
      }

      var feePerUnit = getGameConfigNumber_('WarehouseFeePerUnit', 2);
      var fee = feePerUnit * qty;
      var player = PlayerService.getOrCreatePlayer();
      if (player.gold < fee) throw new Error('Gold tidak cukup untuk biaya titip (' + fee + ' gold).');

      var owned = CargoService.getCargo(playerId).filter(function (c) { return c.commodityId === commodityId; })[0];
      if (!owned || owned.qty < qty) {
        throw new Error('Cargo tidak cukup untuk dititipkan.');
      }

      CargoService.adjustQty(playerId, commodityId, -qty);

      var sheet = SheetCache.getSheet('Warehouse');
      var data = SheetCache.getData('Warehouse');
      var found = false;
      for (var i = 1; i < data.length; i++) {
        if (data[i][0] === playerId && data[i][1] === cityId && data[i][2] === commodityId) {
          sheet.getRange(i + 1, 4).setValue(Number(data[i][3]) + qty);
          found = true;
          break;
        }
      }
      if (!found) sheet.appendRow([playerId, cityId, commodityId, qty]);
      SheetCache.invalidate('Warehouse');

      PlayerService.updatePlayerRow(playerId, { Gold: player.gold - fee });

      var commodity = getCommodityById(commodityId);
      LogService.addLog(playerId, 'Stored ' + qty + ' ' + (commodity ? commodity.name : commodityId) +
        ' at the warehouse (fee: ' + fee + ' gold).');

      return { fee: fee, newGold: player.gold - fee };
    } finally {
      lock.releaseLock();
    }
  }

  function withdrawItem(cityId, commodityId, qty) {
    qty = Math.floor(Number(qty));
    if (!qty || qty <= 0) throw new Error('Jumlah tidak valid.');

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      if (LocationService.getCurrentCityId(playerId) !== cityId) {
        throw new Error('Kamu harus berada di kota ini untuk ambil barang dari gudang.');
      }

      var ship = ShipService.getShip(playerId);
      var currentCargoQty = CargoService.getTotalCargoQty(playerId);
      if (currentCargoQty + qty > ship.EffectiveCargo) {
        throw new Error('Kapasitas cargo tidak cukup untuk mengambil semua ini.');
      }

      var sheet = SheetCache.getSheet('Warehouse');
      var data = SheetCache.getData('Warehouse');
      var rowIndex = -1;
      for (var i = 1; i < data.length; i++) {
        if (data[i][0] === playerId && data[i][1] === cityId && data[i][2] === commodityId) {
          rowIndex = i;
          break;
        }
      }
      if (rowIndex === -1 || data[rowIndex][3] < qty) throw new Error('Jumlah di gudang tidak cukup.');

      sheet.getRange(rowIndex + 1, 4).setValue(data[rowIndex][3] - qty);
      SheetCache.invalidate('Warehouse');
      CargoService.adjustQty(playerId, commodityId, qty);

      var commodity = getCommodityById(commodityId);
      LogService.addLog(playerId, 'Retrieved ' + qty + ' ' + (commodity ? commodity.name : commodityId) + ' from the warehouse.');

      return { ok: true };
    } finally {
      lock.releaseLock();
    }
  }

  return {
    getWarehouseContents: getWarehouseContents,
    storeItem: storeItem,
    withdrawItem: withdrawItem
  };
})();
