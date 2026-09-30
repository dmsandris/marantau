/**
 * CombatService.gs
 * ------------------------------------------------------------------
 * Fase 3b - Ship & Combat, DIROMBAK jadi simulasi multi-ronde ala
 * Tradewinds 2 (bukan lagi satu klik = langsung selesai). Pirate
 * encounter di-roll oleh LocationService begitu waktu tiba voyage
 * (lihat LocationService.resolveArrivalIfDue -> rollEncounterForArrival).
 * Kalau kena, voyage "ditahan" (PendingEncounter tersimpan di
 * PlayerLocation) sampai musuh kalah/kabur/damai/kapal tenggelam.
 *
 * SETIAP panggilan api_resolveCombat(tactic) memproses SATU ronde
 * (kecuali bribe/negotiate-sukses/ram yang langsung menuntaskan
 * pertempuran) - HP musuh & amunisi meriam kapal persisten di dalam
 * PendingEncounter (JSON) antar ronde, jadi terasa seperti pertempuran
 * sungguhan yang berkembang, bukan satu roll dadu tunggal.
 *
 * 6 taktik:
 *   fire      - tembak meriam (perlu amunisi >0). Combat stat + Cannon
 *               upgrade menentukan akurasi; musuh biasanya balas tembak.
 *   reload    - isi ulang amunisi penuh, TAPI kapal rentan ronde ini
 *               (musuh nyaris pasti menembak duluan) - trade-off klasik
 *               "reload sambil dihujani tembakan".
 *   flee      - coba kabur (Sailing stat + Speed upgrade). Gagal =
 *               kena tembakan tambahan, pertempuran lanjut.
 *   bribe     - suap sesuai HP musuh yang TERSISA (makin lemah musuh,
 *               makin murah nego) - selalu berhasil kalau gold cukup.
 *   negotiate - Negotiation stat. Gagal = bayar upeti kecil, TAPI
 *               pertempuran lanjut (bukan otomatis damai/gagal total).
 *   ram       - taruhan tinggi, SELALU menuntaskan pertempuran di
 *               tempat (menang telak tanpa damage, atau damage sangat
 *               besar kalau gagal).
 *
 * Kalau Condition kapal jatuh ke 0 kapanpun, kapal "tenggelam" - BUKAN
 * game over: emergency rescue balik ke kota asal, Condition dipulihkan
 * ke 25%, sebagian cargo/gold hilang.
 * ------------------------------------------------------------------
 */

