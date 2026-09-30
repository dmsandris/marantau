/**
 * PlayerService.gs
 * ------------------------------------------------------------------
 * Identifikasi pemain lewat akun Google (Session.getActiveUser()).
 *
 * PENTING (perubahan Fase 1): getOrCreatePlayer() HANYA membuat row
 * di Players. Stat, kapal, lokasi awal BARU dibuat saat pemain
 * menyelesaikan Character Creation (lihat CharacterService.gs).
 * Ini supaya kita tahu pasti "Archetype kosong = belum bikin karakter"
 * dan bisa mengarahkan ke layar Character Creation di Code.gs.
 *
 * PERFORMANCE: semua baca/tulis sheet Players lewat SheetCache.gs -
 * lihat SheetCache.gs untuk kenapa ini penting (sheet Players dibaca
 * berkali-kali dalam satu request oleh service lain: Bank, Ship
 * Upgrades, Mission reputation, dst).
 * ------------------------------------------------------------------
 */

var PlayerService = (function () {

  function getCurrentPlayerId() {
    // Tide v6: login akun game (token) - dipakai saat web app di-deploy "Execute as: Me".
    if (typeof AUTH_CTX_ !== 'undefined' && AUTH_CTX_ && AUTH_CTX_.playerId) return AUTH_CTX_.playerId;
    if (String(getGameConfigValue_('AuthMode') || '').toLowerCase() === 'account') {
      throw new Error('AUTH_REQUIRED: Silakan masuk dengan akun Marantau-mu.');
    }
    var email = '';
    try { email = Session.getActiveUser().getEmail(); } catch (e) { email = ''; }
    if (!email) {
      throw new Error('AUTH_REQUIRED: Silakan masuk dengan akun Marantau-mu.');
    }
    // Normalisasi (lowercase + trim) supaya satu akun Google SELALU dipetakan
    // ke baris Players yang sama persis, apapun kapitalisasi email yang
    // dikembalikan Session di berbagai kondisi - ini kunci "karakter selalu
    // nyambung" yang diminta di roadmap.
    return email.trim().toLowerCase();
  }

  function getOrCreatePlayer() {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);

    try {
      var playerId = getCurrentPlayerId();
      var sheet = SheetCache.getSheet('Players');
      var data = SheetCache.getData('Players');

      for (var i = 1; i < data.length; i++) {
        if (data[i][0] === playerId) {
          sheet.getRange(i + 1, 7).setValue(new Date()); // update LastActive
          SheetCache.invalidate('Players');
          return rowToPlayerObject(data[i]);
        }
      }

      var newRow = [playerId, '', '', 0, '{}', new Date(), new Date()];
      sheet.appendRow(newRow);
      SheetCache.invalidate('Players');
      return rowToPlayerObject(newRow);
    } finally {
      lock.releaseLock();
    }
  }

  function rowToPlayerObject(row) {
    return {
      playerId: row[0],
      characterName: row[1],
      archetype: row[2],
      gold: row[3],
      reputation: row[4],
      // Date -> string ISO SEBELUM dikirim ke client. Ini kemungkinan
      // besar akar masalah "api_getGameState() balik null lewat
      // google.script.run" - objek Date mentah yang bersarang di dalam
      // objek kompleks (player di dalam state) gagal di-serialize lewat
      // jembatan RPC Apps Script, padahal function-nya sendiri sukses
      // dan tidak melempar error (makanya Executions bilang "Completed").
      createdAt: row[5] instanceof Date ? row[5].toISOString() : String(row[5] || ''),
      lastActive: row[6] instanceof Date ? row[6].toISOString() : String(row[6] || ''),
      hasCharacter: row[2] !== ''
    };
  }

  /** Dipakai CharacterService saat menyelesaikan character creation. */
  function updatePlayerRow(playerId, updates) {
    var sheet = SheetCache.getSheet('Players');
    var data = SheetCache.getData('Players');
    var headers = data[0];

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        Object.keys(updates).forEach(function (key) {
          var col = headers.indexOf(key);
          if (col >= 0) sheet.getRange(i + 1, col + 1).setValue(updates[key]);
        });
        SheetCache.invalidate('Players');
        return;
      }
    }
    throw new Error('Player ' + playerId + ' tidak ditemukan.');
  }

  /** Tide v6: baca pemain LAIN (untuk dagang/duel antar-pemain). null kalau tidak ada. */
  function getPlayerById(playerId) {
    var data = SheetCache.getData('Players');
    for (var i = 1; i < data.length; i++) if (data[i][0] === playerId) return rowToPlayerObject(data[i]);
    return null;
  }

  /** Tide v6: pastikan baris Players ada untuk playerId akun (tanpa butuh sesi Google). */
  function ensurePlayerRow(playerId) {
    if (getPlayerById(playerId)) return;
    var sheet = SheetCache.getSheet('Players');
    sheet.appendRow([playerId, '', '', 0, '{}', new Date(), new Date()]);
    SheetCache.invalidate('Players');
  }

  return {
    getCurrentPlayerId: getCurrentPlayerId,
    getOrCreatePlayer: getOrCreatePlayer,
    updatePlayerRow: updatePlayerRow,
    getPlayerById: getPlayerById,
    ensurePlayerRow: ensurePlayerRow
  };
})();
