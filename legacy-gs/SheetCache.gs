/**
 * SheetCache.gs
 * ------------------------------------------------------------------
 * PERFORMANCE FIX (lihat PATCH_NOTES_Performance-Optimization.md).
 *
 * Root cause dari latency 8-15 detik per aksi (buy/sell/upgrade/dsb):
 * SETIAP fungsi service sebelumnya memanggil sendiri-sendiri
 *   SpreadsheetApp.getActiveSpreadsheet().getSheetByName(X).getDataRange().getValues()
 * meski sheet yang sama sudah dibaca berkali-kali dalam SATU request.
 * Contoh nyata: satu panggilan api_getGameState() membaca sheet Players
 * 3-4x, PlayerLocation 3x, GameConfig 4-5x - masing-masing adalah SATU
 * round-trip API terpisah ke Google Sheets (~200-500ms). Ditambah client
 * yang memanggil ulang seluruh api_getGameState() lagi setelah SETIAP
 * aksi (loadState()), total bisa 30+ round-trip untuk satu klik "Beli".
 *
 * SheetCache MEMOIZE hasil getDataRange().getValues() per nama sheet,
 * berlaku SELAMA SATU EKSEKUSI (satu panggilan api_ dari client).
 * Setiap fungsi service tinggal ganti:
 *   var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('X');
 *   var data = sheet.getDataRange().getValues();
 * menjadi:
 *   var sheet = SheetCache.getSheet('X');
 *   var data = SheetCache.getData('X');
 * dan WAJIB panggil SheetCache.invalidate('X') tepat setelah menulis ke
 * sheet itu (setValue/appendRow/deleteRow) - supaya baca berikutnya DALAM
 * eksekusi yang sama tidak memakai data basi.
 *
 * SheetCache.reset() dipanggil di AWAL setiap fungsi api_ di Code.gs -
 * ini bukan cuma optimisasi, tapi juga jaring pengaman: Apps Script TIDAK
 * menjamin variable global tetap sama antar-request terpisah, jadi reset
 * eksplisit di setiap entry point memastikan tidak ada data basi
 * "bocor" ke request lain walau kebetulan container di-reuse Google.
 * ------------------------------------------------------------------
 */

var SheetCache = (function () {
  var dataCache = {};   // sheetName -> 2D values array (termasuk header row)
  var sheetRefs = {};   // sheetName -> objek Sheet (hindari getSheetByName berulang)

  function getSheet(name) {
    if (!sheetRefs[name]) {
      sheetRefs[name] = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(name);
    }
    return sheetRefs[name];
  }

  function getData(name) {
    if (!dataCache[name]) {
      var sheet = getSheet(name);
      dataCache[name] = sheet ? sheet.getDataRange().getValues() : [];
    }
    return dataCache[name];
  }

  function getHeaders(name) {
    var data = getData(name);
    return data.length ? data[0] : [];
  }

  /** Panggil setelah menulis (setValue/appendRow/deleteRow) ke sheet ini. */
  function invalidate(name) {
    delete dataCache[name];
  }

  /** Dipanggil di awal setiap fungsi api_ - lihat Code.gs. */
  function reset() {
    dataCache = {};
    sheetRefs = {};
  }

  return {
    getSheet: getSheet,
    getData: getData,
    getHeaders: getHeaders,
    invalidate: invalidate,
    reset: reset
  };
})();
