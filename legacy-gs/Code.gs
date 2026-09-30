/**
 * Code.gs
 * ------------------------------------------------------------------
 * Entry point Web App. MASIH testing lokal via "Test deployments" -
 * JANGAN membuat "New deployment" publik/share ke teman dulu.
 * ------------------------------------------------------------------
 */

function doGet(e) {
  SheetCache.reset();
  try {
    // Developer Mode - halaman diagnostik terpisah, diakses via ?dev=1 di
    // akhir URL /exec. Tidak mengganggu alur game normal sama sekali.
    if (e && e.parameter && (e.parameter.dev === '1' || e.parameter.mode === 'debug')) {
      return HtmlService.createHtmlOutputFromFile('DevTools')
        .setTitle("Marantau - Developer Mode")
        .addMetaTag('viewport', 'width=device-width, initial-scale=1')
        .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
    }

    // Tide v6: SATU halaman untuk semua (login akun, buat karakter, game).
    // Identitas pemain ditentukan token di client, bukan akun Google -
    // jadi web app bisa di-deploy "Execute as: Me" + akses "Anyone".
    var template = HtmlService.createTemplateFromFile('Index');

    return template.evaluate()
      .setTitle("Marantau")
      .addMetaTag('viewport', 'width=device-width, initial-scale=1')
      .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
  } catch (err) {
    // Halaman error yang ramah, bukan stack trace mentah - penting begitu
    // game dibuka teman-teman yang bisa saja belum punya akses/setting yang
    // pas, supaya mereka tahu apa yang salah alih-alih layar putih kosong.
    return renderFatalErrorPage_(err);
  }
}

