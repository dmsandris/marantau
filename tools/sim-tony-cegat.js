// Kalibrasi pencegatan Tony and Gank (Tide v67): peluang memukul mundur Tony (HP armada <= TonyKaburPct).
// Pemakaian: node tools/sim-tony-cegat.js [jumlahPerSkenario=300] [combat=60] [TonyCegatDmgKali]
// Target: Warlord lengkap (4/4, semua mentok, Combat rata-rata) sekitar 25%; tanpa Meriam Warlord praktis 0%.
// Taktik bot: tembak selama ada amunisi, isi ulang bila kosong. Kapal berangkat dengan kondisi penuh.
// 'mesiu' = menang lama lewat gudang mesiu (TonyPowderChance), dihitung terpisah dari 'kabur'.
const path = require('path');
const N = Number(process.argv[2] || 300), COMBAT = Number(process.argv[3] || 60), KALI = process.argv[4];
const SCEN = {
  'mentok tanpa Warlord': [],
  'Meriam Warlord saja': ['cannons'],
  'Warlord lengkap': ['speed', 'cargo', 'condition', 'cannons']
};
(async () => {
  const H = await require(path.join(__dirname, '..', 'test', 'harness')).create();
  if (KALI) await H.sql(`update game.config set value = $1 where key = 'TonyCegatDmgKali'`, [KALI]);
  await H.sql(`insert into game.tony_raid(dest_city, start_at, end_at, chance, kabar, announce_victims)
               values ('toogood', now() - interval '1 hour', now() + interval '20 hours', 100, 'diam', false)`);
  const mentok = `jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0)`;
  let uid = 0;
  for (const [nama, wl] of Object.entries(SCEN)) {
    const name = 'csim' + (++uid);
    const c = await H.user(name); await c.call('api_createCharacter', [name, 'merchant']);
    await H.sql(`update game.players set ship_upgrades = jsonb_build_object('speed', ${mentok}, 'cargo', ${mentok},
      'condition', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 1996), 'cannons', ${mentok}) where player_id = $1`, [c.id]);
    await H.sql(`update game.character_stats set combat = $2 where player_id = $1`, [c.id, COMBAT]);
    for (const g of wl) await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, $2)`, [c.id, g]);
    const sh = (await H.sql(`select game.ship_json($1) j`, [c.id]))[0].j;
    const out = { repelled: 0, won: 0, robbed: 0 }; let ronde = 0, sisa = 0;
    for (let i = 0; i < N; i++) {
      await H.sql(`delete from game.tony_victims`);
      await H.sql(`update game.ships set condition = $2 where player_id = $1`, [c.id, sh.EffectiveMaxCondition]);
      await H.sql(`update game.player_location set city_id = 'sunda_empire', destination_city_id = 'toogood', depart_at = now() - interval '2 minutes',
                   arrive_at = now() - interval '1 second', pending_encounter = null where player_id = $1`, [c.id]);
      await H.sql(`update game.player_location set pending_encounter = game.tony_roll($1) where player_id = $1`, [c.id]);
      let ammo = Number(sh.MaxCannonAmmo), r, hp = 4000;
      for (let k = 0; k < 60; k++) {
        r = await c.call('api_tonyRaid', [ammo > 0 ? 'fire' : 'reload']);
        if (!r.ongoing) break;
        ammo = Number(r.encounter.ammoRemaining); hp = Number(r.encounter.enemyHp);
        ronde++;
      }
      out[r.result] = (out[r.result] || 0) + 1;
      if (r.result === 'robbed') sisa += hp;
    }
    const pct = (n) => (n / N * 100).toFixed(1) + '%';
    console.log(`${nama} (damage x${sh.CannonDmgMul}, kondisi maks ${sh.EffectiveMaxCondition}, amunisi ${sh.MaxCannonAmmo}, Combat ${COMBAT}): ` +
      `Tony kabur ${out.repelled}/${N} (${pct(out.repelled)}), gudang mesiu ${out.won}/${N} (${pct(out.won)}), dirampas ${out.robbed}/${N} (${pct(out.robbed)}), ` +
      `HP armada rata-rata saat dirampas ${out.robbed ? Math.round(sisa / out.robbed) : '-'}`);
  }
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
