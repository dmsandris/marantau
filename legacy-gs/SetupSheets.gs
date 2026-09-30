/**
 * SetupSheets.gs
 * ------------------------------------------------------------------
 * Jalankan SATU KALI dari editor Apps Script:
 *   1. Pilih fungsi "setupAllSheets" di dropdown toolbar
 *   2. Klik Run (izinkan permission saat diminta)
 *
 * Aman dijalankan berkali-kali - hanya membuat sheet & header yang
 * belum ada, tidak akan menimpa data yang sudah diisi.
 * ------------------------------------------------------------------
 * Referensi schema: GDD §14 (Skema Google Sheets)
 */

var SHEET_SCHEMA = {
  // ShipUpgrades ditambahkan di Fase 3a - lihat migrateFase3aSetup()
  'Players':         ['PlayerId', 'CharacterName', 'Archetype', 'Gold', 'Reputation', 'CreatedAt', 'LastActive', 'BankBalance', 'BankLastInterestGameDay', 'DebtBalance', 'DebtLastInterestGameDay', 'ShipUpgrades'],
  'CharacterStats':  ['PlayerId', 'Trading', 'Negotiation', 'Navigation', 'Sailing', 'Combat', 'Luck', 'Knowledge'],
  'PlayerBooks':     ['PlayerId', 'BookId', 'DateAcquired'],
  'BookCatalog':     ['BookId', 'Name', 'Tier', 'StatEffects', 'SpecialEffect', 'Price', 'Source'],
  'PlayerInventory': ['PlayerId', 'ItemId', 'Qty'],
  'ItemCatalog':     ['ItemId', 'Name', 'Type', 'Effects', 'Value'],
  // ConditionDecayPerSail/MaxCondition/DamageThreshold ditambahkan di Fase 3a/3c - lihat migrateFase3aSetup()
  'Ship':            ['PlayerId', 'ShipName', 'Tier', 'Hull', 'MaxHull', 'Cargo', 'Speed', 'Combat', 'Armor', 'Navigation', 'Condition', 'ConditionDecayPerSail', 'MaxCondition', 'DamageThreshold'],
  'ShipEquipment':   ['PlayerId', 'SlotType', 'ItemId'],
  'Cities':          ['CityId', 'Name', 'Type', 'RepairCostRate', 'MayorMissionPool', 'ImageUrl', 'MapX', 'MapY'],
  'Market':          ['CityId', 'CommodityId', 'BasePrice', 'CurrentPrice', 'LastUpdated'],
  'Missions':        ['MissionId', 'CityId', 'Difficulty', 'Reward', 'RequiredCargo', 'RequiredQty', 'Status'],
  'PlayerMissions':  ['PlayerId', 'MissionId', 'Status', 'AcceptedAt', 'CityId', 'CommodityId', 'Qty', 'DeliverToCityId', 'Reward', 'Type', 'SourceCityId', 'LoadedQty'],
  'CombatLog':       ['PlayerId', 'Timestamp', 'EnemyLevel', 'Action', 'Result', 'Loot'],
  'GameConfig':      ['Key', 'Value'],

  // Ditambahkan di Fase 1 - additive, aman ditambahkan ke Sheet Fase 0 yang sudah ada
  // DestinationCityId/DepartAt/ArriveAt ditambahkan di fitur "Set Sail" (lihat migrateSetSail())
  // PendingEncounter ditambahkan di Fase 3b - lihat migrateFase3bCombat()
  'PlayerLocation':  ['PlayerId', 'CurrentCityId', 'ArrivedGameDay', 'DestinationCityId', 'DepartAt', 'ArriveAt', 'PendingEncounter'],
  'PlayerLog':       ['PlayerId', 'GameDay', 'Timestamp', 'Message'],

  // Ditambahkan di update "TW2 Improvements" - lihat migrateTW2Improvements()
  'Warehouse':       ['PlayerId', 'CityId', 'CommodityId', 'Qty']
};

function setupAllSheets() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var created = [];

  Object.keys(SHEET_SCHEMA).forEach(function (sheetName) {
    var sheet = ss.getSheetByName(sheetName);
    if (!sheet) {
      sheet = ss.insertSheet(sheetName);
      created.push(sheetName);
    }

    var headers = SHEET_SCHEMA[sheetName];
    var firstRow = sheet.getRange(1, 1, 1, headers.length).getValues()[0];
    var isEmpty = firstRow.join('') === '';

    if (isEmpty) {
      sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
      sheet.setFrozenRows(1);
      sheet.getRange(1, 1, 1, headers.length).setFontWeight('bold');
    }
  });

  // Hapus sheet default "Sheet1" kalau masih kosong dan bukan bagian dari schema kita
  var defaultSheet = ss.getSheetByName('Sheet1');
  if (defaultSheet && defaultSheet.getLastRow() === 0) {
    ss.deleteSheet(defaultSheet);
  }

  seedGameConfig();
  seedCities();
  seedMarket();
  seedBookCatalog();

  var msg = 'Setup selesai. ' + Object.keys(SHEET_SCHEMA).length + ' sheet siap.' +
    (created.length ? ' Baru dibuat: ' + created.join(', ') : ' (semua sudah ada sebelumnya)');
  Logger.log(msg);

  try {
    SpreadsheetApp.getUi().alert(msg);
  } catch (e) {
    // getUi() tidak tersedia kalau dijalankan bukan dari UI Sheets - abaikan saja
  }
}

/**
 * WorldStartTimestamp = titik nol waktu dunia.
 * Hari-game SELALU dihitung ulang dari sini (lihat TimeService.gs),
 * bukan dari counter yang di-increment trigger - ini mencegah bug
 * drift/skip trigger. Lihat GDD §16.2 Risiko 2.
 *
 * Skala waktu: 1 hari-game = 60 menit nyata (1 jam nyata = 1 hari-game,
 * sesuai keputusan "1 hari nyata = 24 hari-game").
 */