function renderFatalErrorPage_(err) {
  var template = HtmlService.createTemplate(
    '<html><body style="font-family:Georgia,serif;background:#3b2417;color:#f0e4c4;' +
    'padding:40px;text-align:center;max-width:640px;margin:0 auto;">' +
    '<h1 style="color:#f4d374;">Marantau belum bisa dimuat</h1>' +
    '<p><?= message ?></p>' +
    '</body></html>'
  );
  template.message = err.message;
  return template.evaluate()
    .setTitle("Marantau - Error")
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

/** Helper supaya .html bisa include file .html lain */
function include(filename) {
  return HtmlService.createHtmlOutputFromFile(filename).getContent();
}

/**
 * Trigger bawaan Google Sheets (bukan dipanggil dari client). Begitu admin
 * mengedit sheet Cities (misal paste link foto port baru), cache
 * WorldService langsung di-invalidate supaya perubahan terasa instan buat
 * semua pemain, tidak perlu nunggu TTL 5 menit habis.
 */
function onEdit(e) {
  try {
    if (e && e.range) {
      var sheetName = e.range.getSheet().getName();
      if (sheetName === 'Cities') {
        WorldService.invalidateCache();
      } else if (sheetName === 'BookCatalog') {
        BookService.invalidateCatalogCache();
      } else if (sheetName === 'GameConfig') {
        invalidateGameConfigCache_();
      } else if (sheetName === 'ItemCatalog') {
        ItemService.invalidateCatalogCache();
      }
    }
  } catch (err) {
    // Jangan sampai error di sini mengganggu editing manual di sheet.
  }
}

/**
 * ==== Fungsi yang dipanggil dari client lewat google.script.run ====
 * (prefix api_ = fungsi publik untuk client)
 */

// --- Title Screen (Play/Settings/About) ---

/**
 * Endpoint RINGAN yang bisa dipanggil SEBELUM karakter ada / sebelum
 * state game penuh dimuat - dipakai TitleScreen.html di Index.html
 * MAUPUN CharacterCreate.html. Cuma baca satu key GameConfig, tidak
 * butuh identitas pemain sama sekali.
 */
function api_getTitleScreenConfig() {
  SheetCache.reset();
  var raw = getGameConfigValue_('TitleScreenImageUrl');
  return { imageUrl: raw ? driveUrlToDirectImage_(raw) : '' };
}

/**
 * Foto latar laut yang tampil selagi kapal berlayar (scene "Berlayar...")
 * - link Google Drive, admin isi di GameConfig.SailingBackgroundImageUrl
 * (lihat migrateSailingBackground() di SetupSheets.gs). Kosong = client
 * fallback ke SVG bawaan. Diambil SEKALI di boot (bukan tiap
 * api_getGameState()) - lihat JavaScript.html.
 */
function api_getSailingBackgroundUrl() {
  SheetCache.reset();
  var raw = getGameConfigValue_('SailingBackgroundImageUrl');
  return { imageUrl: raw ? driveUrlToDirectImage_(raw) : '' };
}

// --- Character Creation ---

function api_getArchetypes() {
  SheetCache.reset();
  return ARCHETYPES.map(function (a) {
    return { id: a.id, name: a.name, tagline: a.tagline, bio: a.bio, bonuses: a.bonuses, perkName: a.perkName, perkDesc: a.perkDesc };
  });
}

function api_createCharacter(characterName, archetypeId, appearance) {
  SheetCache.reset();
  // Tide v6: nama kapten harus unik (dipakai di chat, duel, bursa)
  var wanted = String(characterName || '').trim().toLowerCase(), me = PlayerService.getCurrentPlayerId();
  var pdata = SheetCache.getData('Players');
  for (var i = 1; i < pdata.length; i++) {
    if (pdata[i][0] !== me && String(pdata[i][1] || '').trim().toLowerCase() === wanted && wanted) throw new Error('Nama kapten "' + characterName + '" sudah dipakai pemain lain.');
  }
  var res = CharacterService.createCharacter(characterName, archetypeId);
  // Tide v3: simpan wajah kapten (opsional, tidak mengubah sheet apa pun)
  if (appearance) { try { AppearanceStore_.save(PlayerService.getCurrentPlayerId(), appearance); } catch (e) { Logger.log('appearance save gagal: ' + e.message); } }
  return res;
}

// --- Diagnostik ---

/**
 * Fungsi super ringan buat isolasi masalah: kalau ini juga balik `null`
 * di client padahal Executions bilang "Completed", berarti masalahnya
 * BUKAN soal ukuran/isi payload api_getGameState() (yang jauh lebih
 * besar & kompleks) - melainkan masalah umum di jalur transport
 * google.script.run itu sendiri (kemungkinan besar ada extension
 * browser yang mengganggu komunikasi antar-iframe Apps Script).
 */
function api_ping() {
  SheetCache.reset();
  return { ok: true, time: new Date().toISOString(), playerId: PlayerService.getCurrentPlayerId() };
}

/**
 * "Bug Finder" untuk Developer Mode (DevTools.html): cek kesehatan setup
 * secara menyeluruh - sheet ada semua, kolom/migrasi Fase 1 & 2 lengkap,
 * akun Google terdeteksi, sampai coba jalankan api_getGameState() end-to-end.
 * Setiap cek dibungkus try/catch sendiri-sendiri supaya SATU hal yang gagal
 * tidak menghentikan pengecekan lainnya - hasilnya laporan lengkap sekali
 * jalan, bukan cuma "berhenti di error pertama".
 */
function api_devDiagnostics() {
  requireOwner_();
  SheetCache.reset();
  var report = { timestamp: new Date().toISOString(), checks: [] };

  function check(name, fn) {
    var entry = { name: name };
    var start = Date.now();
    try {
      entry.detail = fn();
      entry.status = 'ok';
    } catch (err) {
      entry.status = 'fail';
      entry.detail = err.message;
    }
    entry.ms = Date.now() - start;
    report.checks.push(entry);
  }

  check('Session aktif (akun Google terdeteksi)', function () {
    var email = Session.getActiveUser().getEmail();
    if (!email) throw new Error('Session.getActiveUser() kosong - lihat catatan otorisasi di PATCH_NOTES.');
    return 'Email terdeteksi: ' + email;
  });

  check('Spreadsheet terhubung', function () {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    return ss.getName() + ' (' + ss.getId() + ')';
  });

  var expectedSheets = ['Players', 'CharacterStats', 'PlayerBooks', 'BookCatalog',
    'PlayerInventory', 'ItemCatalog', 'Ship', 'ShipEquipment', 'Cities', 'Market',
    'Missions', 'PlayerMissions', 'CombatLog', 'GameConfig', 'PlayerLocation', 'PlayerLog'];

  expectedSheets.forEach(function (name) {
    check('Sheet "' + name + '"', function () {
      var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(name);
      if (!sheet) throw new Error('Sheet tidak ditemukan - jalankan setupAllSheets().');
      return sheet.getLastRow() + ' baris, ' + sheet.getLastColumn() + ' kolom.';
    });
  });

  check('Cities.ImageUrl (kolom foto port custom)', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Cities');
    var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
    if (headers.indexOf('ImageUrl') === -1) {
      throw new Error('Kolom ImageUrl belum ada - jalankan migrateFase1Improvements().');
    }
    return 'Ada di kolom ' + (headers.indexOf('ImageUrl') + 1);
  });

  check('GameConfig.SoundBgmUrl / SoundEnabled', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('GameConfig');
    var data = sheet.getDataRange().getValues();
    var hasBgm = data.some(function (r) { return r[0] === 'SoundBgmUrl'; });
    var hasEnabled = data.some(function (r) { return r[0] === 'SoundEnabled'; });
    if (!hasBgm || !hasEnabled) throw new Error('Belum lengkap - jalankan migrateFase1Improvements().');
    return 'Lengkap.';
  });

  check('BookCatalog terisi (Fase 2)', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('BookCatalog');
    var rows = sheet.getLastRow() - 1;
    if (rows <= 0) throw new Error('Kosong - jalankan migrateFase2Setup().');
    return rows + ' buku.';
  });

  check('Players: kolom Bank/Moneylender', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Players');
    var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
    var need = ['BankBalance', 'BankLastInterestGameDay', 'DebtBalance', 'DebtLastInterestGameDay'];
    var missing = need.filter(function (c) { return headers.indexOf(c) === -1; });
    if (missing.length) throw new Error('Kolom hilang: ' + missing.join(', ') + ' - jalankan migrateTW2Improvements().');
    return 'Lengkap.';
  });

  check('PlayerMissions: kolom Governor\'s Missive', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('PlayerMissions');
    var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
    var need = ['CityId', 'CommodityId', 'Qty', 'DeliverToCityId', 'Reward'];
    var missing = need.filter(function (c) { return headers.indexOf(c) === -1; });
    if (missing.length) throw new Error('Kolom hilang: ' + missing.join(', ') + ' - jalankan migrateTW2Improvements().');
    return 'Lengkap.';
  });

  check('Players: kolom ShipUpgrades (Fase 3a)', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Players');
    var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
    if (headers.indexOf('ShipUpgrades') === -1) throw new Error('Kolom hilang - jalankan migrateFase3aSetup().');
    return 'Lengkap.';
  });

  check('Ship: kolom Condition/MaxCondition/ConditionDecayPerSail/DamageThreshold (Fase 3a/3c)', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Ship');
    var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
    var need = ['Condition', 'ConditionDecayPerSail', 'MaxCondition', 'DamageThreshold'];
    var missing = need.filter(function (c) { return headers.indexOf(c) === -1; });
    if (missing.length) throw new Error('Kolom hilang: ' + missing.join(', ') + ' - jalankan migrateFase3aSetup().');
    return 'Lengkap.';
  });

  check('PlayerLocation: kolom PendingEncounter (Fase 3b)', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('PlayerLocation');
    var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
    if (headers.indexOf('PendingEncounter') === -1) throw new Error('Kolom hilang - jalankan migrateFase3bCombat().');
    return 'Lengkap.';
  });

  check('GameConfig: konstanta Combat & Mission Board (Fase 3b/4)', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('GameConfig');
    var data = sheet.getDataRange().getValues();
    var need = ['PirateEncounterBaseChance', 'ShipRepairBaseCostPerPoint', 'ReputationMarketBonusPerPoint'];
    var missing = need.filter(function (k) { return !data.some(function (r) { return r[0] === k; }); });
    if (missing.length) throw new Error('Key hilang: ' + missing.join(', ') + ' - jalankan migrateFase3bCombat() & migrateFase4Missions().');
    return 'Lengkap.';
  });

  check('Sheet "Warehouse"', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Warehouse');
    if (!sheet) throw new Error('Sheet tidak ditemukan - jalankan migrateTW2Improvements().');
    return sheet.getLastRow() + ' baris.';
  });

  check('Cities: kolom MapX/MapY (Set Sail)', function () {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Cities');
    var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
    if (headers.indexOf('MapX') === -1 || headers.indexOf('MapY') === -1) {
      throw new Error('Kolom MapX/MapY belum ada - jalankan migrateSetSail().');
    }
    return 'Ada.';
  });

  check('Player row untuk akun ini', function () {
    var player = PlayerService.getOrCreatePlayer();
    return JSON.stringify(player);
  });

  check('api_getGameState() end-to-end', function () {
    var player = PlayerService.getOrCreatePlayer();
    if (!player.hasCharacter) return 'Dilewati (akun ini belum punya karakter).';
    var state = api_getGameState();
    var size = JSON.stringify(state).length;
    return 'OK, payload ' + size + ' chars.';
  });

  check('Script time zone', function () {
    return Session.getScriptTimeZone();
  });

  return report;
}

