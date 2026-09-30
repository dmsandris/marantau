/**
 * Utils.gs
 * ------------------------------------------------------------------
 * Helper umum yang dipakai lintas service. Ditambahkan di update
 * "Fase 1 polish" untuk: (1) konversi link Google Drive jadi URL yang
 * bisa langsung dipakai sebagai src gambar/audio, (2) baca/tulis
 * GameConfig dari mana saja tanpa duplikasi kode, (3) hapus baris
 * milik satu pemain dari sheet manapun (dipakai fitur Delete Character).
 * ------------------------------------------------------------------
 */

/**
 * Menerima berbagai bentuk link Google Drive yang biasa di-copy dari
 * tombol "Share", dan mengembalikan URL yang bisa langsung dipakai
 * sebagai src <img>/<audio> di browser.
 *
 * Didukung:
 *   - https://drive.google.com/file/d/FILE_ID/view?usp=sharing
 *   - https://drive.google.com/open?id=FILE_ID
 *   - https://drive.google.com/uc?id=FILE_ID&export=download
 *   - Link Google Sheets biasa (misal cell berisi IMAGE()) - dikembalikan
 *     apa adanya kalau bukan link drive.google.com/file.
 *   - Direct URL dari hosting lain (GitHub raw, dsb) -> dikembalikan apa adanya.
 *
 * PENTING: file di Drive HARUS di-share "Anyone with the link" (Viewer),
 * kalau tidak browser pemain akan gagal load (403 Forbidden). Untuk file
 * besar (>25-30MB) Drive kadang menampilkan halaman peringatan virus-scan
 * dan bukan file langsung - untuk BGM/foto disarankan tetap di bawah itu.
 */
function driveUrlToDirect_(url) {
  if (!url) return '';
  url = String(url).trim();
  if (!url) return '';

  if (url.indexOf('drive.google.com') === -1) {
    // Bukan link Drive yang dikenali - anggap sudah direct URL.
    return url;
  }

  var idMatch = url.match(/\/file\/d\/([a-zA-Z0-9_-]+)/) ||
                url.match(/[?&]id=([a-zA-Z0-9_-]+)/);

  if (idMatch) {
    return 'https://drive.google.com/uc?export=view&id=' + idMatch[1];
  }

  return url;
}

/**
 * Sama seperti driveUrlToDirect_(), TAPI khusus untuk GAMBAR (foto port,
 * dsb). Google sekarang membatasi hotlink lewat format lama
 * (uc?export=view) - sering gagal load / kena halaman "tidak bisa
 * pratinjau" kalau dipakai sebagai src <img>/background-image dari luar
 * drive.google.com.
 *
 * Format /thumbnail resmi didukung Google untuk embed gambar langsung
 * (ini yang dipakai internal oleh Google Slides/Sites juga), jauh lebih
 * reliable untuk kasus ini dibanding uc?export=view.
 */
function driveUrlToDirectImage_(url) {
  if (!url) return '';
  url = String(url).trim();
  if (!url) return '';

  if (url.indexOf('drive.google.com') === -1) {
    return url;
  }

  var idMatch = url.match(/\/file\/d\/([a-zA-Z0-9_-]+)/) ||
                url.match(/[?&]id=([a-zA-Z0-9_-]+)/);

  if (idMatch) {
    return 'https://drive.google.com/thumbnail?id=' + idMatch[1] + '&sz=w1600';
  }

  return url;
}

/**
 * PERFORMANCE: GameConfig dibaca SANGAT sering (TimeService, harga
 * market, combat tuning, dst - sampai 5x+ per request sebelum fix ini).
 * Nilainya jarang berubah (cuma kalau admin tuning manual), jadi
 * di-cache lintas request pakai CacheService (sama pola BookCatalog di
 * BookService.gs), TTL pendek (2 menit) supaya perubahan tuning admin
 * tetap terasa cepat tanpa perlu baca sheet di HAMPIR SETIAP panggilan.
 * Auto-invalidate begitu admin edit sheet GameConfig langsung (lihat
 * onEdit di Code.gs).
 */
