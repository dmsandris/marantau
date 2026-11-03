// Kalibrasi Perburuan Tony (Tide v47): banyak serbuan bot melawan armada Tony, ringkas peluang menang.
// Pemakaian: node tools/sim-tony.js [jumlahPerSkenario=10] [skenario: 4avg,3avg,2good,2poor]
// Target (KONSEP-Perburuan-Tony.md): 4avg 55-65%, 3avg 30-40%, 2good 10-15%, 2poor ~3%.
const path = require('path');
const bot = require(path.join(__dirname, '..', 'test', 'raidbot'));
const N = Number(process.argv[2] || 10);
const ONLY = (process.argv[3] || '').split(',').filter(Boolean);
// kapal & stat per tingkat kapten
const AVG = { tier: 'IV', combat: 60 }, GOOD = { tier: 'V', combat: 80 }, POOR = { tier: 'III', combat: 40 };
const SCEN = { '4avg': [AVG, AVG, AVG, AVG], '3avg': [AVG, AVG, AVG], '2good': [GOOD, GOOD], '2poor': [POOR, POOR] };
(async () => {
  const H = await require(path.join(__dirname, '..', 'test', 'harness')).create();
  await H.sql(`update game.config set value = 'on' where key = 'TonyHuntForce'`);
  let uid = 0;
  const kapten = async (p) => {
    const name = 'tsim' + (++uid);
    const c = await H.user(name); await c.call('api_createCharacter', [name, 'pirate']);
    const pid = c.id;
    await H.sql(`update game.ships set tier = $2, cargo = 5000, condition = 100 where player_id = $1`, [pid, p.tier]);
    await H.sql(`update game.character_stats set combat = $2, luck = 40, sailing = 50, navigation = 50, knowledge = 30, negotiation = 50 where player_id = $1`, [pid, p.combat]);
    await H.sql(`update game.players set meta = jsonb_build_object('u', (select jsonb_object_agg('b' || g, 1) from generate_series(1, 25) g)) where player_id = $1`, [pid]);
    await H.sql(`update game.player_location set city_id = 'kabut_abu' where player_id = $1`, [pid]);
    await H.sql(`select game.adjust_inventory($1, 'mesiu', 3000)`, [pid]);
    const pub = (await c.call('api_mpPulse', [{}])).mePub;
    return { c, pid, pub };
  };
  for (const [key, list] of Object.entries(SCEN)) {
    if (ONLY.length && !ONLY.includes(key)) continue;
    const crew = [];
    for (const p of list) crew.push(await kapten(p));
    let wins = 0, finals = 0, turns = 0, fb = [], dur = [];
    for (let i = 0; i < N; i++) {
      await H.sql(`delete from game.tony_hunts`);
      for (const u of crew) await H.sql(`update game.ships set condition = 100 where player_id = $1`, [u.pid]);
      let r = (await crew[0].c.call('api_tonyHunt', ['open'])).raid;
      for (const u of crew.slice(1)) await u.c.call('api_tonyHunt', ['join', r.id]);
      for (const u of crew) await u.c.call('api_tonyHunt', ['ready', true]);
      await crew[0].c.call('api_tonyHunt', ['depart']);
      const t0 = Number((await H.sql(`select game.dt_now() t`))[0].t);
      const res = await bot.runRaid(H, crew.map(u => ({ c: u.c, pub: u.pub })), { skill: 0.85, api: 'api_tonyHunt' });
      const t1 = Number((await H.sql(`select game.dt_now() t`))[0].t);
      if (res.result === 'win') wins++;
      if (res.finalBoss != null) { finals++; fb.push(Math.round(res.finalBoss)); }
      turns += res.turns; dur.push(Math.round((t1 - t0) / 60000 * 10) / 10);
      if (process.env.V) console.log(res.result, res.turns, JSON.stringify(res.fire), JSON.stringify(res.log.filter((x, j) => j % 4 === 0).map(x => [x.r, x.boss, x.sh, x.p])), JSON.stringify(res.card.rows.map(r => [r.hull, r.shield, r.taken, r.endHull])));
      process.stdout.write(res.result === 'win' ? 'W' : (res.finalBoss != null ? 'f' : 'x'));
    }
    console.log(`\n${key}: menang ${wins}/${N} (${Math.round(wins / N * 100)}%), sampai final ${finals}/${N}, giliran rata2 ${(turns / N).toFixed(1)}, HP saat final ${JSON.stringify(fb)}, menit ${JSON.stringify(dur)}`);
  }
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
