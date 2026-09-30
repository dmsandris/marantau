/**
 * AudioService.gs
 * ------------------------------------------------------------------
 * Sumber suara game (BGM) dikontrol dari sheet GameConfig, jadi bisa
 * diganti admin kapan saja tanpa perlu deploy ulang script.
 *
 * Cara pasang BGM dari Google Drive:
 *   1. Upload file audio (mp3, disarankan di bawah ~10-15MB supaya loading
 *      cepat) ke Google Drive.
 *   2. Klik kanan file -> Share -> ubah access jadi "Anyone with the link"
 *      (role: Viewer). Ini WAJIB, kalau tidak browser pemain akan gagal load.
 *   3. Copy link share-nya (boleh format apa saja, contoh:
 *      https://drive.google.com/file/d/XXXXXXXX/view?usp=sharing).
 *   4. Buka sheet GameConfig di spreadsheet, cari baris Key = SoundBgmUrl,
 *      lalu isi kolom Value dengan link tadi.
 *      (Kalau baris ini belum ada, jalankan migrateFase1Improvements()
 *      sekali dari editor Apps Script - lihat SetupSheets.gs.)
 *   5. Reload game - BGM otomatis kepakai. Player tetap bisa mute/atur
 *      volume sendiri lewat menu Settings (preferensi disimpan di
 *      browser masing-masing, bukan di sheet).
 *   6. Kalau mau mematikan musik untuk semua pemain sementara (misal file
 *      rusak), set GameConfig.SoundEnabled = FALSE tanpa perlu hapus link.
 * ------------------------------------------------------------------
 */

var AudioService = (function () {

  function getAudioConfig() {
    var bgmRaw = getGameConfigValue_('SoundBgmUrl');
    var enabledRaw = getGameConfigValue_('SoundEnabled');

    return {
      bgmUrl: bgmRaw ? driveUrlToDirect_(bgmRaw) : '',
      // Default TRUE kalau baris belum ada sama sekali di GameConfig.
      enabledByAdmin: enabledRaw === false ? false : true
    };
  }

  return { getAudioConfig: getAudioConfig };
})();