// --- Main Game State ---

function api_getGameState(knownCitiesVersion) {
  SheetCache.reset();
  var player = PlayerService.getOrCreatePlayer();
  if (!player.hasCharacter) return { needsCharacter: true, username: AUTH_CTX_ ? AUTH_CTX_.username : '' };

  var playerId = player.playerId;

  // Selesaikan voyage yang sudah waktunya tiba SEBELUM baca kota/state
  // lain - supaya kedatangan selalu diproses tepat waktu begitu pemain
  // buka game lagi, walau dia tidak sedang melihat layar saat kapal
  // benar-benar merapat.
  LocationService.resolveArrivalIfDue(playerId);

  var cityId = LocationService.getCurrentCityId(playerId);
  var city = LocationService.getCityById(cityId);

  if (!city) {
    // Fallback aman kalau data lokasi pemain menunjuk ke kota yang sudah
    // tidak ada lagi di sheet Cities (mis. admin sedang eksperimen data) -
    // daripada client crash karena city null.
    city = LocationService.getCityById('sunda_empire');
  }

  var result = {
    player: player,
    stats: CharacterService.getCharacterStats(playerId),
    ship: ShipService.getShip(playerId),
    city: city,
    // PERFORMANCE (strategyinstant.md): array Cities PENUH tidak lagi
    // dikirim di sini - cuma versinya (angka kecil). Client cache
    // array-nya di localStorage, cuma fetch ulang via api_getCities()
    // kalau versi berubah (admin edit Cities). Lihat WorldService.gs.
    citiesVersion: WorldService.getCitiesVersion(),
    voyage: LocationService.getVoyageState(playerId),
    bank: BankService.getState(playerId),
    mission: MissionService.getMissionState(playerId),
    reputationHere: MissionService.getReputationForCity(player, city.CityId),
    // Fase 6: World Event ekonomi/sosial yang sedang aktif di kota ini
    // (null kalau tidak ada) - ditampilkan sebagai banner kecil di scene.
    cityEvent: WorldEventService.getActiveEventForCity(city.CityId),
    gameDay: TimeService.getCurrentGameDay(),
    minutesUntilNextGameDay: TimeService.getMinutesUntilNextGameDay(),
    audio: AudioService.getAudioConfig(),
    logs: LogService.getRecentLogs(playerId, 30),
    // Tide v3: wajah kapten (ScriptProperties, bukan sheet)
    appearance: AppearanceStore_.get(playerId),
    // Tide v4: Tanda Jasa & statistik kecil (ScriptProperties, bukan sheet)
    meta: MetaStore_.get(playerId)
  };

  // LATENCY: kalau client belum punya cache Cities versi terbaru, kirim
  // sekalian di sini - hemat SATU round-trip api_getCities() saat boot.
  if (knownCitiesVersion !== undefined && knownCitiesVersion !== result.citiesVersion) {
    result.cities = WorldService.getCities();
  }

  // Tide v6: umumkan kehadiran ke pemain lain (CacheService, murah)
  MP.touchFromState(result);
  result.username = AUTH_CTX_ ? AUTH_CTX_.username : '';

  // Log ukuran payload ke Executions > lihat tab "Logs" di eksekusi terkait -
  // membantu diagnosis kalau masalahnya ternyata soal ukuran response.
  try {
    Logger.log('api_getGameState() payload size: ' + JSON.stringify(result).length + ' chars');
  } catch (logErr) {
    Logger.log('api_getGameState() GAGAL di-JSON.stringify: ' + logErr.message);
  }

  return result;
}