function seedGameConfig() {
  requireOwner_();
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('GameConfig');
  var existing = sheet.getDataRange().getValues();
  var hasWorldStart = existing.some(function (row) { return row[0] === 'WorldStartTimestamp'; });

  if (!hasWorldStart) {
    sheet.appendRow(['WorldStartTimestamp', new Date().getTime()]);
    sheet.appendRow(['GameDayLengthRealMinutes', 60]);
  }
}

function seedCities() {
  requireOwner_();
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Cities');
  if (sheet.getLastRow() > 1) return; // sudah ada data, jangan ditimpa

  var rows = [
    ['sunda_empire', 'Sunda Empire', 'TradeHub',     1.0, '', '', 25, 55],
    ['joungjava',    'Joungjava',    'Agricultural', 1.2, '', '', 60, 30],
    ['bjorneo',      'Bjorneo',      'Remote',       1.6, '', '', 75, 75]
  ];
  sheet.getRange(2, 1, rows.length, rows[0].length).setValues(rows);
}

/**
 * Migrasi additive untuk update "Fase 1 polish" (aman dijalankan berkali-kali,
 * TIDAK menimpa data yang sudah ada):
 *   1. Menambahkan kolom ImageUrl ke sheet Cities kalau belum ada - dipakai
 *      untuk background foto port custom per kota (paste link Google Drive
 *      di sana, lihat README).
 *   2. Menyiapkan baris SoundBgmUrl & SoundEnabled di GameConfig kalau
 *      belum ada - dipakai untuk BGM dari Google Drive (lihat AudioService.gs).
 *
 * CARA PAKAI: buka editor Apps Script, pilih "migrateFase1Improvements" di
 * dropdown toolbar (di sebelah tombol Run), klik Run sekali saja.
 */
