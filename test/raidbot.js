// Bot Serbuan Bersama: dipakai tes 0030 dan alat kalibrasi tools/sim-raid.js.
// Bot memakai API yang sama dengan klien (api_dtRaid view/act/rt) dan fisika JS yang sama dengan lb_step.
const TAU = Math.PI * 2;
const ang = a => a - TAU * Math.floor((a + Math.PI) / TAU);
const wf = (h, w) => { const a = Math.abs(ang(h - (w + Math.PI))); if (a < 0.62) return 0.12 + a * 0.12; if (a < 1.75) return 0.25 + 0.75 * Math.sin((a - 0.62) / (1.75 - 0.62) * Math.PI / 2); return 1.0 - (a - 1.75) / (Math.PI - 1.75) * 0.22; };
function lbStep(s, rud, sails, dt, w) {
  const tr = 0.2 * (sails === 1 ? 0.85 : 1) * (0.55 + 0.45 * Math.min(1, s.v / 30)) * (s.tm || 1);
  s.h = ang(s.h + rud * tr * dt);
  const ts = 62 * wf(s.h, w) * (sails === 1 ? 1 : 0.55) * (0.3 + 0.7 * (s.sail == null ? 100 : s.sail) / 100) * (s.sp || 1);
  s.v = s.v + (ts - s.v) * (1 - Math.exp(-dt * 0.9));
  s.x += Math.sin(s.h) * s.v * dt; s.y -= Math.cos(s.h) * s.v * dt;
  s.x = Math.max(60, Math.min(2140, s.x)); s.y = Math.max(60, Math.min(1440, s.y));
}
const steer = (x, y, h, tx, ty) => { const rel = ang(Math.atan2(tx - x, -(ty - y)) - h); if (Math.abs(rel) < 0.12) return 0; return rel > 0 ? (rel > 0.55 ? 2 : 1) : (rel < -0.55 ? -2 : -1); };
const SX = 1100, SY = 750, LANE = 560;

