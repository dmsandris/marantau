/**
 * CargoService.gs
 * ------------------------------------------------------------------
 * PlayerInventory = cargo di kapal. Kapasitas dibatasi oleh Ship.Cargo.
 * PERFORMANCE: baca/tulis lewat SheetCache.gs.
 * ------------------------------------------------------------------
 */

var CargoService = (function () {

  function getCargo(playerId) {
    var data = SheetCache.getData('PlayerInventory');
    var items = [];

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId && data[i][2] > 0) {
        var commodity = getCommodityById(data[i][1]);
        items.push({
          commodityId: data[i][1],
          name: commodity ? commodity.name : data[i][1],
          qty: data[i][2]
        });
      }
    }
    return items;
  }

  /** Total unit yang memakan ruang palka: barang dagang + muatan misi terkunci (Tide v8). */
  function getTotalCargoQty(playerId) {
    var trade = getCargo(playerId).reduce(function (sum, item) { return sum + item.qty; }, 0);
    var mission = 0;
    try { mission = MissionService.getMissionLoad(playerId) || 0; } catch (e) { mission = 0; }
    return trade + mission;
  }

  /** delta boleh negatif (mengurangi). Baris dengan qty 0 tetap disimpan, difilter saat getCargo(). */
  function adjustQty(playerId, commodityId, delta) {
    var sheet = SheetCache.getSheet('PlayerInventory');
    var data = SheetCache.getData('PlayerInventory');

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId && data[i][1] === commodityId) {
        var newQty = data[i][2] + delta;
        if (newQty < 0) throw new Error('Jumlah cargo tidak boleh negatif.');
        sheet.getRange(i + 1, 3).setValue(newQty);
        SheetCache.invalidate('PlayerInventory');
        return newQty;
      }
    }

    if (delta < 0) throw new Error('Kamu tidak punya cargo ini untuk dijual.');
    sheet.appendRow([playerId, commodityId, delta]);
    SheetCache.invalidate('PlayerInventory');
    return delta;
  }

  return {
    getCargo: getCargo,
    getTotalCargoQty: getTotalCargoQty,
    adjustQty: adjustQty
  };
})();