function migrateFase1Improvements() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  var citiesSheet = ss.getSheetByName('Cities');
  if (citiesSheet) {
    var lastCol = Math.max(citiesSheet.getLastColumn(), 1);
    var headers = citiesSheet.getRange(1, 1, 1, lastCol).getValues()[0];
    if (headers.indexOf('ImageUrl') === -1) {
      var col = lastCol + 1;
      citiesSheet.getRange(1, col).setValue('ImageUrl').setFontWeight('bold');
      log.push('Kolom "ImageUrl" ditambahkan ke sheet Cities (kolom ' + col + '). ' +
        'Isi dengan link foto Google Drive per kota (share "Anyone with the link" dulu).');
    } else {
      log.push('Cities.ImageUrl sudah ada, dilewati.');
    }
  } else {
    log.push('Sheet Cities tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var data = configSheet.getDataRange().getValues();
    var hasBgm = data.some(function (row) { return row[0] === 'SoundBgmUrl'; });
    var hasEnabled = data.some(function (row) { return row[0] === 'SoundEnabled'; });

    if (!hasBgm) {
      configSheet.appendRow(['SoundBgmUrl', '']);
      log.push('GameConfig.SoundBgmUrl ditambahkan (masih kosong - isi link musik Drive kamu di sini).');
    } else {
      log.push('GameConfig.SoundBgmUrl sudah ada, dilewati.');
    }
    if (!hasEnabled) {
      configSheet.appendRow(['SoundEnabled', true]);
      log.push('GameConfig.SoundEnabled ditambahkan (default TRUE).');
    } else {
      log.push('GameConfig.SoundEnabled sudah ada, dilewati.');
    }
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var msg = log.join('\n');
  Logger.log(msg);
  try {
    SpreadsheetApp.getUi().alert(msg);
  } catch (e) {
    // getUi() tidak tersedia kalau dijalankan bukan dari UI Sheets - abaikan.
  }
}

/**
 * Seed harga awal Market berdasarkan MARKET_SEED_PRICES
 * (lihat CommodityData.gs). Hanya jalan kalau Market masih kosong,
 * supaya aman dijalankan ulang tanpa menimpa harga yang sudah bergerak.
 */
function seedMarket() {
  requireOwner_();
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Market');
  if (sheet.getLastRow() > 1) return;

  var rows = [];
  var now = new Date();

  Object.keys(MARKET_SEED_PRICES).forEach(function (cityId) {
    var commodities = MARKET_SEED_PRICES[cityId];
    Object.keys(commodities).forEach(function (commodityId) {
      var price = commodities[commodityId];
      rows.push([cityId, commodityId, price, price, now]);
    });
  });

  sheet.getRange(2, 1, rows.length, rows[0].length).setValues(rows);
}

/**
 * Seed katalog awal buku (BookCatalog) untuk Fase 2 - Books & Knowledge.
 * Hanya jalan kalau sheet masih kosong (selain header), supaya aman
 * dijalankan ulang tanpa menimpa buku yang sudah ditambah/diedit admin.
 *
 * Format kolom:
 *   - Source: CityId tempat buku dijual, atau 'any' kalau dijual di
 *     semua kota (pedagang buku keliling).
 *   - StatEffects: JSON stat -> kenaikan permanen saat dibeli, contoh
 *     {"Trading":5,"Negotiation":3}.
 *   - SpecialEffect: keyword efek tersembunyi (lihat BookService.gs),
 *     kosongkan kalau buku murni kenaikan stat.
 *
 * Admin bebas menambah/mengedit/menghapus baris ini langsung di sheet
 * kapan saja setelah seed awal - tidak perlu ubah kode sama sekali.
 */
function seedBookCatalog() {
  requireOwner_();
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('BookCatalog');
  if (!sheet || sheet.getLastRow() > 1) return;

  var rows = [
    ['bk_trading_1', 'Basic Bookkeeping', 'I', '{"Trading":5}', '', 300, 'sunda_empire'],
    ['bk_negotiation_1', 'Street Haggling', 'I', '{"Negotiation":5}', '', 300, 'sunda_empire'],
    ['bk_navigation_1', 'Coastal Charts', 'I', '{"Navigation":5}', '', 300, 'joungjava'],
    ['bk_sailing_1', 'Knot & Rigging', 'I', '{"Sailing":5}', '', 300, 'joungjava'],
    ['bk_combat_1', "Brawler's Primer", 'I', '{"Combat":5}', '', 350, 'bjorneo'],
    ['bk_luck_1', "Sailor's Superstitions", 'I', '{"Luck":5}', '', 400, 'any'],
    ['bk_knowledge_1', 'Common Almanac', 'I', '{"Knowledge":8}', '', 250, 'any'],
    ['bk_trading_2', "The Merchant's Codex", 'II', '{"Trading":10,"Negotiation":3}', '', 900, 'sunda_empire'],
    ['bk_navigation_2', 'Deep Sea Charts', 'II', '{"Navigation":10,"Sailing":3}', '', 900, 'joungjava'],
    ['bk_combat_2', 'Blade & Broadside', 'II', '{"Combat":10,"Luck":2}', '', 950, 'bjorneo'],
    ['bk_negotiation_2', "Diplomat's Handbook", 'II', '{"Negotiation":10,"Knowledge":3}', '', 900, 'sunda_empire'],
    ['bk_black_market', "Smuggler's Codebook", 'III', '{"Negotiation":5}', 'black_market_discount', 1800, 'bjorneo'],
    ['bk_deep_hold', "Shipwright's Secrets", 'III', '{"Sailing":5}', 'cargo_bonus_10', 1600, 'joungjava'],
    ['bk_sea_lore', 'Chronicle of the Drowned Kings', 'III', '{"Knowledge":15,"Luck":5}', '', 2000, 'any']
  ];

  sheet.getRange(2, 1, rows.length, rows[0].length).setValues(rows);
}

/**
 * Fase 2 (Books & Knowledge) - jalankan SEKALI dari editor Apps Script
 * kalau project ini sudah pernah menjalankan setupAllSheets() sebelumnya
 * (jadi sheet BookCatalog sudah ada tapi masih kosong karena Fase 2 belum
 * dikerjakan waktu itu). Aman dijalankan berkali-kali (idempotent) - hanya
 * seed kalau BookCatalog masih kosong.
 */
function migrateFase2Setup() {
  requireOwner_();
  seedBookCatalog();
  var msg = 'Fase 2 setup selesai: BookCatalog di-seed (kalau sebelumnya kosong). ' +
    'Cek sheet BookCatalog untuk lihat/edit daftar bukunya.';
  Logger.log(msg);
  try {
    SpreadsheetApp.getUi().alert(msg);
  } catch (e) {
    // getUi() tidak tersedia kalau dijalankan bukan dari UI Sheets - abaikan.
  }
}

/**
 * Migrasi untuk fitur "Set Sail" (peta dunia + durasi pelayaran):
 *   1. Cities.MapX / Cities.MapY - koordinat posisi kota di peta (0-100,
 *      persentase lebar/tinggi SVG). Diisi default untuk 3 kota awal
 *      kalau masih kosong; admin bebas geser lewat sheet kapan saja.
 *   2. PlayerLocation.DestinationCityId / DepartAt / ArriveAt - state
 *      pelayaran yang sedang berlangsung (kosong = tidak sedang berlayar).
 *   3. GameConfig: TravelMinutesPerDistanceUnit, MinTravelMinutes,
 *      BaselineShipSpeed - dipakai LocationService.gs menghitung berapa
 *      lama pelayaran, bisa di-tuning admin tanpa ubah kode.
 *
 * Aman dijalankan berkali-kali (idempotent), tidak menimpa data yang
 * sudah ada. Jalankan SEKALI dari editor Apps Script kalau project ini
 * sudah pernah setupAllSheets() sebelum fitur ini ada.
 */
function migrateSetSail() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  // 1. Cities.MapX / MapY
  var citiesSheet = ss.getSheetByName('Cities');
  if (citiesSheet) {
    var headers = citiesSheet.getRange(1, 1, 1, Math.max(citiesSheet.getLastColumn(), 1)).getValues()[0];
    var addedCols = [];
    ['MapX', 'MapY'].forEach(function (colName) {
      var currentHeaders = citiesSheet.getRange(1, 1, 1, Math.max(citiesSheet.getLastColumn(), 1)).getValues()[0];
      if (currentHeaders.indexOf(colName) === -1) {
        var col = citiesSheet.getLastColumn() + 1;
        citiesSheet.getRange(1, col).setValue(colName).setFontWeight('bold');
        addedCols.push(colName + ' (kolom ' + col + ')');
      }
    });
    log.push(addedCols.length
      ? 'Cities: kolom ' + addedCols.join(', ') + ' ditambahkan.'
      : 'Cities.MapX/MapY sudah ada, dilewati.');

    // Seed koordinat default untuk 3 kota awal kalau masih kosong.
    var data = citiesSheet.getDataRange().getValues();
    var hdr = citiesSheet.getRange(1, 1, 1, citiesSheet.getLastColumn()).getValues()[0];
    var mapXCol = hdr.indexOf('MapX');
    var mapYCol = hdr.indexOf('MapY');
    var defaults = { sunda_empire: [25, 55], joungjava: [60, 30], bjorneo: [75, 75] };

    if (mapXCol >= 0 && mapYCol >= 0) {
      for (var i = 1; i < data.length; i++) {
        var cityId = data[i][0];
        var curX = data[i][mapXCol];
        if (defaults[cityId] && (curX === '' || curX === undefined || curX === null)) {
          citiesSheet.getRange(i + 1, mapXCol + 1).setValue(defaults[cityId][0]);
          citiesSheet.getRange(i + 1, mapYCol + 1).setValue(defaults[cityId][1]);
        }
      }
      log.push('Koordinat default diisi untuk kota yang dikenal (kalau masih kosong).');
    }
  } else {
    log.push('Sheet Cities tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  // 2. PlayerLocation - kolom voyage
  var locSheet = ss.getSheetByName('PlayerLocation');
  if (locSheet) {
    var newCols = ['DestinationCityId', 'DepartAt', 'ArriveAt'];
    newCols.forEach(function (colName) {
      var currentHeaders = locSheet.getRange(1, 1, 1, Math.max(locSheet.getLastColumn(), 1)).getValues()[0];
      if (currentHeaders.indexOf(colName) === -1) {
        var col = locSheet.getLastColumn() + 1;
        locSheet.getRange(1, col).setValue(colName).setFontWeight('bold');
      }
    });
    log.push('PlayerLocation: kolom DestinationCityId/DepartAt/ArriveAt dipastikan ada.');
  } else {
    log.push('Sheet PlayerLocation tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  // 3. GameConfig - konstanta tuning waktu pelayaran
  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var cdata = configSheet.getDataRange().getValues();
    var keys = { TravelMinutesPerDistanceUnit: '0.25', MinTravelMinutes: '5', BaselineShipSpeed: '50' };
    Object.keys(keys).forEach(function (key) {
      var exists = cdata.some(function (r) { return r[0] === key; });
      if (!exists) {
        configSheet.appendRow([key, keys[key]]);
        log.push('GameConfig.' + key + ' ditambahkan (default ' + keys[key] + ').');
      } else {
        log.push('GameConfig.' + key + ' sudah ada, dilewati.');
      }
    });
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var msg = log.join('\n');
  Logger.log(msg);
  try {
    SpreadsheetApp.getUi().alert(msg);
  } catch (e) {
    // getUi() tidak tersedia kalau dijalankan bukan dari UI Sheets - abaikan.
  }
}

/**
 * Migrasi untuk update "Tradewinds 2 Improvements" (Bank/Moneylender,
 * Warehouse, Governor's Missive) - lihat TRADEWINDS2_RESEARCH.md &
 * PATCH_NOTES terkait. Aman dijalankan berkali-kali (idempotent), tidak
 * menimpa data yang sudah ada. Jalankan SEKALI dari editor Apps Script
 * kalau project sudah pernah setupAllSheets() sebelum update ini.
 */
function migrateTW2Improvements() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  // 1. Players: kolom Bank & Moneylender
  var playersSheet = ss.getSheetByName('Players');
  if (playersSheet) {
    var newPlayerCols = ['BankBalance', 'BankLastInterestGameDay', 'DebtBalance', 'DebtLastInterestGameDay'];
    var added = [];
    newPlayerCols.forEach(function (colName) {
      var currentHeaders = playersSheet.getRange(1, 1, 1, Math.max(playersSheet.getLastColumn(), 1)).getValues()[0];
      if (currentHeaders.indexOf(colName) === -1) {
        var col = playersSheet.getLastColumn() + 1;
        playersSheet.getRange(1, col).setValue(colName).setFontWeight('bold');
        added.push(colName);
      }
    });
    log.push(added.length ? 'Players: kolom ' + added.join(', ') + ' ditambahkan.' : 'Players: kolom Bank/Moneylender sudah ada.');
  } else {
    log.push('Sheet Players tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  // 2. PlayerMissions: kolom detail Governor's Missive
  var pmSheet = ss.getSheetByName('PlayerMissions');
  if (pmSheet) {
    var newPmCols = ['CityId', 'CommodityId', 'Qty', 'DeliverToCityId', 'Reward'];
    var addedPm = [];
    newPmCols.forEach(function (colName) {
      var currentHeaders = pmSheet.getRange(1, 1, 1, Math.max(pmSheet.getLastColumn(), 1)).getValues()[0];
      if (currentHeaders.indexOf(colName) === -1) {
        var col = pmSheet.getLastColumn() + 1;
        pmSheet.getRange(1, col).setValue(colName).setFontWeight('bold');
        addedPm.push(colName);
      }
    });
    log.push(addedPm.length ? 'PlayerMissions: kolom ' + addedPm.join(', ') + ' ditambahkan.' : 'PlayerMissions: kolom misi sudah ada.');
  } else {
    log.push('Sheet PlayerMissions tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  // 3. Sheet Warehouse (baru)
  if (!ss.getSheetByName('Warehouse')) {
    var whSheet = ss.insertSheet('Warehouse');
    whSheet.getRange(1, 1, 1, 4).setValues([['PlayerId', 'CityId', 'CommodityId', 'Qty']]);
    whSheet.getRange(1, 1, 1, 4).setFontWeight('bold');
    log.push('Sheet Warehouse dibuat.');
  } else {
    log.push('Sheet Warehouse sudah ada.');
  }

  // 4. GameConfig: konstanta Bank/Moneylender/Warehouse
  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var cdata = configSheet.getDataRange().getValues();
    var keys = {
      BankInterestRatePercent: '0.5',
      DebtInterestRatePercent: '2',
      MaxDebtAmount: '5000',
      WarehouseFeePerUnit: '2'
    };
    Object.keys(keys).forEach(function (key) {
      var exists = cdata.some(function (r) { return r[0] === key; });
      if (!exists) {
        configSheet.appendRow([key, keys[key]]);
        log.push('GameConfig.' + key + ' ditambahkan (default ' + keys[key] + ').');
      } else {
        log.push('GameConfig.' + key + ' sudah ada, dilewati.');
      }
    });
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var msg = log.join('\n');
  Logger.log(msg);
  try {
    SpreadsheetApp.getUi().alert(msg);
  } catch (e) {
    // getUi() tidak tersedia kalau dijalankan bukan dari UI Sheets - abaikan.
  }
}

/**
 * Migrasi Fase 3a (Ship Upgrades) - lihat ShipUpgradeService.gs &
 * FILES_SUMMARY.txt. Aman dijalankan berkali-kali (idempotent).
 *   - Players: +ShipUpgrades (JSON string, default '{}')
 *   - Ship: +ConditionDecayPerSail, +MaxCondition, +DamageThreshold
 *     (nilai default diisi HANYA untuk baris yang masih kosong -
 *     kapal yang sudah ada tidak ditimpa kalau admin sudah mengisi
 *     manual sebelumnya)
 */
function migrateFase3aSetup() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  var playersSheet = ss.getSheetByName('Players');
  if (playersSheet) {
    var pHeaders = playersSheet.getRange(1, 1, 1, Math.max(playersSheet.getLastColumn(), 1)).getValues()[0];
    if (pHeaders.indexOf('ShipUpgrades') === -1) {
      var col = playersSheet.getLastColumn() + 1;
      playersSheet.getRange(1, col).setValue('ShipUpgrades').setFontWeight('bold');
      log.push('Players: kolom ShipUpgrades ditambahkan.');
    } else {
      log.push('Players: kolom ShipUpgrades sudah ada.');
    }
  } else {
    log.push('Sheet Players tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var shipSheet = ss.getSheetByName('Ship');
  if (shipSheet) {
    var sHeaders = shipSheet.getRange(1, 1, 1, Math.max(shipSheet.getLastColumn(), 1)).getValues()[0];
    var newShipCols = { ConditionDecayPerSail: 0.03, MaxCondition: 100, DamageThreshold: 45 };
    var added = [];

    Object.keys(newShipCols).forEach(function (colName) {
      var headers = shipSheet.getRange(1, 1, 1, Math.max(shipSheet.getLastColumn(), 1)).getValues()[0];
      if (headers.indexOf(colName) === -1) {
        var col = shipSheet.getLastColumn() + 1;
        shipSheet.getRange(1, col).setValue(colName).setFontWeight('bold');
        added.push(colName);

        var data = shipSheet.getDataRange().getValues();
        for (var i = 1; i < data.length; i++) {
          shipSheet.getRange(i + 1, col).setValue(newShipCols[colName]);
        }
      }
    });
    log.push(added.length ? 'Ship: kolom ' + added.join(', ') + ' ditambahkan (+ default diisi).' : 'Ship: kolom Condition decay/max/threshold sudah ada.');
  } else {
    log.push('Sheet Ship tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}

/**
 * Migrasi Fase 3b (Combat / Pirate Encounters) - lihat CombatService.gs.
 * Aman dijalankan berkali-kali.
 *   - PlayerLocation: +PendingEncounter (JSON string kosong = tidak ada encounter)
 *   - GameConfig: konstanta tuning peluang & hasil combat
 */
function migrateFase3bCombat() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  var locSheet = ss.getSheetByName('PlayerLocation');
  if (locSheet) {
    var headers = locSheet.getRange(1, 1, 1, Math.max(locSheet.getLastColumn(), 1)).getValues()[0];
    if (headers.indexOf('PendingEncounter') === -1) {
      var col = locSheet.getLastColumn() + 1;
      locSheet.getRange(1, col).setValue('PendingEncounter').setFontWeight('bold');
      log.push('PlayerLocation: kolom PendingEncounter ditambahkan.');
    } else {
      log.push('PlayerLocation: kolom PendingEncounter sudah ada.');
    }
  } else {
    log.push('Sheet PlayerLocation tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var cdata = configSheet.getDataRange().getValues();
    var keys = {
      PirateEncounterBaseChance: '12',
      PirateEncounterConditionPenalty: '15',
      PirateEncounterLevelMax: '5',
      CombatLootGoldPerLevel: '200',
      CombatBribeGoldPerLevel: '150',
      ShipRepairBaseCostPerPoint: '15'
    };
    Object.keys(keys).forEach(function (key) {
      var exists = cdata.some(function (r) { return r[0] === key; });
      if (!exists) {
        configSheet.appendRow([key, keys[key]]);
        log.push('GameConfig.' + key + ' ditambahkan (default ' + keys[key] + ').');
      } else {
        log.push('GameConfig.' + key + ' sudah ada, dilewati.');
      }
    });
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}

/**
 * Migrasi Fase 4 (Missions & Reputation) - lihat MissionService.gs.
 * TIDAK perlu kolom sheet baru (Players.Reputation & PlayerMissions
 * sudah lengkap sejak update TW2 Improvements) - cuma menambah
 * konstanta GameConfig untuk efek reputasi ke harga market.
 */
function migrateFase4Missions() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var cdata = configSheet.getDataRange().getValues();
    var keys = {
      ReputationMarketBonusPerPoint: '0.05',
      ReputationMarketBonusCap: '10'
    };
    Object.keys(keys).forEach(function (key) {
      var exists = cdata.some(function (r) { return r[0] === key; });
      if (!exists) {
        configSheet.appendRow([key, keys[key]]);
        log.push('GameConfig.' + key + ' ditambahkan (default ' + keys[key] + ').');
      } else {
        log.push('GameConfig.' + key + ' sudah ada, dilewati.');
      }
    });
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}

/**
 * Migrasi 3 kota baru: Skitraw, TooGood, IKN - lihat CommodityData.gs
 * (MARKET_SEED_PRICES) untuk penjelasan karakter tiap kota. Aman
 * dijalankan berkali-kali (idempotent) - kota/baris Market yang sudah
 * ada TIDAK ditimpa.
 *
 * Setelah migrasi ini, admin bisa isi Cities.ImageUrl untuk 3 kota baru
 * ini persis seperti kota lain (paste link Google Drive, share "Anyone
 * with the link" dulu).
 */
function migrateAddCitiesRound2() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  var citiesSheet = ss.getSheetByName('Cities');
  if (!citiesSheet) {
    Logger.log('Sheet Cities tidak ditemukan - jalankan setupAllSheets() dulu.');
    return;
  }

  var citiesData = citiesSheet.getDataRange().getValues();
  var existingCityIds = citiesData.slice(1).map(function (r) { return r[0]; });

  // CityId, Name, Type, RepairCostRate, MayorMissionPool, ImageUrl, MapX, MapY
  var newCities = [
    ['skitraw', 'Skitraw', 'Capital',       0.9, '', '', 45, 15],
    ['toogood', 'TooGood', 'Outlaw',        1.3, '', '', 15, 80],
    ['ikn',     'IKN',     'FallenCapital', 1.4, '', '', 50, 62]
  ];

  var citiesToAdd = newCities.filter(function (c) { return existingCityIds.indexOf(c[0]) === -1; });
  if (citiesToAdd.length) {
    citiesSheet.getRange(citiesSheet.getLastRow() + 1, 1, citiesToAdd.length, citiesToAdd[0].length).setValues(citiesToAdd);
    log.push('Cities: ditambahkan ' + citiesToAdd.map(function (c) { return c[1]; }).join(', ') + '.');
  } else {
    log.push('Cities: Skitraw/TooGood/IKN sudah ada semua, dilewati.');
  }
  WorldService.invalidateCache();

  var marketSheet = ss.getSheetByName('Market');
  if (marketSheet) {
    var marketData = marketSheet.getDataRange().getValues();
    var existingPairs = {};
    marketData.slice(1).forEach(function (r) { existingPairs[r[0] + '|' + r[1]] = true; });

    var now = new Date();
    var rowsToAdd = [];
    ['skitraw', 'toogood', 'ikn'].forEach(function (cityId) {
      var commodities = MARKET_SEED_PRICES[cityId] || {};
      Object.keys(commodities).forEach(function (commodityId) {
        var key = cityId + '|' + commodityId;
        if (!existingPairs[key]) {
          var price = commodities[commodityId];
          rowsToAdd.push([cityId, commodityId, price, price, now]);
        }
      });
    });

    if (rowsToAdd.length) {
      marketSheet.getRange(marketSheet.getLastRow() + 1, 1, rowsToAdd.length, rowsToAdd[0].length).setValues(rowsToAdd);
      log.push('Market: ditambahkan ' + rowsToAdd.length + ' baris harga untuk kota baru.');
    } else {
      log.push('Market: baris untuk kota baru sudah lengkap, dilewati.');
    }
  } else {
    log.push('Sheet Market tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  log.push('Selesai. Isi Cities.ImageUrl untuk Skitraw/TooGood/IKN kalau mau pasang foto latar kota.');

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}

/**
 * Migrasi konfigurasi screen judul (Title Screen: Play/Settings/About) -
 * lihat TitleScreen.html & api_getTitleScreenConfig() di Code.gs. Aman
 * dijalankan berkali-kali.
 */
function migrateTitleScreen() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var data = configSheet.getDataRange().getValues();
    var hasKey = data.some(function (r) { return r[0] === 'TitleScreenImageUrl'; });
    if (!hasKey) {
      configSheet.appendRow(['TitleScreenImageUrl', '']);
      log.push('GameConfig.TitleScreenImageUrl ditambahkan (kosong - isi link Google Drive foto judul di sini).');
    } else {
      log.push('GameConfig.TitleScreenImageUrl sudah ada, dilewati.');
    }
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}

/**
 * Migrasi Fase 3b lanjutan: kolom ammo meriam (Cannon reload mechanic) -
 * lihat ShipUpgradeService.gs & CombatService.gs untuk detail. Aman
 * dijalankan berkali-kali.
 */
function migrateCannonAmmo() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var data = configSheet.getDataRange().getValues();
    var keys = {
      CombatBaseAmmo: '3',
      CombatEnemyBaseHp: '40',
      CombatEnemyHpPerLevel: '25'
    };
    Object.keys(keys).forEach(function (key) {
      var exists = data.some(function (r) { return r[0] === key; });
      if (!exists) {
        configSheet.appendRow([key, keys[key]]);
        log.push('GameConfig.' + key + ' ditambahkan (default ' + keys[key] + ').');
      } else {
        log.push('GameConfig.' + key + ' sudah ada, dilewati.');
      }
    });
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}

/**
 * Fase 5 — Exploration & Treasure. TIDAK ada sheet baru sama sekali -
 * ItemCatalog/PlayerInventory/ShipEquipment sudah ada sejak Fase 0
 * (belum pernah dipakai). Migrasi ini murni SEED DATA additive:
 *   1. ItemCatalog: 6 treasure map (satu per situs, lihat
 *      TreasureData.gs) + 3 artifact.
 *   2. BookCatalog: +2 buku "decoder" baru (Hidden Knowledge Pairing) -
 *      SpecialEffect 'treasure_decoder_1' (situs difficulty 1-2) dan
 *      'treasure_decoder_2' (situs difficulty 3/elite, dijual di TooGood).
 *   3. GameConfig: +2 key tuning (TreasureMapDropChance,
 *      TreasureDigBaseGold, dipakai TreasureService.gs/CombatService.gs).
 * Aman dijalankan berkali-kali (idempotent) - baris/ID yang sudah ada
 * TIDAK ditimpa, admin bebas edit manual setelahnya.
 */
function migrateFase5Exploration() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  // --- 1. ItemCatalog ---
  var itemSheet = ss.getSheetByName('ItemCatalog');
  if (itemSheet) {
    var itemData = itemSheet.getDataRange().getValues();
    var existingItemIds = itemData.slice(1).map(function (r) { return r[0]; });

    // ItemId, Name, Type, Effects, Value
    var newItems = [
      ['tm_sunda_reef', 'Peta Karang Terlantar', 'treasure_map', '{"siteId":"site_sunda_reef","requiresBookKeyword":"treasure_decoder_1"}', 80],
      ['tm_joungjava_grove', 'Peta Rimba Sunyi', 'treasure_map', '{"siteId":"site_joungjava_grove","requiresBookKeyword":"treasure_decoder_1"}', 80],
      ['tm_skitraw_docks', 'Peta Dermaga Tua', 'treasure_map', '{"siteId":"site_skitraw_docks","requiresBookKeyword":"treasure_decoder_1"}', 120],
      ['tm_bjorneo_cliffs', 'Peta Tebing Berkabut', 'treasure_map', '{"siteId":"site_bjorneo_cliffs","requiresBookKeyword":"treasure_decoder_1"}', 120],
      ['tm_toogood_den', 'Peta Sarang Lama', 'treasure_map', '{"siteId":"site_toogood_den","requiresBookKeyword":"treasure_decoder_2"}', 220],
      ['tm_ikn_ruins', 'Peta Reruntuhan Istana', 'treasure_map', '{"siteId":"site_ikn_ruins","requiresBookKeyword":"treasure_decoder_2"}', 220],
      ['art_current_charts', 'Peta Arus Purba', 'artifact', '{"SpecialEffect":"cargo_bonus_10"}', 1200],
      ['art_smugglers_ring', "Cincin Penyelundup", 'artifact', '{"SpecialEffect":"black_market_discount"}', 1500],
      ['art_sunken_crown', 'Mahkota Karam', 'artifact', '{}', 3000]
    ];

    var itemsToAdd = newItems.filter(function (it) { return existingItemIds.indexOf(it[0]) === -1; });
    if (itemsToAdd.length) {
      itemSheet.getRange(itemSheet.getLastRow() + 1, 1, itemsToAdd.length, itemsToAdd[0].length).setValues(itemsToAdd);
      log.push('ItemCatalog: ditambahkan ' + itemsToAdd.length + ' item baru (treasure map + artifact).');
    } else {
      log.push('ItemCatalog: semua item Fase 5 sudah ada, dilewati.');
    }
    try { ItemService.invalidateCatalogCache(); } catch (e) { /* belum ada instance - abaikan */ }
  } else {
    log.push('Sheet ItemCatalog tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  // --- 2. BookCatalog (Hidden Knowledge Pairing) ---
  var bookSheet = ss.getSheetByName('BookCatalog');
  if (bookSheet) {
    var bookData = bookSheet.getDataRange().getValues();
    var existingBookIds = bookData.slice(1).map(function (r) { return r[0]; });

    var newBooks = [
      ['bk_treasure_decoder_1', 'Kompendium Pemburu Harta', 'II', '{"Knowledge":5}', 'treasure_decoder_1', 1100, 'any'],
      ['bk_treasure_decoder_2', 'Kitab Terlarang Sang Perompak', 'III', '{"Knowledge":8,"Luck":3}', 'treasure_decoder_2', 2400, 'toogood']
    ];

    var booksToAdd = newBooks.filter(function (b) { return existingBookIds.indexOf(b[0]) === -1; });
    if (booksToAdd.length) {
      bookSheet.getRange(bookSheet.getLastRow() + 1, 1, booksToAdd.length, booksToAdd[0].length).setValues(booksToAdd);
      log.push('BookCatalog: ditambahkan ' + booksToAdd.length + ' buku decoder baru.');
    } else {
      log.push('BookCatalog: buku decoder Fase 5 sudah ada, dilewati.');
    }
    try { BookService.invalidateCatalogCache(); } catch (e) { /* belum ada instance - abaikan */ }
  } else {
    log.push('Sheet BookCatalog tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  // --- 3. GameConfig ---
  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var configData = configSheet.getDataRange().getValues();
    var keys = {
      TreasureMapDropChance: '15',
      TreasureDigBaseGold: '350'
    };
    Object.keys(keys).forEach(function (key) {
      var exists = configData.some(function (r) { return r[0] === key; });
      if (!exists) {
        configSheet.appendRow([key, keys[key]]);
        log.push('GameConfig.' + key + ' ditambahkan (default ' + keys[key] + ').');
      } else {
        log.push('GameConfig.' + key + ' sudah ada, dilewati.');
      }
    });
    invalidateGameConfigCache_();
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  log.push('Selesai. Cek panel Items (baru) di client, dan buku decoder di Library.');

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}

/**
 * Migrasi kecil: siapkan GameConfig.SailingBackgroundImageUrl (link
 * Google Drive buat foto latar laut selagi kapal berlayar - lihat
 * api_getSailingBackgroundUrl() di Code.gs & renderAtSeaScene() di
 * JavaScript.html). Aman dijalankan berkali-kali.
 */
function migrateSailingBackground() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var data = configSheet.getDataRange().getValues();
    var hasKey = data.some(function (r) { return r[0] === 'SailingBackgroundImageUrl'; });
    if (!hasKey) {
      configSheet.appendRow(['SailingBackgroundImageUrl', '']);
      log.push('GameConfig.SailingBackgroundImageUrl ditambahkan (kosong - isi link Google Drive foto laut di sini).');
    } else {
      log.push('GameConfig.SailingBackgroundImageUrl sudah ada, dilewati.');
    }
    invalidateGameConfigCache_();
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}

/**
 * Follow-up Fase 5: (1) toko treasure map per kota, (2) slot equipment
 * KEDUA. Tidak ada sheet baru:
 *   - ShipEquipment sudah generic (PlayerId/SlotType/ItemId) - slot
 *     kedua ('artifact_2') otomatis jalan begitu ItemService.gs versi
 *     baru di-deploy, TANPA migrasi apapun untuk itu.
 *   - ItemCatalog dapat 2 kolom baru: Price & Source (pola sama seperti
 *     BookCatalog) - kolom LAMA (ItemId/Name/Type/Effects/Value) tidak
 *     diubah, cuma ditambah di akhir. Item yang Price-nya kosong TETAP
 *     loot-only seperti sebelumnya (lihat ItemService.getTreasureMapShop()).
 * Aman dijalankan berkali-kali (idempotent).
 */
function migrateFase5TreasureShop() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  var itemSheet = ss.getSheetByName('ItemCatalog');
  if (!itemSheet) {
    Logger.log('Sheet ItemCatalog tidak ditemukan - jalankan setupAllSheets() dulu.');
    return;
  }

  var data = itemSheet.getDataRange().getValues();
  var headers = data[0];
  var priceCol = headers.indexOf('Price');
  var sourceCol = headers.indexOf('Source');

  if (priceCol === -1) {
    itemSheet.getRange(1, headers.length + 1).setValue('Price');
    priceCol = headers.length;
    headers.push('Price');
    log.push('ItemCatalog: kolom Price ditambahkan.');
  }
  if (sourceCol === -1) {
    itemSheet.getRange(1, headers.length + 1).setValue('Source');
    sourceCol = headers.length;
    headers.push('Source');
    log.push('ItemCatalog: kolom Source ditambahkan.');
  }
  if (priceCol !== -1 && sourceCol !== -1 && log.length === 0) {
    log.push('ItemCatalog: kolom Price/Source sudah ada, dilewati.');
  }

  // Peta dijual di kota LAIN dari lokasi situsnya (bukan kota digalinya
  // sendiri) - insentif "beli di sini, berlayar ke sana buat gali",
  // sesuai semangat Exploration. Harga dinaikkan dari harga jual loot
  // (Value) supaya membeli tetap terasa "membayar kepastian", bukan
  // jalan pintas yang lebih murah dari sekadar berharap dapat loot.
  var shopEntries = {
    tm_sunda_reef: { price: 250, source: 'joungjava' },
    tm_joungjava_grove: { price: 250, source: 'skitraw' },
    tm_skitraw_docks: { price: 450, source: 'bjorneo' },
    tm_bjorneo_cliffs: { price: 450, source: 'toogood' },
    tm_toogood_den: { price: 800, source: 'ikn' },
    tm_ikn_ruins: { price: 800, source: 'sunda_empire' }
  };

  data = itemSheet.getDataRange().getValues(); // re-read, kolom baru mungkin baru ditambah
  var idCol = headers.indexOf('ItemId');
  var updated = 0;
  for (var i = 1; i < data.length; i++) {
    var itemId = data[i][idCol];
    var entry = shopEntries[itemId];
    if (!entry) continue;
    var currentPrice = data[i][priceCol];
    if (currentPrice) continue; // sudah diisi manual - jangan ditimpa
    itemSheet.getRange(i + 1, priceCol + 1).setValue(entry.price);
    itemSheet.getRange(i + 1, sourceCol + 1).setValue(entry.source);
    updated++;
  }
  log.push(updated + ' treasure map diisi Price/Source (toko).');

  try { ItemService.invalidateCatalogCache(); } catch (e) { /* belum ada instance - abaikan */ }

  log.push('Slot equipment kedua ("artifact_2") aktif otomatis - tidak perlu migrasi tambahan untuk itu.');

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}

/**
 * Fase 6 — World Expansion & Events (ronde pertama: sistem Events).
 * Sheet baru `CityEvents` (CityId, EventType, Label, Message,
 * PriceMultiplierPercent, RewardMultiplierPercent, ExpiresGameDay) -
 * dibaca WorldEventService.gs, dipicu otomatis dari
 * LocationService.completeArrival_() (peluang kecil tiap voyage
 * damai/selesai combat). Aman dijalankan berkali-kali (idempotent).
 */
function migrateFase6WorldEvents() {
  requireOwner_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = [];

  if (!ss.getSheetByName('CityEvents')) {
    var sheet = ss.insertSheet('CityEvents');
    sheet.getRange(1, 1, 1, 7).setValues([[
      'CityId', 'EventType', 'Label', 'Message',
      'PriceMultiplierPercent', 'RewardMultiplierPercent', 'ExpiresGameDay'
    ]]);
    sheet.getRange(1, 1, 1, 7).setFontWeight('bold');
    log.push('Sheet CityEvents dibuat.');
  } else {
    log.push('Sheet CityEvents sudah ada.');
  }

  var configSheet = ss.getSheetByName('GameConfig');
  if (configSheet) {
    var data = configSheet.getDataRange().getValues();
    var keys = {
      WorldEventRollChancePercent: '10',
      WorldEventMinDurationDays: '2',
      WorldEventMaxDurationDays: '5'
    };
    Object.keys(keys).forEach(function (key) {
      var exists = data.some(function (r) { return r[0] === key; });
      if (!exists) {
        configSheet.appendRow([key, keys[key]]);
        log.push('GameConfig.' + key + ' ditambahkan (default ' + keys[key] + ').');
      } else {
        log.push('GameConfig.' + key + ' sudah ada, dilewati.');
      }
    });
    invalidateGameConfigCache_();
  } else {
    log.push('Sheet GameConfig tidak ditemukan - jalankan setupAllSheets() dulu.');
  }

  log.push('Selesai. World Event akan mulai muncul otomatis (peluang ' +
    '10% per kedatangan) begitu ada pemain yang merapat ke kota manapun.');

  var msg = log.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { /* bukan dari UI Sheets - abaikan */ }
}


/**
 * Tide v6: web app sekarang "Execute as: Me", jadi SIAPA PUN yang membuka game
 * bisa memanggil fungsi global lewat google.script.run. Fungsi admin/setup
 * dikunci: hanya jalan kalau dijalankan oleh pemilik script (dari editor,
 * atau pemilik yang membuka web app-nya sendiri).
 */
function requireOwner_() {
  var active = '', owner = '';
  try { active = String(Session.getActiveUser().getEmail() || '').toLowerCase(); } catch (e) {}
  try { owner = String(Session.getEffectiveUser().getEmail() || '').toLowerCase(); } catch (e) {}
  if (!active || !owner || active !== owner) throw new Error('Khusus pemilik game - jalankan dari editor Apps Script.');
}