// perintah satu giliran: coba 5 posisi kemudi, simulasikan 3 dtk, pilih yang memberi salvo terbaik
function arcOk(s, bx, by, side, maxd) {
  const d = Math.hypot(bx - s.x, by - s.y), rel = ang(Math.atan2(bx - s.x, -(by - s.y)) - s.h);
  const off = Math.abs(ang(rel - side * Math.PI / 2));
  return d <= maxd && off <= 0.8 ? (1 - off / 0.85 * 0.5) * (1.08 - d / 560) : 0;
}
function plan(me, boss, phase, skill, rnd, w) {
  rnd = rnd || Math.random;
  if (w != null && rnd() < skill) {
    let best = null;
    for (let rud = -2; rud <= 2; rud++) {
      const s = { x: me.x, y: me.y, h: me.h, v: me.v, sp: me.sp, tm: me.tm, sail: me.sail };
      let fireL = 0, fireR = 0, sc = 0;
      for (let i = 1; i <= 60; i++) {
        lbStep(s, rud, 1, 0.05, w);
        if (i === 20) {
          const bx = boss.x + Math.sin(boss.h) * boss.v, by = boss.y - Math.cos(boss.h) * boss.v;
          fireL = (me.rlL || 0) <= 1 ? arcOk(s, bx, by, -1, 510) : 0; fireR = (me.rlR || 0) <= 1 ? arcOk(s, bx, by, 1, 510) : 0;
          sc += (fireL + fireR) * 10;
        }
      }
      const bx = boss.x + Math.sin(boss.h) * boss.v * 3, by = boss.y - Math.cos(boss.h) * boss.v * 3;
      const d = Math.hypot(bx - s.x, by - s.y), rel = Math.abs(ang(Math.atan2(bx - s.x, -(by - s.y)) - s.h));
      sc -= Math.abs(d - 260) / 100 + Math.abs(rel - Math.PI / 2) * 1.5;
      if (phase === 2) { const rr = Math.hypot(s.x - SX, s.y - SY); sc -= Math.max(0, Math.abs(rr - LANE) - (me.lane || 70) * 0.8) / 15; }
      if (d < 140) sc -= 3;
      const edge = Math.min(s.x - 60, 2140 - s.x, s.y - 60, 1440 - s.y);
      if (edge < 220) sc -= (220 - edge) / 25;
      if (!best || sc > best.sc) best = { sc, rud, fl: fireL > 0.05, fr: fireR > 0.05 };
    }
    return { rud: best.rud, sails: 1, fl: best.fl, fr: best.fr, ammo: boss.shield > 0 ? 'chain' : 'ball' };
  }
  return planSimple(me, boss, phase, skill, rnd);
}
function planSimple(me, boss, phase, skill, rnd) {
  rnd = rnd || Math.random;
  const d = Math.hypot(boss.x - me.x, boss.y - me.y);
  const rel = ang(Math.atan2(boss.x - me.x, -(boss.y - me.y)) - me.h);
  let rud;
  if (phase === 2) {
    const th = Math.atan2(me.y - SY, me.x - SX) + 0.42;
    rud = steer(me.x, me.y, me.h, SX + Math.cos(th) * LANE, SY + Math.sin(th) * LANE);
  } else if (d > 330) {
    rud = steer(me.x, me.y, me.h, boss.x, boss.y);
  } else {
    // putar sampai bos di samping
    rud = Math.abs(rel) < Math.PI / 2 - 0.2 ? (rel > 0 ? -1 : 1) : Math.abs(rel) > Math.PI / 2 + 0.2 ? (rel > 0 ? 1 : -1) : 0;
  }
  if (rnd() > skill) rud = Math.round(rnd() * 4) - 2;
  const fl = Math.abs(ang(rel + Math.PI / 2)) < 0.75 && d < 480;
  const fr = Math.abs(ang(rel - Math.PI / 2)) < 0.75 && d < 480;
  return { rud, sails: 1, fl: fl || (rnd() > skill && rnd() < 0.3), fr, ammo: boss.shield > 0 ? 'chain' : 'ball' };
}