// --- Settings ---

/**
 * PERFORMANCE (strategyinstant.md): array Cities lengkap - dipisah dari
 * api_getGameState() supaya cuma ditarik SEKALI dan di-cache di
 * localStorage client, bukan dikirim ulang di setiap load state. Lihat
 * citiesVersion di api_getGameState() dan resolveCitiesThenApply_() di
 * JavaScript.html.
 */
function api_getCities() {
  SheetCache.reset();
  return { cities: WorldService.getCities(), version: WorldService.getCitiesVersion() };
}

/**
 * PERFORMANCE (strategyinstant.md): endpoint SANGAT ringan khusus buat
 * polling progress pelayaran (dipanggil client tiap beberapa detik
 * selama inTransit) - SENGAJA tidak menarik Bank/Mission/Ship/Log/Stats
 * seperti api_getGameState() penuh. Tetap memproses
 * resolveArrivalIfDue() (jadi kedatangan/pirate encounter tetap
 * ke-detect tepat waktu meski pemain tidak buka panel apapun), tapi
 * hasilnya cuma voyage state - client sendiri yang decide kapan perlu
 * loadState() penuh (begitu inTransit berubah dari true ke false, lihat
 * pollVoyage_() di JavaScript.html).
 */
function api_pollVoyage() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  LocationService.resolveArrivalIfDue(playerId);
  return { voyage: LocationService.getVoyageState(playerId) };
}

function api_deleteCharacter() {
  SheetCache.reset();
  try { MetaStore_.clear(PlayerService.getCurrentPlayerId()); } catch (e) {}
  return CharacterService.deleteCharacter();
}

// --- Library / Books (Fase 2) ---

function api_getLibrary() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  var cityId = LocationService.getCurrentCityId(playerId);
  return BookService.getLibraryState(playerId, cityId);
}

