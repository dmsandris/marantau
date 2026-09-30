/**
 * ShipUpgradeService.gs
 * ------------------------------------------------------------------
 * Fase 3a (Ship Upgrades) + Fase 3c (Condition & Repair) - lihat
 * FILES_SUMMARY.txt untuk spek awal & STATUS_ROADMAP.md untuk konteks.
 *
 * PATCH (logic fix + Level system): sebelumnya cargoBonus/maxConditionBonus
 * disimpan sebagai "TOTAL di tier itu" - begitu upgrade ke tier
 * berikutnya, TOTAL LAMA DIGANTI TOTAL BARU (bukan ditambah), jadi tier3
 * (total 30) terasa cuma naik dikit dari tier2 (total 15) padahal
 * labelnya sendiri bilang "+30". Sekarang KEDUA field itu genuinely
 * AKUMULATIF: tiap pembelian menambah nilai katalog tier itu MENTAH-
 * MENTAH di atas akumulasi sebelumnya (cargo 15 + beli tier3 (+30) =
 * 45, PERSIS sesuai contoh yang diminta). Field lain (speed, cannons,
 * decay%) TETAP nilai absolut-tier-terkini seperti sebelumnya (tidak
 * dilaporkan bermasalah).
 *
 * LEVEL SYSTEM (baru): tiap grup sekarang 5 LEVEL (I-V, V="Legendary"),
 * masing-masing level tetap 4 tier (I-IV) seperti sebelumnya. Begitu
 * tier IV di level saat ini sudah dibeli, pembelian berikutnya otomatis
 * lanjut ke Level berikutnya mulai dari Tier I lagi (bukan berhenti).
 * Biaya & efek tiap level dikalikan SHIP_LEVEL_MULT - jadi Level II
 * Tier I lebih mahal & lebih besar efeknya daripada Level I Tier I.
 * Maksimum mutlak: Level V Tier IV ("Legendary", tidak bisa upgrade lagi).
 *
 * Disimpan di Players.ShipUpgrades (JSON per grup). FORMAT BARU:
 *   { level: 1-5, tier: 0-4, accumulated: <angka, cargo/condition saja> }
 * FORMAT LAMA (angka polos 0-4 = tier di Level I) TETAP DIBACA - lihat
 * normalizeGroupState_() - dikonversi on-the-fly, accumulated DI-SEED
 * dari nilai TOTAL lama tier itu (supaya pemain lama TIDAK kehilangan
 * progress yang sudah kelihatan), baru pembelian SETELAHNYA pakai
 * logic akumulatif baru. Kolom ditambahkan oleh migrateFase3aSetup() di
 * SetupSheets.gs - GRACEFUL DEGRADATION tetap sama seperti sebelumnya:
 * kalau kolom belum ada, semua fungsi di sini menganggap belum ada
 * upgrade sama sekali alih-alih throw (pola sama dengan BankService.gs).
 * ------------------------------------------------------------------
 */

