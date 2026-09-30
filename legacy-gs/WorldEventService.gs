/**
 * WorldEventService.gs — Fase 6 (World Expansion & Events)
 * ------------------------------------------------------------------
 * Event dunia per-KOTA (bukan per-pemain) - shared world, semua orang
 * yang berlabuh di kota itu melihat & merasakan efek yang sama. Dua
 * kategori sesuai roadmap:
 *   - EKONOMI: 'storm_surge' (harga naik sementara) / 'harvest_bounty'
 *     (harga turun sementara) - dibaca MarketService.gs.
 *   - SOSIAL: 'festival' (reward misi naik) / 'unrest' (reward misi
 *     turun) - dibaca MissionService.gs.
 *
 * Sheet baru `CityEvents` (lihat migrateFase6WorldEvents() di
 * SetupSheets.gs): CityId, EventType, Label, Message,
 * PriceMultiplierPercent, RewardMultiplierPercent, ExpiresGameDay.
 * Satu kota cuma boleh punya SATU event aktif sekaligus (tidak overlap)
 * - baris lama yang sudah kedaluwarsa (ExpiresGameDay < hari ini)
 * diabaikan begitu saja saat dibaca, TIDAK dihapus (housekeeping
 * manual, volume kecil untuk game seukuran ini).
 *
 * GRACEFUL DEGRADATION (pola sama dengan BankService/ShipUpgradeService):
 * kalau sheet CityEvents belum ada (migrasi belum jalan), semua fungsi
 * di sini diam-diam mengembalikan "tidak ada event" alih-alih throw -
 * supaya TIDAK merusak Market/Mission/voyage completion untuk siapapun
 * yang belum update.
 * ------------------------------------------------------------------
 */

var WORLD_EVENT_TYPES = [
  {
    type: 'storm_surge', label: 'Gelombang Badai', weight: 25,
    message: function () { return 'Badai musiman mengganggu jalur pasokan - harga di pasar melonjak sementara.'; },
    price: function () { return 15 + Math.floor(Math.random() * 11); }, // +15..+25
    reward: function () { return 0; }
  },
  {
    type: 'harvest_bounty', label: 'Panen Melimpah', weight: 25,
    message: function () { return 'Panen melimpah membanjiri pasar - harga turun sementara, saat yang tepat untuk berbelanja.'; },
    price: function () { return -(15 + Math.floor(Math.random() * 11)); }, // -15..-25
    reward: function () { return 0; }
  },
  {
    type: 'festival', label: 'Festival Kota', weight: 25,
    message: function () { return 'Kota sedang berpesta - gubernur murah hati memberi upah lebih besar untuk misi.'; },
    price: function () { return 0; },
    reward: function () { return 20 + Math.floor(Math.random() * 21); } // +20..+40
  },
  {
    type: 'unrest', label: 'Kerusuhan Kecil', weight: 25,
    message: function () { return 'Kerusuhan kecil melanda kota - aktivitas dagang & misi lesu untuk sementara.'; },
    price: function () { return 0; },
    reward: function () { return -(15 + Math.floor(Math.random() * 16)); } // -15..-30
  }
];

var WorldEventService = (function () {
  var SHEET_NAME = 'CityEvents';

  function getActiveEventForCity(cityId) {
    var sheet = SheetCache.getSheet(SHEET_NAME);
    if (!sheet) return null; // belum migrasi - graceful degradation

    var data = SheetCache.getData(SHEET_NAME);
    var today = TimeService.getCurrentGameDay();

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === cityId && Number(data[i][6]) >= today) {
        return {
          cityId: data[i][0],
          eventType: data[i][1],
          label: data[i][2],
          message: data[i][3],
          priceMultiplierPercent: Number(data[i][4]) || 0,
          rewardMultiplierPercent: Number(data[i][5]) || 0,
          expiresGameDay: Number(data[i][6])
        };
      }
    }
    return null;
  }

  function getPriceMultiplierPercent(cityId) {
    var ev = getActiveEventForCity(cityId);
    return ev ? ev.priceMultiplierPercent : 0;
  }

  function getRewardMultiplierPercent(cityId) {
    var ev = getActiveEventForCity(cityId);
    return ev ? ev.rewardMultiplierPercent : 0;
  }

  function pickWeighted_(list) {
    var total = list.reduce(function (s, x) { return s + x.weight; }, 0);
    var roll = Math.random() * total;
    for (var i = 0; i < list.length; i++) {
      roll -= list[i].weight;
      if (roll <= 0) return list[i];
    }
    return list[list.length - 1];
  }

  /**
   * Dipanggil LocationService.completeArrival_() tiap kali voyage
   * SELESAI (damai maupun setelah combat) - peluang kecil memicu event
   * baru di kota TUJUAN, kalau kota itu belum punya event aktif. Boleh
   * gagal diam-diam (try/catch di sisi pemanggil) - event dunia TIDAK
   * BOLEH sampai menggagalkan penyelesaian voyage pemain.
   */
  function maybeRollCityEvent_(cityId) {
    var sheet = SheetCache.getSheet(SHEET_NAME);
    if (!sheet) return; // belum migrasi - skip diam-diam

    if (getActiveEventForCity(cityId)) return; // sudah ada event aktif, jangan overlap

    var chance = getGameConfigNumber_('WorldEventRollChancePercent', 10);
    if (Math.random() * 100 >= chance) return;

    var picked = pickWeighted_(WORLD_EVENT_TYPES);
    var minDur = getGameConfigNumber_('WorldEventMinDurationDays', 2);
    var maxDur = getGameConfigNumber_('WorldEventMaxDurationDays', 5);
    var duration = minDur + Math.floor(Math.random() * (maxDur - minDur + 1));
    var expiresGameDay = TimeService.getCurrentGameDay() + duration;

    sheet.appendRow([cityId, picked.type, picked.label, picked.message(), picked.price(), picked.reward(), expiresGameDay]);
    SheetCache.invalidate(SHEET_NAME);
  }

  return {
    getActiveEventForCity: getActiveEventForCity,
    getPriceMultiplierPercent: getPriceMultiplierPercent,
    getRewardMultiplierPercent: getRewardMultiplierPercent,
    maybeRollCityEvent_: maybeRollCityEvent_
  };
})();