function api_buyBook(bookId) {
  SheetCache.reset();
  return BookService.buyBook(bookId);
}

/**
 * PERFORMANCE: endpoint sempit khusus buat re-sync panel Character
 * setelah beli buku (StatEffects permanen mengubah CharacterStats) -
 * dipakai SEBAGAI GANTI loadState() penuh. Lihat doBuyBook() di
 * JavaScript.html.
 */
function api_getCharacterStats() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return { stats: CharacterService.getCharacterStats(playerId) };
}

// --- Market ---

function api_getMarket(cityId) {
  SheetCache.reset();
  return MarketService.getMarketForCity(cityId);
}

function api_buy(cityId, commodityId, qty) {
  SheetCache.reset();
  return MarketService.buy(cityId, commodityId, qty);
}

function api_sell(cityId, commodityId, qty) {
  SheetCache.reset();
  return MarketService.sell(cityId, commodityId, qty);
}

// --- Cargo ---

function api_getCargo() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return CargoService.getCargo(playerId);
}

/**
 * PERFORMANCE (strategyinstant.md, sesi "instant panel load"): gabungan
 * api_getCargo() + api_getWarehouse() dalam SATU round-trip - panel
 * Cargo dulu perlu 2 panggilan berurutan buat render lengkap, sekarang
 * cukup 1. Dipakai renderCargo() DAN prefetchPanelData_() di
 * JavaScript.html.
 */
function api_getCargoState(cityId) {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return {
    cargo: CargoService.getCargo(playerId),
    warehouse: WarehouseService.getWarehouseContents(playerId, cityId),
    missionLoad: MissionService.getMissionLoad(playerId)
  };
}

// --- Set Sail ---

function api_getSailOptions() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return LocationService.getSailOptions(playerId);
}

function api_setSail(cityId) {
  SheetCache.reset();
  var res = LocationService.setSail(cityId);
  try { MP.markSea(PlayerService.getCurrentPlayerId(), cityId); } catch (e) {}
  return res;
}

// --- Ship Upgrades (Fase 3a) & Repair (Fase 3c) ---

/**
 * PERFORMANCE: endpoint sempit khusus buat panel Ship re-render setelah
 * upgrade/reparasi - jauh lebih murah daripada api_getGameState() penuh
 * (yang juga narik Bank/Mission/Voyage/Log yang tidak berubah oleh aksi
 * ini). Dipakai client SEBAGAI GANTI loadState() penuh - lihat
 * doShipUpgrade()/doRepairShip() di JavaScript.html.
 */
function api_getShipState() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return { ship: ShipService.getShip(playerId) };
}

function api_getShipUpgrades() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return {
    current: ShipUpgradeService.getPlayerUpgrades(playerId),
    affordable: ShipUpgradeService.getAffordableUpgrades(playerId),
    allCatalogs: ShipUpgradeService.getAllCatalogs()
  };
}

function api_shipUpgrade(group) {
  SheetCache.reset();
  return ShipUpgradeService.upgradeShip(group);
}

function api_getRepairQuote(cityId) {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return ShipUpgradeService.getRepairQuote(playerId, cityId);
}

function api_repairShip(cityId) {
  SheetCache.reset();
  return ShipUpgradeService.repairShip(cityId);
}

// --- Combat (Fase 3b) ---

function api_resolveCombat(tactic) {
  SheetCache.reset();
  return CombatService.resolveCombat(tactic);
}

// --- Bank & Moneylender ---

function api_getBankState() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return BankService.getState(playerId);
}

function api_bankDeposit(amount) {
  SheetCache.reset();
  return BankService.deposit(amount);
}

function api_bankWithdraw(amount) {
  SheetCache.reset();
  return BankService.withdraw(amount);
}

function api_bankBorrow(amount) {
  SheetCache.reset();
  return BankService.borrow(amount);
}

function api_bankRepay(amount) {
  SheetCache.reset();
  return BankService.repay(amount);
}

// --- Warehouse (Port Authority) ---

function api_getWarehouse(cityId) {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return WarehouseService.getWarehouseContents(playerId, cityId);
}

function api_warehouseStore(cityId, commodityId, qty) {
  SheetCache.reset();
  return WarehouseService.storeItem(cityId, commodityId, qty);
}

function api_warehouseWithdraw(cityId, commodityId, qty) {
  SheetCache.reset();
  return WarehouseService.withdrawItem(cityId, commodityId, qty);
}

// --- Governor's Missive / Mission Board (Tasks, Fase 4) ---

function api_getMissionState() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  return MissionService.getMissionState(playerId);
}

function api_getMissionBoard(cityId) {
  SheetCache.reset();
  return MissionService.getMissionBoard(cityId);
}

