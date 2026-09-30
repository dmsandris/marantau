/**
 * LogService.gs
 * ------------------------------------------------------------------
 * Voyage log per pemain - tampil seperti strip perkamen di bagian
 * bawah layar (referensi screenshot Trade Winds yang dikirim).
 *
 * PERFORMANCE: PlayerLog itu SATU sheet SHARED untuk log SEMUA pemain
 * (tumbuh terus tanpa batas seiring waktu main). getRecentLogs()
 * sebelumnya selalu getDataRange() SELURUH sheet lalu filter - baik-baik
 * saja saat sheet masih kecil, tapi makin lambat makin lama sheet-nya
 * tumbuh. Sekarang dibatasi: kalau sheet sudah besar, cuma baca N baris
 * TERAKHIR (asumsi log baru selalu di-append ke bawah, jadi baris
 * terbaru pasti ada di situ) - lebih dari cukup untuk menampilkan log
 * terakhir SATU pemain tanpa perlu scan seluruh histori dunia.
 * ------------------------------------------------------------------
 */

var LogService = (function () {
  var MAX_ROWS_TO_SCAN = 3000; // batas atas baris yang di-scan per baca

  function addLog(playerId, message) {
    var sheet = SheetCache.getSheet('PlayerLog');
    sheet.appendRow([playerId, TimeService.getCurrentGameDay(), new Date(), message]);
    SheetCache.invalidate('PlayerLog');
  }

  function getRecentLogsData_() {
    var sheet = SheetCache.getSheet('PlayerLog');
    if (!sheet) return [];
    var lastRow = sheet.getLastRow();
    if (lastRow <= 1) return [];

    // Sheet kecil - baca semua lewat cache biasa (dipakai ulang kalau
    // fungsi lain di request yang sama juga butuh PlayerLog).
    if (lastRow <= MAX_ROWS_TO_SCAN) {
      return SheetCache.getData('PlayerLog').slice(1);
    }

    // Sheet besar - cukup baca N baris terakhir (log terbaru selalu di
    // bawah karena append-only), hindari getDataRange() atas seluruh
    // histori dunia yang cuma makin lambat seiring waktu.
    var startRow = lastRow - MAX_ROWS_TO_SCAN + 1;
    var numCols = Math.max(sheet.getLastColumn(), 4);
    return sheet.getRange(startRow, 1, MAX_ROWS_TO_SCAN, numCols).getValues();
  }

  /** Terbaru dulu (descending). limit default 30 entri terakhir. */
  function getRecentLogs(playerId, limit) {
    limit = limit || 30;
    var rows = getRecentLogsData_();

    var mine = [];
    for (var i = 0; i < rows.length; i++) {
      if (rows[i][0] === playerId) {
        mine.push({ gameDay: rows[i][1], timestamp: rows[i][2], message: rows[i][3] });
      }
    }

    mine.sort(function (a, b) { return new Date(b.timestamp) - new Date(a.timestamp); });
    mine = mine.slice(0, limit);

    // Konversi Date -> string ISO SEBELUM dikirim ke client. Objek Date
    // mentah yang bersarang di dalam array of objects kadang gagal
    // di-serialize dengan benar lewat jembatan google.script.run (dites
    // sebagai salah satu kemungkinan penyebab "payload balik null" -
    // ini aman dihilangkan kalau ternyata bukan penyebabnya, tapi tidak
    // ada ruginya dibuat lebih defensif).
    mine.forEach(function (entry) {
      entry.timestamp = entry.timestamp instanceof Date
        ? entry.timestamp.toISOString()
        : String(entry.timestamp || '');
    });

    return mine;
  }

  return {
    addLog: addLog,
    getRecentLogs: getRecentLogs
  };
})();