var SHIP_UPGRADE_CATALOGS = {
  speed: [
    { tier: 1, cost: 1500,  speedMultiplier: 0.80, label: '+20% lebih cepat' },
    { tier: 2, cost: 3500,  speedMultiplier: 0.65, label: '+35% lebih cepat' },
    { tier: 3, cost: 7000,  speedMultiplier: 0.50, label: '+50% lebih cepat' },
    { tier: 4, cost: 12000, speedMultiplier: 0.40, label: '+60% lebih cepat' }
  ],
  cargo: [
    { tier: 1, cost: 1000, cargoBonus: 5,  label: '+5 kapasitas' },
    { tier: 2, cost: 2500, cargoBonus: 15, label: '+15 kapasitas' },
    { tier: 3, cost: 5000, cargoBonus: 30, label: '+30 kapasitas' },
    { tier: 4, cost: 9000, cargoBonus: 50, label: '+50 kapasitas' }
  ],
  condition: [
    { tier: 1, cost: 2000,  maxConditionBonus: 10, decayReductionPercent: 0,  label: '+10 max, tanpa kurangi decay' },
    { tier: 2, cost: 4000,  maxConditionBonus: 20, decayReductionPercent: 5,  label: '+20 max, -5% decay' },
    { tier: 3, cost: 7500,  maxConditionBonus: 30, decayReductionPercent: 10, label: '+30 max, -10% decay' },
    { tier: 4, cost: 13000, maxConditionBonus: 45, decayReductionPercent: 20, label: '+45 max, -20% decay' }
  ],
  cannons: [
    { tier: 1, cost: 1200,  combatBonusPercent: 5,  ammoBonus: 1, label: '+5% peluang menang, +1 amunisi meriam' },
    { tier: 2, cost: 3000,  combatBonusPercent: 10, ammoBonus: 2, label: '+10% peluang menang, +2 amunisi meriam' },
    { tier: 3, cost: 6000,  combatBonusPercent: 15, ammoBonus: 3, label: '+15% peluang menang, +3 amunisi meriam' },
    { tier: 4, cost: 11000, combatBonusPercent: 20, ammoBonus: 4, label: '+20% peluang menang, +4 amunisi meriam' }
  ]
};

var SHIP_UPGRADE_GROUPS = ['speed', 'cargo', 'condition', 'cannons'];

// Grup yang bonusnya AKUMULATIF (dijumlah tiap pembelian) - lihat catatan
// patch di atas. Grup lain (speed, cannons, condition.decayReductionPercent)
// tetap "nilai tier terkini" seperti semula.
var SHIP_ACCUMULATING_FIELDS = {
  cargo: 'cargoBonus',
  condition: 'maxConditionBonus'
};

var SHIP_LEVEL_COUNT = 5;
// Skala biaya & besaran efek per Level (index 0 = Level I, dst). Level I
// = angka katalog asli (tidak berubah utk kapal yang sudah ada).
var SHIP_LEVEL_MULT = [1, 2, 3.5, 5, 7.5];
var SHIP_LEVEL_ROMAN = ['I', 'II', 'III', 'IV', 'V'];