function api_acceptMission(cityId, offerIndex) {
  SheetCache.reset();
  return MissionService.acceptNewMission(cityId, offerIndex);
}

/** Tide v8: misi Pesanan - beli barang pesanan di pulau sumber (masuk muatan misi terkunci). */
function api_buyForMission() {
  SheetCache.reset();
  return MissionService.buyForMission();
}

function api_abandonMission() {
  SheetCache.reset();
  return MissionService.abandonMission();
}

function api_completeMission() {
  SheetCache.reset();
  return MissionService.completeMission();
}

// --- Items & Treasure (Fase 5 - Exploration & Treasure) ---

/**
 * State panel Items baru: artifact yang dimiliki (2 slot equipment) +
 * treasure map yang dimiliki + status decode, DAN toko peta di kota
 * saat ini (kalau ada yang dijual - lihat ItemService.getTreasureMapShop()).
 */
function api_getItems() {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  var cityId = LocationService.getCurrentCityId(playerId);
  return {
    artifacts: ItemService.getPlayerArtifactsView(playerId),
    treasureMaps: TreasureService.getPlayerTreasureMapsView(playerId),
    shop: ItemService.getTreasureMapShop(cityId)
  };
}

function api_getTreasureMapDetail(itemId) {
  SheetCache.reset();
  return TreasureService.getTreasureMapDetail(itemId);
}

function api_digTreasure(itemId) {
  SheetCache.reset();
  return TreasureService.digTreasure(itemId);
}

function api_equipArtifact(itemId) {
  SheetCache.reset();
  return ItemService.equipArtifact(itemId);
}

function api_unequipArtifact(slotKey) {
  SheetCache.reset();
  return ItemService.unequipArtifact(slotKey);
}

function api_sellItem(itemId, qty) {
  SheetCache.reset();
  return ItemService.sellItem(itemId, qty);
}

function api_buyTreasureMap(itemId) {
  SheetCache.reset();
  return ItemService.buyTreasureMap(itemId);
}

// --- Leaderboard ---

/**
 * "Wealthiest Captains" - papan peringkat sederhana berbasis Gold,
 * terinspirasi semangat "amass your fortune" Tradewinds 2. Sengaja
 * ringan (cuma baca sheet Players, tidak menghitung cargo/kapal semua
 * pemain yang mahal) - ditampilkan di panel Settings.
 */
function api_getLeaderboard() {
  SheetCache.reset();
  var data = SheetCache.getData('Players');
  var rows = [];

  for (var i = 1; i < data.length; i++) {
    if (data[i][1]) { // CharacterName terisi = punya karakter
      rows.push({ characterName: data[i][1], archetype: data[i][2], gold: Number(data[i][3]) || 0, _id: data[i][0] });
    }
  }

  rows.sort(function (a, b) { return b.gold - a.gold; });
  var top = rows.slice(0, 5);
  // Tide v3: sertakan wajah kapten (tanpa membocorkan email/playerId)
  try {
    var all = AppearanceStore_.all(), metas = MetaStore_.all();
    top.forEach(function (r) { r.appearance = all[r._id] || null; r.badges = metas[r._id] ? Object.keys(metas[r._id].u || {}).length : 0; delete r._id; });
  } catch (e) { top.forEach(function (r) { delete r._id; }); }
  return top;
}


// =====================================================================
// Tide v3 (Marantau) - tambahan ADITIF, tidak mengubah sheet apa pun.
// =====================================================================

/**
 * Wajah kapten disimpan di ScriptProperties dengan key "face:<playerId>"
 * (JSON kecil ~80 byte). Sengaja TIDAK di sheet supaya tidak perlu migrasi
 * kolom baru. Nilai divalidasi ketat (whitelist) sebelum disimpan.
 */
var AppearanceStore_ = (function () {
  var HEADS = ['arch', 'none', 'hijab', 'peci', 'blangkon', 'bandana', 'tricorne'];
  function clean(a) {
    a = a || {};
    function int(v, max) { v = Math.floor(Number(v) || 0); return Math.max(0, Math.min(max, v)); }
    return { fem: a.fem ? 1 : 0, skin: int(a.skin, 5), hair: int(a.hair, 5), hairStyle: int(a.hairStyle, 5), facial: int(a.facial, 4), head: HEADS.indexOf(a.head) >= 0 ? a.head : 'arch', eyes: int(a.eyes, 2), seed: int(a.seed, 999999) };
  }
  function key(playerId) { return 'face:' + playerId; }
  function get(playerId) {
    try { var raw = PropertiesService.getScriptProperties().getProperty(key(playerId)); return raw ? JSON.parse(raw) : null; } catch (e) { return null; }
  }
  function save(playerId, a) {
    var c = clean(a);
    PropertiesService.getScriptProperties().setProperty(key(playerId), JSON.stringify(c));
    return c;
  }
  function all() {
    var props = PropertiesService.getScriptProperties().getProperties(), out = {};
    Object.keys(props).forEach(function (k) { if (k.indexOf('face:') === 0) { try { out[k.substr(5)] = JSON.parse(props[k]); } catch (e) {} } });
    return out;
  }
  return { get: get, save: save, all: all };
})();

