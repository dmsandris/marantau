/**
 * ShipService.gs
 * ------------------------------------------------------------------
 * Fase 1: hanya baca data kapal (upgrade & equipment menyusul Fase 3).
 * Fase 2: kapasitas cargo efektif bisa ditambah oleh buku dengan
 * SpecialEffect 'cargo_bonus_10' (lihat BookService.gs) - dihitung di
 * sini secara dinamis (EffectiveCargo), TIDAK mengubah nilai Ship.Cargo
 * asli di sheet, supaya sumber kebenarannya tetap satu (base stat kapal)
 * dan bonus dari buku selalu konsisten meski kapal di-upgrade/diganti
 * nanti di Fase 3.
 *
 * Fase 3a/3c: ditambah stat efektif dari ShipUpgradeService (cargo
 * upgrade, speed multiplier, max condition, decay reduction, cannon
 * bonus) - SEMUA dihitung dinamis di sini juga (sama filosofinya
 * dengan bonus buku), supaya Ship.Cargo/Condition di sheet tetap jadi
 * SATU sumber kebenaran untuk base stat.
 *
 * PERFORMANCE: baca sheet lewat SheetCache.gs (getShip() dipanggil
 * berkali-kali per request - state.ship, Market, Warehouse, Set Sail).
 * ------------------------------------------------------------------
 */

var ShipService = (function () {

  function getShip(playerId) {
    var data = SheetCache.getData('Ship');
    var headers = data[0];

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        var ship = {};
        headers.forEach(function (h, idx) { ship[h] = data[i][idx]; });

        // Fase 5: artifact terpasang (ShipEquipment) bisa memberi keyword efek
        // yang SAMA dengan buku (mis. 'cargo_bonus_10') - dicek di sini juga
        // supaya sumbernya tidak duplikat-hitung (buku ATAU artifact, bukan keduanya).
        var hasCargoBonus = BookService.hasSpecialEffect(playerId, 'cargo_bonus_10') ||
          ItemService.hasEquippedEffect(playerId, 'cargo_bonus_10');
        var bookCargoBonus = hasCargoBonus ? 10 : 0;
        var upgradeStats = ShipUpgradeService.getEffectiveShipStats(playerId);

        ship.CargoBonus = bookCargoBonus + upgradeStats.cargoBonus;
        ship.EffectiveCargo = Number(ship.Cargo) + ship.CargoBonus;

        ship.SpeedMultiplier = upgradeStats.speedMultiplier;
        ship.CannonBonusPercent = upgradeStats.cannonBonusPercent;
        ship.MaxCannonAmmo = getGameConfigNumber_('CombatBaseAmmo', 3) + upgradeStats.cannonAmmoBonus;
        ship.ShipUpgrades = upgradeStats.upgrades;

        var baseMaxCondition = 100;
        ship.EffectiveMaxCondition = baseMaxCondition + upgradeStats.maxConditionBonus;
        var rawCondition = Number(ship.Condition);
        if (isNaN(rawCondition)) rawCondition = ship.EffectiveMaxCondition;
        ship.Condition = Math.min(rawCondition, ship.EffectiveMaxCondition);
        ship.ConditionPct = ship.EffectiveMaxCondition > 0
          ? Math.round((ship.Condition / ship.EffectiveMaxCondition) * 100) : 100;
        ship.DecayReductionPercent = upgradeStats.decayReductionPercent;

        return ship;
      }
    }
    return null;
  }

  return { getShip: getShip };
})();