var ShipUpgradeService = (function () {

  function getPlayersSheet_() {
    return SheetCache.getSheet('Players');
  }

  function getShipSheet_() {
    return SheetCache.getSheet('Ship');
  }

  function isMigrated_() {
    var headers = SheetCache.getHeaders('Players');
    var shipHeaders = SheetCache.getHeaders('Ship');
    return headers.indexOf('ShipUpgrades') !== -1 &&
      shipHeaders.indexOf('ConditionDecayPerSail') !== -1 &&
      shipHeaders.indexOf('MaxCondition') !== -1;
  }

  /**
   * Normalisasi satu grup dari JSON mentah ke {level, tier, accumulated}.
   * Terima 2 bentuk: angka polos (format LAMA, = tier di Level I) atau
   * object {level,tier,accumulated} (format BARU). accumulated di-seed
   * dari TOTAL lama kalau baru pertama kali dikonversi, supaya progress
   * yang sudah kelihatan pemain tidak hilang/turun.
   */
  function normalizeGroupState_(group, raw) {
    var catalog = SHIP_UPGRADE_CATALOGS[group];
    var field = SHIP_ACCUMULATING_FIELDS[group];

    if (raw && typeof raw === 'object') {
      var level = Number(raw.level) || (Number(raw.tier) > 0 ? 1 : 0);
      var tier = Number(raw.tier) || 0;
      var accumulated = Number(raw.accumulated) || 0;
      return { level: level, tier: tier, accumulated: accumulated };
    }

    // Format lama: angka polos = tier di Level I.
    var oldTier = Number(raw) || 0;
    var seedAccumulated = 0;
    if (field && oldTier > 0 && catalog[oldTier - 1]) {
      seedAccumulated = catalog[oldTier - 1][field] || 0; // seed dari TOTAL lama tier itu
    }
    return { level: oldTier > 0 ? 1 : 0, tier: oldTier, accumulated: seedAccumulated };
  }

  /** {speed:{level,tier,accumulated}, cargo:{...}, condition:{...}, cannons:{...}} - default kosong kalau belum ada/rusak. */
  function getPlayerUpgrades(playerId) {
    var empty = {
      speed: { level: 0, tier: 0, accumulated: 0 },
      cargo: { level: 0, tier: 0, accumulated: 0 },
      condition: { level: 0, tier: 0, accumulated: 0 },
      cannons: { level: 0, tier: 0, accumulated: 0 }
    };
    if (!isMigrated_()) return empty;

    var data = SheetCache.getData('Players');
    var headers = data[0];
    var col = headers.indexOf('ShipUpgrades');

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        var raw = data[i][col];
        if (!raw) return empty;
        try {
          var parsed = JSON.parse(raw);
          var out = {};
          SHIP_UPGRADE_GROUPS.forEach(function (g) {
            out[g] = normalizeGroupState_(g, parsed[g]);
          });
          return out;
        } catch (e) {
          return empty;
        }
      }
    }
    return empty;
  }

  function writePlayerUpgrades_(playerId, upgrades) {
    var sheet = getPlayersSheet_();
    var data = SheetCache.getData('Players');
    var headers = data[0];
    var col = headers.indexOf('ShipUpgrades');
    if (col === -1) throw new Error('Kolom ShipUpgrades belum ada - admin perlu menjalankan migrateFase3aSetup().');

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        sheet.getRange(i + 1, col + 1).setValue(JSON.stringify(upgrades));
        SheetCache.invalidate('Players');
        return;
      }
    }
    throw new Error('Player ' + playerId + ' tidak ditemukan.');
  }

  function getShipRow_(playerId) {
    var data = SheetCache.getData('Ship');
    var headers = data[0];
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        var row = {};
        headers.forEach(function (h, idx) { row[h] = data[i][idx]; });
        row.__rowIndex = i + 1;
        row.__headers = headers;
        return row;
      }
    }
    return null;
  }

  function setShipColumn_(playerId, colName, value) {
    var sheet = getShipSheet_();
    var data = SheetCache.getData('Ship');
    var headers = data[0];
    var col = headers.indexOf(colName);
    if (col === -1) return; // graceful - kolom belum ada, lewati diam-diam

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        sheet.getRange(i + 1, col + 1).setValue(value);
        SheetCache.invalidate('Ship');
        return;
      }
    }
  }

  /** Nomor urut mutlak 1-20 dari kombinasi (level,tier) - dipakai kurva formula speed/cannons/decay lanjutan Level II+. */
  function absoluteStep_(level, tier) {
    if (level < 1 || tier < 1) return 0;
    return (level - 1) * 4 + tier;
  }

  /** SpeedMultiplier absolut tier terkini - tabel asli utk step 1-4 (Level I, TIDAK berubah), kurva menurun halus utk step lanjutan (lantai 0.15 - kapal tidak pernah "gratis instan"). */
  function speedMultiplierForStep_(step) {
    if (step <= 0) return 1;
    var table = [0.80, 0.65, 0.50, 0.40];
    if (step <= 4) return table[step - 1];
    return Math.max(0.15, 0.40 - 0.02 * (step - 4));
  }

  /** DecayReductionPercent absolut tier terkini - sama pola dengan speed. */
  function decayReductionForStep_(step) {
    if (step <= 0) return 0;
    var table = [0, 5, 10, 20];
    if (step <= 4) return table[step - 1];
    return Math.min(50, 20 + 2 * (step - 4));
  }

  /** CombatBonusPercent absolut tier terkini - sama pola. */
  function combatBonusForStep_(step) {
    if (step <= 0) return 0;
    var table = [5, 10, 15, 20];
    if (step <= 4) return table[step - 1];
    return Math.min(60, 20 + 2 * (step - 4));
  }

  /** AmmoBonus absolut tier terkini - +1 amunisi tiap 2 tier lanjutan setelah Level I penuh. */
  function ammoBonusForStep_(step) {
    if (step <= 0) return 0;
    var table = [1, 2, 3, 4];
    if (step <= 4) return table[step - 1];
    return 4 + Math.floor((step - 4) / 2);
  }

  /**
   * Stat efektif kapal HASIL upgrade - dipanggil ShipService.getShip()
   * di setiap load, jadi HARUS ringan (tidak baca sheet ekstra selain
   * Ship & Players yang sudah dibaca caller).
   */
  function getEffectiveShipStats(playerId) {
    var upgrades = getPlayerUpgrades(playerId);
    var speedStep = absoluteStep_(upgrades.speed.level, upgrades.speed.tier);
    var conditionStep = absoluteStep_(upgrades.condition.level, upgrades.condition.tier);
    var cannonStep = absoluteStep_(upgrades.cannons.level, upgrades.cannons.tier);

    return {
      upgrades: upgrades,
      speedMultiplier: speedMultiplierForStep_(speedStep),
      cargoBonus: upgrades.cargo.accumulated, // akumulatif, lihat catatan patch di atas
      maxConditionBonus: upgrades.condition.accumulated, // akumulatif juga
      decayReductionPercent: decayReductionForStep_(conditionStep),
      cannonBonusPercent: combatBonusForStep_(cannonStep),
      cannonAmmoBonus: ammoBonusForStep_(cannonStep)
    };
  }

  function getAllCatalogs() {
    return SHIP_UPGRADE_CATALOGS;
  }

  /** {maxed} kalau sudah Level V Tier IV, atau {nextLevel, nextTier} kombinasi berikutnya (loncat ke Level+1 Tier I begitu Tier IV level ini terbeli). */
  function nextPurchaseSlot_(state) {
    var level = state.level || 0;
    var tier = state.tier || 0;
    if (level === 0) return { maxed: false, nextLevel: 1, nextTier: 1 };
    if (level >= SHIP_LEVEL_COUNT && tier >= 4) return { maxed: true };

    var nextTier = tier + 1;
    var nextLevel = level;
    if (nextTier > 4) { nextTier = 1; nextLevel = level + 1; }
    return { maxed: false, nextLevel: nextLevel, nextTier: nextTier };
  }

  function formatLevelTierLabel_(level, tier) {
    return 'Level ' + SHIP_LEVEL_ROMAN[level - 1] + ' &middot; Tier ' + romanNumeral_(tier);
  }

  function getAffordableUpgrades(playerId) {
    var player = PlayerService.getOrCreatePlayer();
    var upgrades = getPlayerUpgrades(playerId);
    var result = {};

    SHIP_UPGRADE_GROUPS.forEach(function (group) {
      var state = upgrades[group];
      var slot = nextPurchaseSlot_(state);

      if (slot.maxed) {
        result[group] = {
          maxed: true,
          currentLevel: state.level,
          currentTier: state.tier,
          currentLabel: formatLevelTierLabel_(state.level, state.tier)
        };
        return;
      }

      var catalogEntry = SHIP_UPGRADE_CATALOGS[group][slot.nextTier - 1];
      var levelMult = SHIP_LEVEL_MULT[slot.nextLevel - 1];
      var cost = Math.round(catalogEntry.cost * levelMult);

      result[group] = {
        maxed: false,
        currentLevel: state.level,
        currentTier: state.tier,
        currentLabel: state.tier > 0 ? formatLevelTierLabel_(state.level, state.tier) : 'Belum di-upgrade',
        nextLevel: slot.nextLevel,
        nextTier: slot.nextTier,
        nextLabel: formatLevelTierLabel_(slot.nextLevel, slot.nextTier),
        cost: cost,
        label: catalogEntry.label + (slot.nextLevel > 1 ? ' (skala Level ' + SHIP_LEVEL_ROMAN[slot.nextLevel - 1] + ')' : ''),
        affordable: player.gold >= cost
      };
    });

    return result;
  }

  function upgradeShip(group) {
    if (SHIP_UPGRADE_GROUPS.indexOf(group) === -1) throw new Error('Grup upgrade tidak dikenali: ' + group);

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      if (!isMigrated_()) {
        throw new Error('Fitur Ship Upgrade belum siap - admin perlu menjalankan migrateFase3aSetup().');
      }

      var playerId = PlayerService.getCurrentPlayerId();
      var upgrades = getPlayerUpgrades(playerId);
      var state = upgrades[group];
      var slot = nextPurchaseSlot_(state);
      if (slot.maxed) throw new Error('Grup ini sudah Level V Tier IV (Legendary) - sudah maksimum mutlak.');

      var catalogEntry = SHIP_UPGRADE_CATALOGS[group][slot.nextTier - 1];
      var levelMult = SHIP_LEVEL_MULT[slot.nextLevel - 1];
      var cost = Math.round(catalogEntry.cost * levelMult);

      var player = PlayerService.getOrCreatePlayer();
      if (player.gold < cost) {
        throw new Error('Gold tidak cukup. Butuh ' + cost + ', kamu punya ' + player.gold + '.');
      }

      // Akumulasi (cargo/condition) - tambah MENTAH nilai katalog tier ini
      // (dikali skala Level) DI ATAS akumulasi sebelumnya, bukan diganti.
      var field = SHIP_ACCUMULATING_FIELDS[group];
      var newAccumulated = state.accumulated || 0;
      if (field) newAccumulated += Math.round(catalogEntry[field] * levelMult);

      state.level = slot.nextLevel;
      state.tier = slot.nextTier;
      state.accumulated = newAccumulated;
      upgrades[group] = state;
      writePlayerUpgrades_(playerId, upgrades);
      PlayerService.updatePlayerRow(playerId, { Gold: player.gold - cost });

      var levelTierLabel = formatLevelTierLabel_(slot.nextLevel, slot.nextTier);
      LogService.addLog(playerId, 'Upgraded ship ' + group + ' to ' + levelTierLabel.replace('&middot;', '-') +
        ' (' + catalogEntry.label + ') for ' + cost + ' gold.');

      return {
        success: true,
        group: group,
        newLevel: slot.nextLevel,
        newTier: slot.nextTier,
        newLevelTierLabel: levelTierLabel,
        goldSpent: cost,
        effect: catalogEntry.label,
        newGold: player.gold - cost
      };
    } finally {
      lock.releaseLock();
    }
  }

  function romanNumeral_(n) {
    return ['0', 'I', 'II', 'III', 'IV'][n] || String(n);
  }

  /**
   * Kutipan biaya reparasi (tanpa mengubah apapun) - dipakai UI panel
   * Ship untuk menampilkan harga sebelum pemain klik "Reparasi".
   * Biaya = poin Condition yang hilang x ShipRepairBaseCostPerPoint x
   * Cities.RepairCostRate kota tempat pemain berlabuh sekarang.
   */
  function getRepairQuote(playerId, cityId) {
    var ship = getShipRow_(playerId);
    if (!ship) throw new Error('Kapal tidak ditemukan.');

    var effective = getEffectiveShipStats(playerId);
    var maxCondition = 100 + effective.maxConditionBonus;
    var currentCondition = Number(ship.Condition);
    if (isNaN(currentCondition)) currentCondition = maxCondition;
    currentCondition = Math.min(currentCondition, maxCondition);

    var missing = Math.max(0, maxCondition - currentCondition);
    var city = LocationService.getCityById(cityId);
    var rate = city ? Number(city.RepairCostRate) || 1 : 1;
    var baseCostPerPoint = getGameConfigNumber_('ShipRepairBaseCostPerPoint', 15);
    var cost = Math.round(missing * baseCostPerPoint * rate);

    return {
      currentCondition: Math.round(currentCondition),
      maxCondition: maxCondition,
      missing: Math.round(missing),
      cost: cost
    };
  }

  function repairShip(cityId) {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      if (LocationService.getVoyageState(playerId).inTransit) {
        throw new Error('Kamu sedang berlayar - reparasi hanya bisa dilakukan saat merapat di pelabuhan.');
      }
      if (LocationService.getCurrentCityId(playerId) !== cityId) {
        throw new Error('Kamu harus berada di kota ini untuk reparasi.');
      }

      var quote = getRepairQuote(playerId, cityId);
      if (quote.missing <= 0) throw new Error('Kapal sudah dalam kondisi penuh.');

      var player = PlayerService.getOrCreatePlayer();
      if (player.gold < quote.cost) {
        throw new Error('Gold tidak cukup. Butuh ' + quote.cost + ', kamu punya ' + player.gold + '.');
      }

      setShipColumn_(playerId, 'Condition', quote.maxCondition);
      PlayerService.updatePlayerRow(playerId, { Gold: player.gold - quote.cost });

      var city = LocationService.getCityById(cityId);
      LogService.addLog(playerId, 'Repaired the ship at ' + (city ? city.Name : cityId) +
        ' for ' + quote.cost + ' gold (Condition restored to ' + quote.maxCondition + ').');

      return { success: true, newCondition: quote.maxCondition, goldSpent: quote.cost, newGold: player.gold - quote.cost };
    } finally {
      lock.releaseLock();
    }
  }

  /**
   * Kurangi Condition kapal sejumlah poin (dipanggil LocationService
   * setiap voyage selesai / decay, dan CombatService saat kapal kena
   * damage) - diclamp 0..MaxCondition efektif. Boleh delta negatif
   * (rusak) maupun positif (dipakai internal repair/rescue).
   */
  function applyConditionDelta(playerId, deltaPoints) {
    var ship = getShipRow_(playerId);
    if (!ship) return null;

    var effective = getEffectiveShipStats(playerId);
    var maxCondition = 100 + effective.maxConditionBonus;
    var current = Number(ship.Condition);
    if (isNaN(current)) current = maxCondition;

    var next = Math.max(0, Math.min(maxCondition, current + deltaPoints));
    setShipColumn_(playerId, 'Condition', Math.round(next));
    return Math.round(next);
  }

  /** Poin Condition yang hilang untuk SATU voyage, sudah dipotong bonus decayReductionPercent. */
  function getConditionDecayForVoyage(playerId) {
    var ship = getShipRow_(playerId);
    if (!ship) return 0;

    var baseDecayFraction = Number(ship.ConditionDecayPerSail);
    if (isNaN(baseDecayFraction) || !ship.__headers || ship.__headers.indexOf('ConditionDecayPerSail') === -1) {
      baseDecayFraction = 0.03; // default 3% kalau kolom belum ada (graceful)
    }
    var basePoints = baseDecayFraction * 100;
    var effective = getEffectiveShipStats(playerId);
    return basePoints * (1 - effective.decayReductionPercent / 100);
  }

  /** Ambang Condition (di bawah ini peluang encounter naik) - dipakai CombatService. */
  function getDamageThreshold(playerId) {
    var ship = getShipRow_(playerId);
    if (!ship || !ship.__headers || ship.__headers.indexOf('DamageThreshold') === -1) return 45;
    var val = Number(ship.DamageThreshold);
    return isNaN(val) ? 45 : val;
  }

  return {
    getPlayerUpgrades: getPlayerUpgrades,
    getEffectiveShipStats: getEffectiveShipStats,
    getAllCatalogs: getAllCatalogs,
    getAffordableUpgrades: getAffordableUpgrades,
    upgradeShip: upgradeShip,
    getRepairQuote: getRepairQuote,
    repairShip: repairShip,
    applyConditionDelta: applyConditionDelta,
    getConditionDecayForVoyage: getConditionDecayForVoyage,
    getDamageThreshold: getDamageThreshold,
    isMigrated: isMigrated_
  };
})();