function api_saveAppearance(appearance) {
  SheetCache.reset();
  return AppearanceStore_.save(PlayerService.getCurrentPlayerId(), appearance);
}

/**
 * LATENCY: SATU round-trip untuk semua data panel kota saat ini (dulu
 * 4-8 panggilan terpisah: cargo, gudang, market, library, papan misi,
 * opsi berlayar, upgrade kapal, kutipan reparasi, items). Semua baca
 * sheet berbagi SheetCache dalam satu eksekusi. Tiap bagian dibungkus
 * try/catch - satu bagian gagal tidak menggagalkan yang lain.
 */
function api_getCityBundle(cityId) {
  SheetCache.reset();
  var playerId = PlayerService.getCurrentPlayerId();
  var voyage = LocationService.getVoyageState(playerId);
  var here = LocationService.getCurrentCityId(playerId);
  cityId = cityId || here;
  var out = { cityId: cityId };
  function safe(k, fn) { try { out[k] = fn(); } catch (e) { out[k] = null; out[k + 'Error'] = e.message; } }
  safe('cargoState', function () { return { cargo: CargoService.getCargo(playerId), warehouse: WarehouseService.getWarehouseContents(playerId, cityId), missionLoad: MissionService.getMissionLoad(playerId) }; });
  safe('upgrades', function () { return { affordable: ShipUpgradeService.getAffordableUpgrades(playerId) }; });
  safe('items', function () { return { artifacts: ItemService.getPlayerArtifactsView(playerId), treasureMaps: TreasureService.getPlayerTreasureMapsView(playerId), shop: ItemService.getTreasureMapShop(here) }; });
  if (!voyage.inTransit) {
    safe('market', function () { return MarketService.getMarketForCity(cityId); });
    safe('library', function () { return BookService.getLibraryState(playerId, cityId); });
    safe('missionBoard', function () { return MissionService.getMissionBoard(cityId); });
    safe('sailOptions', function () { return LocationService.getSailOptions(playerId); });
    safe('repairQuote', function () { return ShipUpgradeService.getRepairQuote(playerId, cityId); });
  }
  return out;
}


// =====================================================================
// Tide v4 - Tanda Jasa (achievement) + statistik kecil per pemain.
// ScriptProperties "meta:<playerId>" (JSON < 8KB), divalidasi ketat.
// Digabung (union/max) dengan data server, jadi aman dipanggil dari
// beberapa perangkat sekaligus.
// =====================================================================
var MetaStore_ = (function () {
  var ID = /^[a-z0-9_]{1,24}$/;
  function key(playerId) { return 'meta:' + playerId; }
  function clean(m) {
    m = m || {};
    var out = { u: {}, c: {}, v: [] };
    Object.keys(m.u || {}).slice(0, 80).forEach(function (k) { if (ID.test(k)) out.u[k] = Math.max(0, Math.floor(Number(m.u[k]) || 0)); });
    Object.keys(m.c || {}).slice(0, 40).forEach(function (k) { if (ID.test(k)) out.c[k] = Math.max(0, Math.min(1e12, Math.floor(Number(m.c[k]) || 0))); });
    (Array.isArray(m.v) ? m.v : []).slice(0, 60).forEach(function (c) { c = String(c).substr(0, 40); if (c && out.v.indexOf(c) < 0) out.v.push(c); });
    return out;
  }
  function merge(a, b) {
    var o = clean(a), n = clean(b);
    Object.keys(n.u).forEach(function (k) { if (!o.u[k] || (n.u[k] && n.u[k] < o.u[k])) o.u[k] = n.u[k] || o.u[k] || 1; });
    Object.keys(n.c).forEach(function (k) { o.c[k] = Math.max(o.c[k] || 0, n.c[k]); });
    n.v.forEach(function (c) { if (o.v.indexOf(c) < 0) o.v.push(c); });
    return o;
  }
  function get(playerId) {
    try { var raw = PropertiesService.getScriptProperties().getProperty(key(playerId)); return raw ? JSON.parse(raw) : null; } catch (e) { return null; }
  }
  function save(playerId, m) {
    var merged = merge(get(playerId), m);
    var json = JSON.stringify(merged);
    if (json.length > 8000) throw new Error('Data Tanda Jasa terlalu besar.');
    PropertiesService.getScriptProperties().setProperty(key(playerId), json);
    return merged;
  }
  function clear(playerId) { PropertiesService.getScriptProperties().deleteProperty(key(playerId)); }
  function all() {
    var props = PropertiesService.getScriptProperties().getProperties(), out = {};
    Object.keys(props).forEach(function (k) { if (k.indexOf('meta:') === 0) { try { out[k.substr(5)] = JSON.parse(props[k]); } catch (e) {} } });
    return out;
  }
  return { get: get, save: save, clear: clear, all: all };
})();