// satu serbuan sampai selesai. clients = [{c, pub}], opts.shift(ms) memajukan jam serbuan.
async function runRaid(H, clients, opts) {
  opts = opts || {};
  const skill = opts.skill == null ? 0.9 : opts.skill;
  const shift = async ms => H.sql(`update game.config set value = (value::bigint + $1)::text where key = 'DtClockOffset'`, [ms]);
  let v = (await clients[0].c.call('api_dtRaid', ['view'])).raid;
  const id = v.id;
  await shift(10000);
  let guard = 0, turns = 0; const res0 = { shots: 0, hits: 0, q: 0 };
  while (v.status === 'active' && v.phase === 'plan' && guard++ < 200) {
    // semua kapten melihat & mengunci perintah
    const round = v.round;
    let cried = false;
    for (const cl of clients) {
      const vv = (await cl.c.call('api_dtRaid', ['view', id])).raid;
      if (vv.status !== 'active' || vv.phase !== 'plan' || vv.round !== round) { v = vv; continue; }
      const me = vv.st.ships[vv.me];
      if (!me || !me.alive) continue;
      if (opts.offline && opts.offline.includes(cl.pub)) continue;
      const o = plan(me, vv.st.boss, vv.st.boss.phase, skill, null, vv.st.w);
      if (vv.st.boss.phase === 3 && me.cry && !cried && !vv.st.boss.stun) { o.cry = true; cried = true; }
      v = (await cl.c.call('api_dtRaid', ['act', round, o, id])).raid;
    }
    if (v.status === 'active' && v.phase === 'plan' && v.round === round) {
      // ada yang tidak mengunci (putus koneksi): tunggu batas waktu
      await shift(16000);
      v = (await clients[0].c.call('api_dtRaid', ['view', id])).raid;
    }
    turns++;
    if (v.ev && v.ev.evs) for (const e of v.ev.evs) res0[e.k] = (res0[e.k] || 0) + 1;
    if (v.ev && v.ev.shots) for (const sh of v.ev.shots) if (sh.hits) { res0.shots++; res0.hits += sh.hits.filter(Boolean).length; res0.q += sh.q > 0 ? 1 : 0; }
    await shift(3500 + (v.ev && v.ev.cine ? 12000 : 0));
  }
  const res = { id, turns, finalBoss: null, result: null, fire: res0 };
  if (v.status === 'active' && v.phase === 'final') {
    res.finalBoss = v.st.boss.hull;
    await shift(Math.max(0, v.finalTs - v.t) + 50);
    const loc = {}, since = {}, lastF = {};
    for (const cl of clients) {
      const s = v.st.ships[cl.pub];
      loc[cl.pub] = Object.assign({}, s); since[cl.pub] = 0; lastF[cl.pub] = { L: 0, R: 0, B: 0 };
    }
    let boss = v.st.boss, t = 0, status = 'active', w = v.st.w, last;
    const dtMs = opts.rtMs || 500;
    while (status === 'active' && t < 80000) {
      for (const cl of clients) {
        const s = loc[cl.pub];
        if (!s || s.alive === false) continue;
        if (opts.offline && opts.offline.includes(cl.pub)) continue;
        // kemudi & fisika lokal (seperti klien)
        const o = plan(Object.assign({}, s, { rlL: 0, rlR: 0 }), boss, 1, skill, null, w);
        for (let i = 0; i < dtMs / 50; i++) lbStep(s, o.rud, 1, 0.05, w);
        const evs = [], d = Math.hypot(boss.x - s.x, boss.y - s.y), rel = ang(Math.atan2(boss.x - s.x, -(boss.y - s.y)) - s.h);
        const rl = 3000 * (s.rm || 1);
        if (Math.abs(ang(rel + Math.PI / 2)) < 0.8 && d < 510 && t - lastF[cl.pub].L >= rl) { evs.push({ k: 'f', s: -1, a: 'ball' }); lastF[cl.pub].L = t; }
        if (Math.abs(ang(rel - Math.PI / 2)) < 0.8 && d < 510 && t - lastF[cl.pub].R >= rl) { evs.push({ k: 'f', s: 1, a: 'ball' }); lastF[cl.pub].R = t; }
        if (d < 115 && t - lastF[cl.pub].B >= 8000) { evs.push({ k: 'b', sc: Math.random() < skill ? 3 : (Math.random() < 0.5 ? 2 : 1) }); lastF[cl.pub].B = t; }
        res.fsent = (res.fsent || 0) + evs.filter(e => e.k === 'f').length;
        last = await cl.c.call('api_dtRaid', ['rt', { x: s.x, y: s.y, h: s.h, v: s.v, sails: 1, ammo: 'ball' }, evs, since[cl.pub], id]);
        status = last.status;
        if (status !== 'active') break;
        since[cl.pub] = last.seq; boss = last.boss;
        const me = last.ships[cl.pub]; if (me) { s.alive = me.alive; s.hull = me.hull; }
      }
      if (status !== 'active') break;
      await shift(dtMs); t += dtMs;
      if (t % 10000 === 0) (res.fl = res.fl || []).push([t / 1000, Math.round(boss.hull), clients.filter(cl => loc[cl.pub].alive !== false).length, res.fsent || 0]);
      if (clients.every(cl => (opts.offline || []).includes(cl.pub) || loc[cl.pub].alive === false)) {
        await shift(80000); last = await clients[0].c.call('api_dtRaid', ['rt', null, [], 0, id]); status = last.status; break;
      }
    }
  }
  v = (await clients[0].c.call('api_dtRaid', ['view', id])).raid;
  res.result = v.result; res.card = v.card; res.status = v.status; res.rounds = v.round; res.log = v.log;
  return res;
}

module.exports = { plan, runRaid, lbStep, ang };
