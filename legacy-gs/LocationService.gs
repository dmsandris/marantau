/**
 * LocationService.gs
 * ------------------------------------------------------------------
 * Fitur "Set Sail": travel BERDURASI, dihitung dari jarak antar kota
 * di peta (Cities.MapX/MapY) dibagi stat Speed kapal (+ SpeedMultiplier
 * dari Ship Upgrade Fase 3a), mengikuti skala waktu dunia yang sudah
 * ada (1 jam nyata = 1 hari-game).
 *
 * State pelayaran disimpan di PlayerLocation:
 *   PlayerId, CurrentCityId, ArrivedGameDay, DestinationCityId, DepartAt,
 *   ArriveAt, PendingEncounter
 * DestinationCityId KOSONG = tidak sedang berlayar.
 *
 * Fase 3b (Combat): begitu waktu tiba (now >= ArriveAt), SEBELUM voyage
 * benar-benar diselesaikan, kita roll peluang pirate encounter (lihat
 * CombatService.gs). Kalau kena, PendingEncounter diisi JSON berisi
 * data musuh dan voyage TIDAK diselesaikan (kapal dianggap masih di
 * tengah laut, "dicegat") sampai pemain memilih taktik lewat
 * api_resolveCombat() - yang pada akhirnya memanggil finalizeArrival()
 * di sini. Kalau tidak kena encounter, voyage diselesaikan langsung
 * seperti biasa (roll flavor event ringan + decay Condition per Fase 3c).
 * ------------------------------------------------------------------
 */