function api_saveMeta(meta) {
  var lock = LockService.getUserLock();
  try { lock.waitLock(5000); } catch (e) {}
  try { return MetaStore_.save(PlayerService.getCurrentPlayerId(), meta); }
  finally { try { lock.releaseLock(); } catch (e) {} }
}


// =====================================================================
// Tide v6 - LOGIN AKUN + MULTIPLAYER
// =====================================================================

/**
 * Pintu tunggal RPC dari client: client memanggil api_rpc('api_xxx', [args], token).
 * Token diverifikasi -> AUTH_CTX_ diisi -> fungsi api_ aslinya dijalankan.
 * Hanya fungsi berawalan api_ yang boleh dipanggil lewat pintu ini.
 */
function api_rpc(name, args, token) {
  if (typeof name !== 'string' || !/^api_[A-Za-z0-9_]+$/.test(name) || name === 'api_rpc') throw new Error('Panggilan tidak dikenal.');
  var G = (typeof globalThis !== 'undefined') ? globalThis : this;
  var fn = G[name];
  if (typeof fn !== 'function') throw new Error('Fungsi tidak ditemukan: ' + name);
  AUTH_CTX_ = token ? AuthService.verify(token) : null;
  if (token && !AUTH_CTX_) throw new Error('AUTH_REQUIRED: Sesi habis, silakan masuk lagi.');
  try { return fn.apply(null, Array.isArray(args) ? args : []); }
  finally { AUTH_CTX_ = null; }
}

function api_authRegister(username, password) { SheetCache.reset(); return AuthService.register(username, password); }
function api_authLogin(username, password) { SheetCache.reset(); return AuthService.login(username, password); }
function api_authChangePassword(oldPass, newPass) { SheetCache.reset(); return AuthService.changePassword(AUTH_CTX_, oldPass, newPass); }
/** Siapa aku? Dipakai client saat boot untuk memutuskan: layar login / buat karakter / game. */
function api_authWhoAmI() {
  SheetCache.reset();
  var id;
  try { id = PlayerService.getCurrentPlayerId(); } catch (e) { return { loggedIn: false, mode: String(getGameConfigValue_('AuthMode') || 'auto') }; }
  PlayerService.ensurePlayerRow(id);
  var p = PlayerService.getPlayerById(id);
  return { loggedIn: true, username: AUTH_CTX_ ? AUTH_CTX_.username : '', viaGoogle: !AUTH_CTX_, hasCharacter: !!(p && p.hasCharacter), name: p ? p.characterName : '' };
}

function api_mpPulse(since) { return MP.pulse(since); }
function api_mpChat(channel, text) { return MP.postChat(channel, text); }
function api_mpProfile(pubId) { SheetCache.reset(); return MP.profile(pubId); }
function api_mpDuelChallenge(targetPub, stake, kind) { SheetCache.reset(); return MP.challenge(targetPub, stake, kind); }
function api_mpDuelRespond(duelId, accept) { SheetCache.reset(); return MP.respond(duelId, accept); }
function api_mpDuelAct(duelId, round, tactic) { SheetCache.reset(); return MP.act(duelId, round, tactic); }
function api_mpDuelState(duelId) { SheetCache.reset(); return MP.state(duelId); }
function api_mpDuelForfeit(duelId) { SheetCache.reset(); return MP.forfeit(duelId); }
function api_mpPvpBoard() { SheetCache.reset(); return MP.pvpBoard(); }
function api_mpOrders() { SheetCache.reset(); return MP.listOrders(); }
function api_mpPostOrder(commodityId, qty, price) { SheetCache.reset(); return MP.postOrder(commodityId, qty, price); }
function api_mpBuyOrder(orderId, qty) { SheetCache.reset(); return MP.buyOrder(orderId, qty); }
function api_mpCancelOrder(orderId) { SheetCache.reset(); return MP.cancelOrder(orderId); }
function api_mpGift(targetPub, amount) { SheetCache.reset(); return MP.gift(targetPub, amount); }
function api_mgFishCast() { SheetCache.reset(); return MP.fishCast(); }
function api_mgFishReel(castId, hit) { SheetCache.reset(); return MP.fishReel(castId, hit); }
function api_mgDice(bet, side) { SheetCache.reset(); return MP.dice(bet, side); }
