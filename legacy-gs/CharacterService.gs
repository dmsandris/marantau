/**
 * CharacterService.gs
 * ------------------------------------------------------------------
 * Menyelesaikan Character Creation: menulis CharacterStats, Ship
 * starter, PlayerLocation, dan meng-update Players (Archetype,
 * CharacterName, Gold, Reputation) - semua dalam satu Lock supaya
 * tidak ada state setengah-jadi kalau ada error di tengah proses.
 * ------------------------------------------------------------------
 */

var STARTING_GOLD = 5000;
var STARTER_SHIP_NAME = 'The Wandering Gull';

var CharacterService = (function () {

  function createCharacter(characterName, archetypeId) {
    var archetype = getArchetypeById(archetypeId);
    if (!archetype) throw new Error('Archetype tidak dikenali: ' + archetypeId);

    var name = (characterName || '').trim();
    if (!name) throw new Error('Nama karakter tidak boleh kosong.');
    if (name.length > 40) throw new Error('Nama karakter terlalu panjang (maks 40 karakter).');

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);

    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var existing = PlayerService.getOrCreatePlayer();

      if (existing.hasCharacter) {
        throw new Error('Karakter untuk akun ini sudah pernah dibuat.');
      }

      writeCharacterStats(playerId, archetype);
      writeStarterShip(playerId);
      writeStartingLocation(playerId);

      var reputation = {};
      if (archetype.startingReputationBonus) {
        reputation['sunda_empire'] = archetype.startingReputationBonus;
      }

      PlayerService.updatePlayerRow(playerId, {
        CharacterName: name,
        Archetype: archetype.id,
        Gold: STARTING_GOLD,
        Reputation: JSON.stringify(reputation)
      });

      LogService.addLog(playerId,
        'Began your journey as ' + name + ', ' + archetype.name.replace('The ', '') +
        ', in Sunda Empire.');

      return getFullCharacterState(playerId);
    } finally {
      lock.releaseLock();
    }
  }

  function writeCharacterStats(playerId, archetype) {
    var sheet = SheetCache.getSheet('CharacterStats');
    var stats = {};
    Object.keys(BASE_STATS).forEach(function (key) { stats[key] = BASE_STATS[key]; });
    Object.keys(archetype.bonuses || {}).forEach(function (key) {
      stats[key] = (stats[key] || 0) + archetype.bonuses[key];
    });

    sheet.appendRow([
      playerId, stats.Trading, stats.Negotiation, stats.Navigation,
      stats.Sailing, stats.Combat, stats.Luck, stats.Knowledge
    ]);
    SheetCache.invalidate('CharacterStats');
  }

  function writeStarterShip(playerId) {
    var sheet = SheetCache.getSheet('Ship');
    // PlayerId, ShipName, Tier, Hull, MaxHull, Cargo, Speed, Combat, Armor, Navigation, Condition,
    // ConditionDecayPerSail, MaxCondition, DamageThreshold (Fase 3a/3c - lihat migrateFase3aSetup())
    sheet.appendRow([playerId, STARTER_SHIP_NAME, 'I', 100, 100, 30, 50, 5, 10, 20, 100, 0.03, 100, 45]);
    SheetCache.invalidate('Ship');
  }

  function writeStartingLocation(playerId) {
    var sheet = SheetCache.getSheet('PlayerLocation');
    sheet.appendRow([playerId, 'sunda_empire', TimeService.getCurrentGameDay()]);
    SheetCache.invalidate('PlayerLocation');
  }

  function getCharacterStats(playerId) {
    var data = SheetCache.getData('CharacterStats');
    var headers = data[0];

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        var stats = {};
        headers.forEach(function (h, idx) { if (h !== 'PlayerId') stats[h] = data[i][idx]; });
        return stats;
      }
    }
    return null;
  }

  function getFullCharacterState(playerId) {
    var player = PlayerService.getOrCreatePlayer();
    var stats = getCharacterStats(playerId);
    var archetype = getArchetypeById(player.archetype);

    return {
      player: player,
      stats: stats,
      archetype: archetype ? { name: archetype.name, perkName: archetype.perkName, perkDesc: archetype.perkDesc } : null
    };
  }

  /**
   * Sheet-sheet yang menyimpan data per-karakter dan wajib dibersihkan
   * kalau karakter dihapus. Additive: aman kalau ada sheet fase depan
   * yang belum dibuat (deleteRowsForPlayer_ skip diam-diam kalau sheet
   * belum ada).
   */
  var DELETABLE_PLAYER_SHEETS = [
    'CharacterStats', 'Ship', 'ShipEquipment', 'PlayerLocation',
    'PlayerInventory', 'PlayerBooks', 'PlayerMissions', 'CombatLog', 'PlayerLog'
  ];

  /**
   * Hapus PERMANEN karakter pemain yang sedang login: semua stat, kapal,
   * cargo, lokasi, dan log dihapus dari sheet terkait, lalu row Players
   * di-reset (CharacterName/Archetype kosong, Gold & Reputation direset)
   * supaya doGet() otomatis mengarahkan balik ke Character Creation.
   *
   * Row Players SENDIRI tidak dihapus (biar histori CreatedAt/LastActive
   * akun tidak hilang) - hanya di-reset ke kondisi "belum bikin karakter".
   */
  function deleteCharacter() {
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);

    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var player = PlayerService.getOrCreatePlayer();

      if (!player.hasCharacter) {
        throw new Error('Belum ada karakter untuk dihapus.');
      }

      DELETABLE_PLAYER_SHEETS.forEach(function (sheetName) {
        deleteRowsForPlayer_(sheetName, playerId);
      });

      PlayerService.updatePlayerRow(playerId, {
        CharacterName: '',
        Archetype: '',
        Gold: 0,
        Reputation: '{}',
        ShipUpgrades: '{}'
      });

      return { success: true };
    } finally {
      lock.releaseLock();
    }
  }

  return {
    createCharacter: createCharacter,
    getCharacterStats: getCharacterStats,
    getFullCharacterState: getFullCharacterState,
    deleteCharacter: deleteCharacter
  };
})();