var LocationService = (function () {

  function getConfigNumber_(key, fallback) {
    var raw = getGameConfigValue_(key);
    var num = Number(raw);
    return raw !== null && raw !== '' && !isNaN(num) ? num : fallback;
  }

  function clampNumber_(n, min, max) {
    return Math.min(max, Math.max(min, n));
  }

  function getCurrentCityId(playerId) {
    var loc = getLocationRow_(playerId);
    return loc ? loc.cityId : 'sunda_empire';
  }

  function getLocationRow_(playerId) {
    var data = SheetCache.getData('PlayerLocation');
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        return {
          rowIndex: i + 1,
          cityId: data[i][1],
          arrivedGameDay: data[i][2],
          destinationCityId: data[i][3] || '',
          departAt: data[i][4] || '',
          arriveAt: data[i][5] || '',
          pendingEncounterRaw: data[i][6] || ''
        };
      }
    }
    return null;
  }

  function parsePendingEncounter_(loc) {
    if (!loc || !loc.pendingEncounterRaw) return null;
    try {
      return JSON.parse(loc.pendingEncounterRaw);
    } catch (e) {
      return null;
    }
  }

  /** Dipakai CombatService untuk baca encounter yang sedang menunggu resolusi. */
  function getPendingEncounter(playerId) {
    var loc = getLocationRow_(playerId);
    return parsePendingEncounter_(loc);
  }

  /** Dipakai CombatService untuk menyimpan encounter baru begitu voyage "dicegat". */
  function setPendingEncounter_(loc, encounter) {
    var sheet = SheetCache.getSheet('PlayerLocation');
    sheet.getRange(loc.rowIndex, 7).setValue(JSON.stringify(encounter));
    SheetCache.invalidate('PlayerLocation');
  }

  /**
   * Dipakai CombatService untuk menulis balik state encounter yang sudah
   * berubah (HP musuh berkurang, amunisi terpakai, dst) SETELAH satu ronde
   * combat diproses tapi pertempuran belum selesai - voyage tetap ditahan.
   */
  function updatePendingEncounter(playerId, encounter) {
    var loc = getLocationRow_(playerId);
    if (!loc || !loc.destinationCityId) throw new Error('Tidak ada voyage aktif untuk di-update encounter-nya.');
    setPendingEncounter_(loc, encounter);
  }

  /**
   * Status pelayaran pemain saat ini buat ditampilkan di client (progress
   * bar, ETA, banner combat, dst). Read-only, tidak mengubah data apapun.
   */
  function getVoyageState(playerId) {
    var loc = getLocationRow_(playerId);
    if (!loc || !loc.destinationCityId) {
      return { inTransit: false };
    }

    var now = Date.now();
    var departMs = new Date(loc.departAt).getTime();
    var arriveMs = new Date(loc.arriveAt).getTime();
    var totalMs = Math.max(1, arriveMs - departMs);
    var progress = Math.min(1, Math.max(0, (now - departMs) / totalMs));

    var encounter = parsePendingEncounter_(loc);

    return {
      inTransit: true,
      originCityId: loc.cityId,
      destinationCityId: loc.destinationCityId,
      departAt: loc.departAt,
      arriveAt: loc.arriveAt,
      progress: progress,
      etaSeconds: Math.max(0, Math.round((arriveMs - now) / 1000)),
      encounterPending: !!encounter,
      encounter: encounter || null
    };
  }

  /**
   * Kalau pemain sedang berlayar dan sudah waktunya tiba, selesaikan
   * voyage - KECUALI kalau terkena pirate encounter, di mana voyage
   * ditahan sampai pemain menyelesaikan combat (lihat CombatService.gs).
   */
  function resolveArrivalIfDue(playerId) {
    var loc = getLocationRow_(playerId);
    if (!loc || !loc.destinationCityId) return null;

    var existingEncounter = parsePendingEncounter_(loc);
    if (existingEncounter) {
      // Sudah dicegat sebelumnya, masih menunggu pemain memilih taktik -
      // jangan roll ulang, jangan selesaikan voyage.
      return { cityId: null, event: null, pendingCombat: true, encounter: existingEncounter };
    }

    if (Date.now() < new Date(loc.arriveAt).getTime()) return null;

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      // Baca ulang setelah dapat lock - siapa tahu request lain (mis. tab
      // browser lain) sudah menyelesaikan voyage yang sama duluan.
      loc = getLocationRow_(playerId);
      if (!loc || !loc.destinationCityId) return null;

      existingEncounter = parsePendingEncounter_(loc);
      if (existingEncounter) return { cityId: null, event: null, pendingCombat: true, encounter: existingEncounter };
      if (Date.now() < new Date(loc.arriveAt).getTime()) return null;

      // Roll pirate encounter SEBELUM voyage diselesaikan (Fase 3b).
      var rolled = CombatService.rollEncounterForArrival(playerId, loc);
      if (rolled) {
        setPendingEncounter_(loc, rolled);
        LogService.addLog(playerId, 'Sails spotted on the horizon - a pirate vessel closes in!');
        return { cityId: null, event: null, pendingCombat: true, encounter: rolled };
      }

      return completeArrival_(playerId, loc, loc.destinationCityId, null);
    } finally {
      lock.releaseLock();
    }
  }

  /**
   * Selesaikan voyage secara aktual: pindah kota, roll flavor event
   * ringan (kalau bukan hasil combat), terapkan decay Condition per
   * sail (Fase 3c), bersihkan status transit + pending encounter.
   * `combatResultMessage` diisi CombatService kalau finalisasi ini
   * dipicu SETELAH combat (menggantikan flavor event acak biasa).
   */
  function completeArrival_(playerId, loc, targetCityId, combatResultMessage) {
    var destCity = getCityById(targetCityId);
    if (!destCity) throw new Error('Kota tujuan tidak dikenali: ' + targetCityId);

    var event = combatResultMessage ? { message: combatResultMessage, goldDelta: 0 } : rollVoyageEvent_();

    var sheet = SheetCache.getSheet('PlayerLocation');
    sheet.getRange(loc.rowIndex, 2).setValue(targetCityId);
    sheet.getRange(loc.rowIndex, 3).setValue(TimeService.getCurrentGameDay());
    sheet.getRange(loc.rowIndex, 4).setValue('');
    sheet.getRange(loc.rowIndex, 5).setValue('');
    sheet.getRange(loc.rowIndex, 6).setValue('');
    sheet.getRange(loc.rowIndex, 7).setValue('');
    SheetCache.invalidate('PlayerLocation');

    if (event.goldDelta) {
      var player = PlayerService.getOrCreatePlayer();
      PlayerService.updatePlayerRow(playerId, { Gold: Math.max(0, player.gold + event.goldDelta) });
    }

    // Fase 3c: setiap voyage yang selesai (damai atau setelah combat)
    // mengikis sedikit Condition kapal, dipotong bonus upgrade decay.
    var decay = ShipUpgradeService.getConditionDecayForVoyage(playerId);
    if (decay > 0) ShipUpgradeService.applyConditionDelta(playerId, -decay);

    // Fase 6: peluang kecil memicu World Event baru di kota tujuan -
    // dibungkus try/catch supaya event dunia TIDAK PERNAH bisa
    // menggagalkan penyelesaian voyage pemain walau ada error di sana.
    try { WorldEventService.maybeRollCityEvent_(targetCityId); } catch (e) { /* diam-diam - lihat catatan di WorldEventService.gs */ }

    LogService.addLog(playerId, 'Made landfall at ' + destCity.Name + '. ' + event.message);

    return { cityId: targetCityId, event: event, pendingCombat: false };
  }

  /** Dipanggil CombatService setelah combat selesai untuk menuntaskan voyage. */
  function finalizeArrival(playerId, targetCityId, resultMessage) {
    var loc = getLocationRow_(playerId);
    if (!loc || !loc.destinationCityId) throw new Error('Tidak ada voyage aktif untuk diselesaikan.');
    return completeArrival_(playerId, loc, targetCityId, resultMessage);
  }

  /**
   * Random event ringan di tengah laut (versi damai, non-combat) -
   * pirate sighting yang sungguhan sekarang ditangani terpisah lewat
   * CombatService (Fase 3b), jadi daftar di sini murni cuaca/nasib baik.
   */
  function rollVoyageEvent_() {
    var roll = Math.random();
    if (roll < 0.65) {
      return { type: 'calm', message: 'Laut tenang sepanjang perjalanan.', goldDelta: 0 };
    } else if (roll < 0.85) {
      var bonus = 10 + Math.floor(Math.random() * 40);
      return {
        type: 'tailwind',
        message: 'Angin buritan bersahabat - kru sempat memancing di sela pelayaran dan menjual ' +
          'hasilnya (+' + bonus + ' gold).',
        goldDelta: bonus
      };
    } else {
      var loss = 10 + Math.floor(Math.random() * 30);
      return {
        type: 'storm',
        message: 'Diterjang badai kecil - sedikit kerusakan ringan pada kapal (-' + loss + ' gold ' +
          'untuk perbaikan darurat).',
        goldDelta: -loss
      };
    }
  }

  function mapDistance_(cityA, cityB) {
    var dx = Number(cityA.MapX) - Number(cityB.MapX);
    var dy = Number(cityA.MapY) - Number(cityB.MapY);
    return Math.sqrt(dx * dx + dy * dy);
  }

  function computeTravelMinutes_(distance, ship) {
    var minutesPerUnit = getConfigNumber_('TravelMinutesPerDistanceUnit', 0.25);
    var minTravelMinutes = getConfigNumber_('MinTravelMinutes', 5);
    var baselineSpeed = getConfigNumber_('BaselineShipSpeed', 50);
    var speedFactor = clampNumber_(Number(ship.Speed || baselineSpeed) / baselineSpeed, 0.5, 2.5);
    var baseMinutes = (distance * minutesPerUnit) / speedFactor;

    // Fase 3a: Speed upgrade memangkas waktu tempuh lewat SpeedMultiplier
    // (mis. 0.65 = 35% lebih cepat) - dikalikan setelah faktor stat dasar.
    var speedMultiplier = Number(ship.SpeedMultiplier) || 1;
    return Math.max(minTravelMinutes, Math.round(baseMinutes * speedMultiplier));
  }

  /**
   * Daftar semua kota lain beserta jarak & estimasi waktu tempuh dari
   * posisi pemain SAAT INI - dipakai panel Set Sail buat menampilkan
   * pilihan sebelum pemain commit berlayar.
   */
  function getSailOptions(playerId) {
    var loc = getLocationRow_(playerId);
    if (!loc) throw new Error('Data lokasi pemain tidak ditemukan.');

    var originCity = getCityById(loc.cityId);
    if (!originCity) throw new Error('Kota asal tidak dikenali: ' + loc.cityId);

    var ship = ShipService.getShip(playerId);
    var cities = WorldService.getCities();

    return cities
      .filter(function (c) { return c.CityId !== loc.cityId; })
      .map(function (c) {
        var distance = mapDistance_(originCity, c);
        var event = WorldEventService.getActiveEventForCity(c.CityId);
        return {
          cityId: c.CityId,
          name: c.Name,
          distance: Math.round(distance * 10) / 10,
          etaMinutes: computeTravelMinutes_(distance, ship),
          // Fase 6: kasih sinyal ke pemain SEBELUM berlayar - kota tujuan
          // lagi ada apa (Panen Melimpah = saat bagus buat belanja, dst).
          eventLabel: event ? event.label : null,
          eventType: event ? event.eventType : null
        };
      });
  }

  /** Mulai pelayaran menuju kota lain - menggantikan travel instan Fase 1. */
  function setSail(destinationCityId) {
    var destCity = getCityById(destinationCityId);
    if (!destCity) throw new Error('Kota tujuan tidak dikenali: ' + destinationCityId);

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);

    try {
      var playerId = PlayerService.getCurrentPlayerId();

      // Selesaikan dulu voyage lama kalau kebetulan sudah waktunya tiba,
      // supaya tidak "menimpa" perjalanan yang belum di-resolve.
      resolveArrivalIfDue(playerId);

      var loc = getLocationRow_(playerId);
      if (!loc) throw new Error('Data lokasi pemain tidak ditemukan.');
      if (parsePendingEncounter_(loc)) {
        throw new Error('Kapal sedang dicegat bajak laut - selesaikan pertempuran dulu sebelum berlayar lagi.');
      }
      if (loc.destinationCityId) throw new Error('Kamu sudah dalam perjalanan menuju kota lain.');
      if (loc.cityId === destinationCityId) throw new Error('Kamu sudah berada di kota ini.');

      var originCity = getCityById(loc.cityId);
      if (!originCity) throw new Error('Kota asal tidak dikenali: ' + loc.cityId);

      var distance = mapDistance_(originCity, destCity);
      var ship = ShipService.getShip(playerId);
      var travelRealMinutes = computeTravelMinutes_(distance, ship);

      var departAt = new Date();
      var arriveAt = new Date(departAt.getTime() + travelRealMinutes * 60000);

      var sheet = SheetCache.getSheet('PlayerLocation');
      sheet.getRange(loc.rowIndex, 4).setValue(destinationCityId);
      sheet.getRange(loc.rowIndex, 5).setValue(departAt.toISOString());
      sheet.getRange(loc.rowIndex, 6).setValue(arriveAt.toISOString());
      SheetCache.invalidate('PlayerLocation');

      LogService.addLog(playerId, 'Set sail from ' + originCity.Name + ' toward ' + destCity.Name + '.');

      return {
        originCityId: loc.cityId,
        destinationCityId: destinationCityId,
        departAt: departAt.toISOString(),
        arriveAt: arriveAt.toISOString(),
        travelRealMinutes: travelRealMinutes
      };
    } finally {
      lock.releaseLock();
    }
  }

  function getCityById(cityId) {
    var cities = WorldService.getCities();
    for (var i = 0; i < cities.length; i++) {
      if (cities[i].CityId === cityId) return cities[i];
    }
    return null;
  }

  return {
    getCurrentCityId: getCurrentCityId,
    getVoyageState: getVoyageState,
    resolveArrivalIfDue: resolveArrivalIfDue,
    getSailOptions: getSailOptions,
    setSail: setSail,
    getCityById: getCityById,
    getPendingEncounter: getPendingEncounter,
    updatePendingEncounter: updatePendingEncounter,
    finalizeArrival: finalizeArrival
  };
})();
