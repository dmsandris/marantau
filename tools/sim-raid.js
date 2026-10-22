// Kalibrasi Serbuan Bersama (Quest 9): jalankan banyak serbuan bot dan ringkas peluang menang.
// Pemakaian: node tools/sim-raid.js [jumlahPerSkenario=10] [skenario: 4avg,3avg,2good,2poor]
const path = require('path');
const bot = require(path.join(__dirname, '..', 'test', 'raidbot'));
const N = Number(process.argv[2] || 10);
const ONLY = (process.argv[3] || '').split(',').filter(Boolean);
const AVG = { hookGrade: 'baik', beads: 3, hasiolan: 'percaya', jejakOk: true, drumBest: 65 };
const AVG2 = { hookGrade: 'kasar', beads: 3, hasiolan: 'ambil', jejakOk: false, drumBest: 65 };
const GOOD = { hookGrade: 'sempurna', beads: 5, hasiolan: 'percaya', jejakOk: true, drumBest: 90 };
const POOR = { hookGrade: 'kasar', beads: 1, hasiolan: 'ambil', jejakOk: false, drumBest: 30 };
const SCEN = {
  '4avg': [AVG, AVG2, AVG, AVG2], '3avg': [AVG, AVG2, AVG], '2good': [GOOD, GOOD], '2poor': [POOR, POOR]
};
(async () => {
  const H = await require(path.join(__dirname, '..', 'test', 'harness')).create();
  let uid = 0;
  const grad = async (bekal, tier) => {
    const name = 'sim' + (++uid);
    const c = await H.user(name); await c.call('api_createCharacter', [name, 'pirate']);
    const pid = c.id;
    await H.sql(`update game.ships set tier = $2, cargo = 5000, condition = 100 where player_id = $1`, [pid, tier || 'IV']);
    await H.sql(`update game.character_stats set combat = 60, luck = 40, sailing = 50, navigation = 50, knowledge = 30, negotiation = 50 where player_id = $1`, [pid]);
    await H.sql(`insert into game.player_quests(player_id, quest_id, step, done_at, data) values
      ($1, 'tigasilang', 12, now(), '{}'), ($1, 'limatangan', 10, now() - interval '30 days', $2::jsonb), ($1, 'duatangan', 1, null, '{}')`, [pid, JSON.stringify(bekal)]);
    await H.sql(`update game.player_location set city_id = 'sowtour' where player_id = $1`, [pid]);
    await H.sql(`select game.adjust_inventory($1, 'mesiu', 3000), game.adjust_inventory($1, 'beras', 6000)`, [pid]);
    const pub = (await c.call('api_mpPulse', [{}])).mePub;
    return { c, pid, pub };
  };
  for (const [key, list] of Object.entries(SCEN)) {
    if (ONLY.length && !ONLY.includes(key)) continue;
    const crew = [];
    for (const b of list) crew.push(await grad(b));
    let wins = 0, finals = 0, turns = 0, fb = [], dur = [];
    for (let i = 0; i < N; i++) {
      for (const u of crew) await H.sql(`update game.ships set condition = 100 where player_id = $1`, [u.pid]);
      let r = (await crew[0].c.call('api_dtRaid', ['open'])).raid;
      for (const u of crew.slice(1)) await u.c.call('api_dtRaid', ['join', r.id]);
      for (const u of crew) await u.c.call('api_dtRaid', ['ready', true]);
      await crew[0].c.call('api_dtRaid', ['depart']);
      const t0 = Number((await H.sql(`select game.dt_now() t`))[0].t);
      const res = await bot.runRaid(H, crew.map(u => ({ c: u.c, pub: u.pub })), { skill: 0.85 });
      const t1 = Number((await H.sql(`select game.dt_now() t`))[0].t);
      if (res.result === 'win') wins++;
      if (res.finalBoss != null) { finals++; fb.push(Math.round(res.finalBoss)); }
      turns += res.turns; dur.push(Math.round((t1 - t0) / 60000 * 10) / 10);
      for (const u of crew) await H.sql(`update game.player_quests set step = 1 where player_id = $1 and quest_id = 'duatangan'`, [u.pid]);
      if (process.env.V) console.log(JSON.stringify(res.fl), res.result, res.turns, JSON.stringify(res.fire), JSON.stringify(res.log.filter((x, i) => i % 4 === 0).map(x => [x.r, x.boss, x.sh, x.p])), JSON.stringify(res.card.rows.map(r => [r.hull, r.shield, r.taken, r.endHull])));
      process.stdout.write(res.result === 'win' ? 'W' : (res.finalBoss != null ? 'f' : 'x'));
    }
    console.log(`\n${key}: menang ${wins}/${N} (${Math.round(wins / N * 100)}%), sampai final ${finals}/${N}, giliran rata2 ${(turns / N).toFixed(1)}, bos saat final ${JSON.stringify(fb)}, menit ${JSON.stringify(dur)}`);
  }
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
