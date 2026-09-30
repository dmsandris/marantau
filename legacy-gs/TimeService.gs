/**
 * TimeService.gs
 * ------------------------------------------------------------------
 * Mengelola waktu dunia (shared, sama untuk semua pemain).
 *
 * PENTING: GameDay dihitung ulang setiap kali dipanggil dari
 * WorldStartTimestamp - BUKAN disimpan sebagai counter yang di-
 * increment oleh trigger. Alasan: Apps Script time-driven trigger
 * tidak dijamin presisi (bisa telat/di-skip), jadi kalau hari-game
 * bergantung pada trigger yang jalan tepat waktu, hari-game bisa
 * jadi tidak konsisten antar sesi.
 *
 * Dengan pendekatan timestamp, GameDay selalu akurat walau trigger
 * telat - trigger cuma dipakai untuk hal yang boleh sedikit telat,
 * misalnya re-roll harga market (lihat MarketService di Fase 1).
 *
 * Referensi: GDD §10.5 dan §16.2 (Risiko 2).
 *
 * PERFORMANCE: baca GameConfig lewat getGameConfigValue_() (Utils.gs),
 * yang sudah di-cache lintas request (CacheService) - lihat Utils.gs.
 * ------------------------------------------------------------------
 */

var TimeService = (function () {

  function getCurrentGameDay() {
    var worldStart = Number(getGameConfigValue_('WorldStartTimestamp'));
    var dayLengthMinutes = Number(getGameConfigValue_('GameDayLengthRealMinutes'));

    if (!worldStart || !dayLengthMinutes) {
      throw new Error('GameConfig belum di-seed. Jalankan setupAllSheets() dulu.');
    }

    var dayLengthMs = dayLengthMinutes * 60 * 1000;
    var elapsedMs = new Date().getTime() - worldStart;
    return Math.floor(elapsedMs / dayLengthMs);
  }

  /**
   * Berapa menit nyata lagi sampai hari-game berikutnya.
   * Berguna untuk UI (mis. countdown "harga berubah dalam Xm").
   */
  function getMinutesUntilNextGameDay() {
    var worldStart = Number(getGameConfigValue_('WorldStartTimestamp'));
    var dayLengthMinutes = Number(getGameConfigValue_('GameDayLengthRealMinutes'));
    var dayLengthMs = dayLengthMinutes * 60 * 1000;

    var elapsedMs = new Date().getTime() - worldStart;
    var msIntoCurrentDay = elapsedMs % dayLengthMs;
    var msRemaining = dayLengthMs - msIntoCurrentDay;

    return Math.ceil(msRemaining / 60000);
  }

  return {
    getCurrentGameDay: getCurrentGameDay,
    getMinutesUntilNextGameDay: getMinutesUntilNextGameDay
  };
})();