var GAME_CONFIG_CACHE_KEY = 'gameconfig_map_v1';
var GAME_CONFIG_CACHE_TTL_SECONDS = 120;

function getGameConfigMap_() {
  var cache = CacheService.getScriptCache();
  var cached = cache.get(GAME_CONFIG_CACHE_KEY);
  if (cached) {
    try { return JSON.parse(cached); } catch (e) { /* cache korup, baca ulang di bawah */ }
  }

  var data = SheetCache.getData('GameConfig');
  var map = {};
  for (var i = 1; i < data.length; i++) {
    map[data[i][0]] = data[i][1];
  }
  cache.put(GAME_CONFIG_CACHE_KEY, JSON.stringify(map), GAME_CONFIG_CACHE_TTL_SECONDS);
  return map;
}

/** Paksa cache GameConfig di-refresh saat pemanggilan berikutnya. */
function invalidateGameConfigCache_() {
  CacheService.getScriptCache().remove(GAME_CONFIG_CACHE_KEY);
}

/** Ambil satu nilai dari GameConfig, atau null kalau key belum ada. */
function getGameConfigValue_(key) {
  var map = getGameConfigMap_();
  return Object.prototype.hasOwnProperty.call(map, key) ? map[key] : null;
}

/** Set (atau buat baru kalau belum ada) satu key di GameConfig. */
function setGameConfigValue_(key, value) {
  var sheet = SheetCache.getSheet('GameConfig');
  if (!sheet) return;
  var data = SheetCache.getData('GameConfig');
  for (var i = 1; i < data.length; i++) {
    if (data[i][0] === key) {
      sheet.getRange(i + 1, 2).setValue(value);
      SheetCache.invalidate('GameConfig');
      invalidateGameConfigCache_();
      return;
    }
  }
  sheet.appendRow([key, value]);
  SheetCache.invalidate('GameConfig');
  invalidateGameConfigCache_();
}

/** Ambil satu nilai numerik dari GameConfig, fallback kalau kosong/bukan angka. */
function getGameConfigNumber_(key, fallback) {
  var raw = getGameConfigValue_(key);
  var num = Number(raw);
  return raw !== null && raw !== '' && !isNaN(num) ? num : fallback;
}

/**
 * RNG deterministik dari sebuah string seed (mulberry32 + hash string
 * sederhana). Dipakai supaya "Mission Board" (Fase 4) bisa menghasilkan
 * penawaran yang SAMA untuk semua pemain pada hari-game yang sama tanpa
 * perlu menyimpan hasil roll ke sheet - cukup seed dari cityId+gameDay,
 * hasilnya reproducible kapan saja dipanggil ulang di hari yang sama,
 * dan otomatis berganti begitu hari-game berpindah.
 *
 * Mengembalikan FUNGSI generator (panggil berkali-kali untuk nilai
 * berikutnya di urutan yang sama), bukan satu nilai - supaya satu seed
 * bisa dipakai untuk beberapa keputusan berurutan (pilih kota, pilih
 * komoditas, roll qty, dst) tanpa saling bertabrakan.
 */
function seededRandom_(seedStr) {
  var h = 1779033703 ^ String(seedStr).length;
  for (var i = 0; i < seedStr.length; i++) {
    h = Math.imul(h ^ seedStr.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  var seed = h >>> 0;
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    var t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Hapus semua baris milik satu playerId di sebuah sheet (kolom A = PlayerId).
 * Dihapus dari bawah ke atas supaya index baris tidak bergeser di tengah loop.
 * Aman dipanggil untuk sheet yang belum ada isinya, atau sheet yang belum
 * dibuat sama sekali (di-skip diam-diam).
 */
function deleteRowsForPlayer_(sheetName, playerId) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(sheetName);
  if (!sheet) return;

  var data = sheet.getDataRange().getValues();
  for (var i = data.length - 1; i >= 1; i--) {
    if (data[i][0] === playerId) {
      sheet.deleteRow(i + 1);
    }
  }
  SheetCache.invalidate(sheetName);
}