var CombatService = (function () {

  function clamp_(n, min, max) { return Math.min(max, Math.max(min, n)); }

  function statBonus_(stat) {
    // Sama filosofi diminishing-returns dengan MarketService: stat/10 = bonus%.
    return Math.min(Number(stat) || 0, 100) / 10;
  }

  /**
   * Dipanggil LocationService SETIAP KALI voyage sudah waktunya tiba
   * dan belum ada PendingEncounter tersimpan. Return null = aman,
   * lanjut arrival normal. Return object = encounter baru, voyage
   * ditahan sampai pemain resolve.
   */
  function rollEncounterForArrival(playerId, loc) {
    var baseChance = getGameConfigNumber_('PirateEncounterBaseChance', 12);
    var ship = ShipService.getShip(playerId);
    var stats = CharacterService.getCharacterStats(playerId) || {};
    var player = PlayerService.getOrCreatePlayer();

    // TooGood = "kota penyamun" - kapal menuju sini HAMPIR PASTI dicegat,
    // dari kota manapun asalnya. Lihat migrateAddCitiesRound2() di
    // SetupSheets.gs untuk konteks kota.
    var headingToOutlawDen = loc && loc.destinationCityId === 'toogood';

    var chance = baseChance;

    // Kapal rusak parah (di bawah DamageThreshold) jadi target empuk.
    var threshold = ShipUpgradeService.getDamageThreshold(playerId);
    if (Number(ship.Condition) < threshold) {
      chance += getGameConfigNumber_('PirateEncounterConditionPenalty', 15);
    }

    // Luck sedikit mengurangi peluang ketemu masalah di laut.
    chance -= statBonus_(stats.Luck) * 1.5;

    // Perk archetype Navigator ("Sea Reader"): -10% peluang sea event berbahaya.
    if (player.archetype === 'navigator') chance *= 0.9;

    chance = clamp_(chance, 1, 60);
    if (headingToOutlawDen) chance = 100;

    if (Math.random() * 100 > chance) return null;

    var levelMax = getGameConfigNumber_('PirateEncounterLevelMax', 5);
    var levelMin = headingToOutlawDen ? 2 : 1; // sarang penyamun = musuh yang lebih berbahaya
    var enemyLevel = levelMin + Math.floor(Math.random() * (levelMax - levelMin + 1));
    var names = ['a lone raider sloop', 'a Bjorneo corsair brig', 'a black-sailed marauder',
      'a notorious pirate frigate', 'a feared warlord\'s flagship'];

    var enemyBaseHp = getGameConfigNumber_('CombatEnemyBaseHp', 40);
    var enemyHpPerLevel = getGameConfigNumber_('CombatEnemyHpPerLevel', 25);
    var enemyMaxHp = enemyBaseHp + enemyLevel * enemyHpPerLevel;
    var maxAmmo = ship.MaxCannonAmmo || getGameConfigNumber_('CombatBaseAmmo', 3);

    return {
      enemyLevel: enemyLevel,
      enemyName: (headingToOutlawDen ? 'TooGood\'s own ' : '') + names[Math.min(enemyLevel, names.length) - 1],
      rolledAt: new Date().toISOString(),
      enemyMaxHp: enemyMaxHp,
      enemyHp: enemyMaxHp,
      maxAmmo: maxAmmo,
      ammoRemaining: maxAmmo,
      round: 1
    };
  }

  function logCombat_(playerId, enemyLevel, action, result, loot) {
    var sheet = SheetCache.getSheet('CombatLog');
    sheet.appendRow([playerId, new Date(), enemyLevel, action, result, loot || '']);
    SheetCache.invalidate('CombatLog');
  }

  /**
   * Hasil SATU pertukaran (ronde) untuk satu taktik. Tidak menyentuh
   * sheet sama sekali - murni kalkulasi, diterapkan oleh resolveCombat().
   */
  function resolveRound_(tactic, encounter, stats, ship, player) {
    var lootPerLevel = getGameConfigNumber_('CombatLootGoldPerLevel', 200);
    var bribePerLevel = getGameConfigNumber_('CombatBribeGoldPerLevel', 150);
    var enemyLevel = encounter.enemyLevel;
    var enemyHpPct = encounter.enemyMaxHp > 0 ? encounter.enemyHp / encounter.enemyMaxHp : 0;
    var roundLabel = 'Ronde ' + encounter.round + ': ';

    if (tactic === 'fire') {
      if (encounter.ammoRemaining <= 0) {
        return { invalidAction: true, message: 'Meriam kosong - reload dulu sebelum menembak lagi.' };
      }

      var chance = 50 + statBonus_(stats.Combat) * 2 + (ship.CannonBonusPercent || 0) - enemyLevel * 5;
      chance = clamp_(chance, 10, 92);
      var hit = Math.random() * 100 < chance;
      var enemyDamage = 0;
      var conditionDelta = 0;
      var msg;

      if (hit) {
        enemyDamage = Math.round(encounter.enemyMaxHp * (0.18 + Math.random() * 0.14));
        msg = roundLabel + 'tembakan meriam menghantam ' + encounter.enemyName + ' telak (-' + enemyDamage + ' HP musuh).';
      } else {
        msg = roundLabel + 'tembakan meriam meleset dari ' + encounter.enemyName + '.';
      }

      var enemyStillAlive = enemyDamage < encounter.enemyHp;
      if (enemyStillAlive && Math.random() < 0.55) {
        conditionDelta = -(4 + Math.floor(Math.random() * 6) + enemyLevel);
        msg += ' Balasan tembakan mereka merobek lambung kapal (' + conditionDelta + ' Condition).';
      }

      return { message: msg, enemyDamage: enemyDamage, conditionDelta: conditionDelta, ammoDelta: -1 };
    }

    if (tactic === 'reload') {
      var conditionDelta2 = 0;
      var msg2 = roundLabel + 'kru buru-buru mengisi ulang meriam.';
      if (Math.random() < 0.75) {
        conditionDelta2 = -(6 + Math.floor(Math.random() * 8) + enemyLevel);
        msg2 += ' Sementara sibuk mengisi ulang, tembakan musuh menghantam kapal (' + conditionDelta2 + ' Condition).';
      } else {
        msg2 += ' Untungnya musuh meleset kali ini.';
      }
      return { message: msg2, reloadToMax: true, conditionDelta: conditionDelta2 };
    }

    if (tactic === 'flee') {
      var speedBonus = (1 - (Number(ship.SpeedMultiplier) || 1)) * 100;
      var fleeChance = 45 + statBonus_(stats.Sailing) * 2 + speedBonus - enemyLevel * 7;
      fleeChance = clamp_(fleeChance, 5, 95);

      if (Math.random() * 100 < fleeChance) {
        return {
          ends: true, endResult: 'fled',
          message: roundLabel + 'manuver tajam & angin bersahabat membawa kapal lolos dari ' + encounter.enemyName + '.'
        };
      }
      var conditionDelta3 = -(5 + Math.floor(Math.random() * 7));
      return {
        message: roundLabel + 'upaya kabur gagal - ' + encounter.enemyName +
          ' mengejar dan sempat menembak (' + conditionDelta3 + ' Condition).',
        conditionDelta: conditionDelta3
      };
    }

    if (tactic === 'bribe') {
      var cost = Math.max(50, Math.round(bribePerLevel * enemyLevel * Math.max(0.25, enemyHpPct)));
      if (player.gold < cost) {
        return { insufficientGold: true, message: 'Gold tidak cukup untuk menyuap (butuh ' + cost + ' gold).' };
      }
      return {
        ends: true, endResult: 'bribed', goldDelta: -cost,
        message: roundLabel + cost + ' gold berpindah tangan, dan ' + encounter.enemyName +
          ' membiarkan kapal lewat tanpa perlawanan lebih lanjut.'
      };
    }

    if (tactic === 'negotiate') {
      var negChance = 40 + statBonus_(stats.Negotiation) * 2.5 - enemyLevel * 6;
      negChance = clamp_(negChance, 5, 90);

      if (Math.random() * 100 < negChance) {
        return {
          ends: true, endResult: 'negotiated',
          message: roundLabel + 'parley tegang di atas air berakhir damai - ' + encounter.enemyName + ' membiarkan kapal berlalu.'
        };
      }
      var toll = Math.min(Math.round(lootPerLevel * enemyLevel * 0.3), player.gold);
      return {
        message: roundLabel + 'parley belum membuahkan hasil - membayar upeti kecil ' + toll + ' gold sekadar menahan mereka sebentar.',
        goldDelta: -toll
      };
    }

    if (tactic === 'ram') {
      var ramChance = 35 + Number(ship.Armor || 0) / 3 + statBonus_(stats.Combat) - enemyLevel * 10;
      ramChance = clamp_(ramChance, 5, 90);

      if (Math.random() * 100 < ramChance) {
        var bigLoot = Math.round(lootPerLevel * enemyLevel * 1.5);
        return {
          ends: true, endResult: 'won', goldDelta: bigLoot, lootNote: bigLoot + ' gold (ram)',
          message: roundLabel + 'manuver menabrak nekat menghancurkan lambung ' + encounter.enemyName +
            ' seketika - kru menjarah ' + bigLoot + ' gold dari puing sebelum tenggelam.'
        };
      }
      var conditionDelta4 = -(22 + Math.floor(Math.random() * 14));
      return {
        ends: true, endResult: 'lost', conditionDelta: conditionDelta4,
        message: roundLabel + 'tabrakan nekat gagal total - benturan yang seharusnya untuk musuh malah dirasakan kapal sendiri.'
      };
    }

    throw new Error('Taktik tidak dikenali: ' + tactic);
  }

  function resolveCombat(tactic) {
    var VALID_TACTICS = ['fire', 'reload', 'flee', 'bribe', 'negotiate', 'ram'];
    if (VALID_TACTICS.indexOf(tactic) === -1) throw new Error('Taktik tidak dikenali: ' + tactic);

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var voyage = LocationService.getVoyageState(playerId);
      if (!voyage.inTransit || !voyage.encounterPending) {
        throw new Error('Tidak ada pertempuran yang sedang menunggu.');
      }

      var encounter = voyage.encounter;
      var stats = CharacterService.getCharacterStats(playerId) || {};
      var ship = ShipService.getShip(playerId);
      var player = PlayerService.getOrCreatePlayer();

      var r = resolveRound_(tactic, encounter, stats, ship, player);

      // Gold tidak cukup / meriam kosong - JANGAN konsumsi ronde, encounter
      // tetap persis seperti semula supaya pemain bisa pilih taktik lain.
      if (r.insufficientGold || r.invalidAction) throw new Error(r.message);

      if (r.goldDelta) {
        PlayerService.updatePlayerRow(playerId, { Gold: Math.max(0, player.gold + r.goldDelta) });
      }
      if (r.cargoLossPercent > 0) {
        CargoService.getCargo(playerId).forEach(function (item) {
          var lost = Math.ceil(item.qty * r.cargoLossPercent);
          if (lost > 0) CargoService.adjustQty(playerId, item.commodityId, -Math.min(lost, item.qty));
        });
      }

      var newCondition = ship.Condition;
      if (r.conditionDelta) {
        newCondition = ShipUpgradeService.applyConditionDelta(playerId, r.conditionDelta);
      }

      if (r.enemyDamage) {
        encounter.enemyHp = Math.max(0, encounter.enemyHp - r.enemyDamage);
      }
      if (r.reloadToMax) {
        encounter.ammoRemaining = encounter.maxAmmo;
      } else if (r.ammoDelta) {
        encounter.ammoRemaining = Math.max(0, Math.min(encounter.maxAmmo, encounter.ammoRemaining + r.ammoDelta));
      }

      var sinking = newCondition <= 0;
      var enemyDefeatedByFire = !r.ends && encounter.enemyHp <= 0;
      var ended = r.ends || sinking || enemyDefeatedByFire;

      if (!ended) {
        encounter.round = (encounter.round || 1) + 1;
        LocationService.updatePendingEncounter(playerId, encounter);
        logCombat_(playerId, encounter.enemyLevel, tactic, 'round', '');

        var goldAfterRound = PlayerService.getOrCreatePlayer().gold;
        return {
          ongoing: true,
          message: r.message,
          encounter: encounter,
          newCondition: ShipService.getShip(playerId).Condition,
          newGold: goldAfterRound
        };
      }

      // --- Pertempuran berakhir di pertukaran ini ---
      var finalMessage = r.message;
      var finalResult = r.endResult || 'unknown';
      var targetCityId = voyage.destinationCityId;

      if (enemyDefeatedByFire) {
        var loot = Math.round(getGameConfigNumber_('CombatLootGoldPerLevel', 200) * encounter.enemyLevel * (0.9 + Math.random() * 0.3));
        var beforeLootGold = PlayerService.getOrCreatePlayer().gold;
        PlayerService.updatePlayerRow(playerId, { Gold: beforeLootGold + loot });
        finalMessage = r.message + ' Tembakan itu ternyata mematikan - ' + encounter.enemyName +
          ' tenggelam dan kru menjarah ' + loot + ' gold dari puing kapal sebelum berlayar lagi.';
        finalResult = 'won';
      }

      if (sinking) {
        var effectiveMax = ShipService.getShip(playerId).EffectiveMaxCondition;
        ShipUpgradeService.applyConditionDelta(playerId, effectiveMax * 0.25);

        var freshPlayer = PlayerService.getOrCreatePlayer();
        var goldPenalty = Math.round(freshPlayer.gold * 0.15);
        if (goldPenalty > 0) PlayerService.updatePlayerRow(playerId, { Gold: freshPlayer.gold - goldPenalty });

        CargoService.getCargo(playerId).forEach(function (item) {
          var lost = Math.ceil(item.qty * 0.5);
          if (lost > 0) CargoService.adjustQty(playerId, item.commodityId, -Math.min(lost, item.qty));
        });

        targetCityId = voyage.originCityId;
        finalMessage = 'The ship went down under ' + encounter.enemyName + '\'s assault after ' + encounter.round +
          ' rounds of fighting! A passing fisherman pulled the crew from the wreckage and towed you back, ' +
          'but half the cargo and ' + goldPenalty + ' gold were lost to the sea.';
        finalResult = 'sunk';
      }

      // Fase 5: kemenangan combat (fire/ram) punya peluang menjatuhkan
      // treasure map, terpisah dari loot gold yang sudah ada di atas.
      var mapDropNote = '';
      if (finalResult === 'won') {
        var dropChance = getGameConfigNumber_('TreasureMapDropChance', 15);
        if (Math.random() * 100 < dropChance) {
          var mapItemId = TreasureService.pickRandomMapItemId_();
          if (mapItemId) {
            ItemService.grantItem(playerId, mapItemId, 1);
            var mapItem = ItemService.getItemById(mapItemId);
            mapDropNote = ' Among the wreckage, the crew salvages ' + (mapItem ? mapItem.Name : 'a weathered map') + '!';
            finalMessage += mapDropNote;
          }
        }
      }

      var result = LocationService.finalizeArrival(playerId, targetCityId, finalMessage);
      logCombat_(playerId, encounter.enemyLevel, tactic, finalResult, (r.lootNote || '') + mapDropNote);

      return {
        ongoing: false,
        success: finalResult === 'won' || finalResult === 'fled' || finalResult === 'bribed' || finalResult === 'negotiated',
        result: finalResult,
        message: finalMessage,
        cityId: result.cityId,
        newCondition: ShipService.getShip(playerId).Condition,
        newGold: PlayerService.getOrCreatePlayer().gold,
        // Fase 5: dipakai layar ringkasan pasca-battle di client (lihat
        // renderBattleSummary_() di JavaScript.html) - null kalau tidak
        // ada drop ronde ini.
        lootItem: (typeof mapItem !== 'undefined' && mapItem) ? { itemId: mapItemId, name: mapItem.Name } : null
      };
    } finally {
      lock.releaseLock();
    }
  }

  return {
    rollEncounterForArrival: rollEncounterForArrival,
    resolveCombat: resolveCombat
  };
})();
