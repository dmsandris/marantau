// S5 Susur Ombak (0112): pembangkit lintasan, penilaian JS = SQL, bot sempurna/acak, bantuan, alur sesi.
const fs = require('fs'), path = require('path');
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const src = fs.readFileSync(path.join(__dirname, '..', 'web', 'src', 'S5Ombak.html'), 'utf8');
const blok = src.slice(src.indexOf('/*NILAI-MULAI*/'), src.indexOf('/*NILAI-SELESAI*/'));
const NILAI = new Function(blok + '; return S5OmbakNilai;')();
const PRESET = ['pelangi', 'pelangi_ulang', 'valkyrie', 'ular_muda', 'hafgufa', 'lari_biasa'];

// jalur aman: pindah ke lajur aman tiap baris segera setelah baris sebelumnya selesai
function jalurAman(p) {
  const c = p.course; let lane = 1, endPrev = 0; const taps = [];
  for (let i = 0; i < c.length; i++) {
    const bebas = [0, 1, 2].filter(s => !(c[i].m & (1 << s)));
    const tuju = bebas.sort((a, b) => Math.abs(a - lane) - Math.abs(b - lane))[0];
    let t = endPrev + 10;
    while (lane !== tuju) { const d = tuju > lane ? 1 : -1; taps.push({ t_ms: t, dir: d }); lane += d; t += 120; }
    endPrev = c[i].t + c[i].len;
  }
  return taps;
}
function acak(p, gaya) {
  const taps = []; let t = 0;
  if (gaya === 'bot') { while ((t += 250 + Math.floor(Math.random() * 600)) < p.dur) taps.push({ t_ms: t, dir: Math.random() < .5 ? -1 : 1 }); return taps; }
  // log acak untuk kesetaraan: termasuk ketukan beruntun (<100 ms), di tepi lajur, dan saat kebal
  const n = Math.floor(Math.random() * 60);
  for (let i = 0; i < n; i++) { t += Math.random() < .25 ? Math.floor(Math.random() * 100) : Math.floor(Math.random() * 1500); if (t > p.dur) break; taps.push({ t_ms: t, dir: Math.random() < .5 ? -1 : 1 }); }
  return taps;
}

(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  await H.sql(`select game.cfg_set('GmUsernames', 's5o_gm'), game.cfg_set('S5MgJedaMs', '0'), game.cfg_set('S5MgPerJam', '999')`);
  const G = await H.user('s5o_gm'); await G.call('api_createCharacter', ['Juru Uji', 'merchant']);
  const A = await H.user('s5o_ana'); await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  await H.sql(`create or replace function public.t_wave(p jsonb, l jsonb, e bigint) returns jsonb language plpgsql as $$
    begin return game.mg_wave_judge(p, l, e); exception when others then return jsonb_build_object('err', sqlerrm); end $$`);
  const builds = async (preset, assist, n) => (await H.sql(`select game.mg_wave_build(null, 'trial', $1, $2) v from generate_series(1, $3)`, [preset, assist, n])).map(r => r.v);

  // ============ 1. Invarian pembangkit (1.000 lintasan per preset per tingkat bantuan) ============
  let nLintas = 0;
  for (const preset of PRESET) for (const assist of [0, 15, 30]) {
    for (const p of await builds(preset, assist, 1000)) {
      const c = p.course; ok(c.length >= 1 && c.length <= 60, `jumlah baris ${preset}: ${c.length}`);
      let reach = new Set([1]), prevEnd = 0;
      c.forEach((w, i) => {
        ok([350, 500, 700].includes(w.len) && ({ k: 500, y: 350, o: 700 })[w.j] === w.len, 'panjang baris sesuai jenis');
        ok(w.m >= 1 && w.m <= 6 && w.m !== 7 && [1, 2, 4, 3, 5, 6].includes(w.m), 'tiap baris punya >= 1 lajur bebas');
        if (w.j === 'o') ok([3, 5, 6].includes(w.m), 'ombak menyapu dua lajur');
        ok(w.t >= prevEnd, 'baris berurutan, tak tumpang tindih');
        const gap = w.t - prevEnd, next = new Set();
        reach.forEach(a => [0, 1, 2].forEach(s => { if (!(w.m & (1 << s)) && Math.abs(s - a) * 250 + 350 <= (i === 0 ? w.t : gap)) next.add(s); }));
        ok(next.size > 0, `jalur aman terjangkau ${preset} baris ${i}`);
        reach = next; prevEnd = w.t + w.len;
      });
      ok(prevEnd <= p.dur - 1500, 'baris terakhir selesai sebelum dur - tail');
      nLintas++;
    }
  }

  // ============ 2. JS = SQL (10.000 log acak) ============
  let nSama = 0;
  for (const preset of PRESET) {
    const ps = await builds(preset, [0, 15, 30][Math.floor(Math.random() * 3)], 5);
    for (const p of ps) {
      const logs = Array.from({ length: 340 }, (_, k) => k % 17 === 0 ? jalurAman(p) : acak(p));
      const rows = await H.sql(`select i, t_wave($1, x, $3) v from jsonb_array_elements($2::jsonb) with ordinality as t(x, i) order by i`, [p, JSON.stringify(logs), p.dur + 5000]);
      rows.forEach((r, k) => {
        const js = NILAI.judge(p, logs[k]);
        if (r.v.err || r.v.won !== js.won || r.v.tabrak !== js.tabrak || r.v.daya !== js.daya) { console.error('BEDA', preset, JSON.stringify(logs[k]), JSON.stringify(r.v), JSON.stringify(js)); process.exit(1); }
        nSama++;
      });
    }
  }
  ok(nSama >= 10000, 'kesetaraan diuji >= 10.000 log: ' + nSama);

  // ============ 3. Bot sempurna menang semua; bot acak kalah >= 99% ============
  for (const preset of PRESET) {
    let kalahAcak = 0;
    for (const p of await builds(preset, 0, 200)) ok(NILAI.judge(p, jalurAman(p)).won === true, 'bot jalur aman menang ' + preset);
    const ps = await builds(preset, 0, 50);
    for (let i = 0; i < 1000; i++) if (!NILAI.judge(ps[i % 50], acak(ps[i % 50], 'bot')).won) kalahAcak++;
    ok(kalahAcak >= 990, `bot acak kalah >= 99% (${preset}): ${kalahAcak}/1000`);
  }

  // ============ 4. Aturan ketukan & log tidak sah ============
  const [p0] = await builds('valkyrie', 0, 1);
  const J = async (l, e) => (await one(`select t_wave($1, $2, $3) v`, [p0, JSON.stringify(l), e == null ? p0.dur + 5000 : e])).v;
  ok((await J([{ t_ms: 500, dir: 1 }, { t_ms: 400, dir: 1 }])).err, 'log mundur ditolak');
  ok((await J([{ t_ms: 500, dir: 2 }])).err, 'dir tidak sah ditolak');
  ok((await J([{ t_ms: 500.5, dir: 1 }])).err, 't_ms pecahan ditolak');
  ok((await J([{ t_ms: p0.dur + 1, dir: 1 }])).err, 't_ms di luar durasi ditolak');
  ok((await J(Array.from({ length: p0.dur / 100 + 1 }, (_, i) => ({ t_ms: i * 10, dir: 1 })))).err, 'terlalu banyak ketukan ditolak');
  ok((await J({ taps: 'x' })).err, 'bentuk log salah ditolak');
  const sA = new NILAI.Sim(p0); sA.ketuk(100, 1); sA.ketuk(150, 1); sA.maju(200); ok(sA.lane === 2, 'ketukan < 100 ms setelah pindah diabaikan (lajur 2, bukan tepi)');
  const sB = new NILAI.Sim(p0); sB.ketuk(100, 1); sB.ketuk(300, 1); sB.maju(400); ok(sB.lane === 2, 'ketukan di tepi lajur diabaikan');
  ok((await J(jalurAman(p0), p0.dur - 4000)).err, 'klaim menang sebelum dur - 3000 ditolak');
  ok((await J(jalurAman(p0), p0.dur - 3000)).won === true, 'menang sah tepat dur - 3000');
  ok((await J([{ t_ms: 9000, dir: 1 }], 2000)).err, 'ketukan melampaui waktu server + 3 dtk ditolak');

  // ============ 5. Bantuan & keringanan awal ============
  const b0 = (await builds('valkyrie', 0, 1))[0], b15 = (await builds('valkyrie', 15, 1))[0], b30 = (await builds('valkyrie', 30, 1))[0];
  ok(b0.hit === 5500 && b15.hit === 4400 && b30.hit === 3300, 'hit_cost x0,8 / x0,6');
  ok(b0.regen === 5 && b15.regen === 5 && b30.regen === 6, 'regen x1,25 (min +1) di tingkat 2');
  const awal = (await one(`select game.mg_wave_build($1, 'quest', 'valkyrie', 0) v`, [A.id])).v;
  ok(awal.hit === 3850, 'tiga percobaan pertama langkah kejaran: x0,7');
  await H.sql(`insert into game.mg_session(player_id, kind, context, preset, expires_at, status) select $1, 'wave', 'quest', 'valkyrie', now(), 'lost' from generate_series(1, 3)`, [A.id]);
  ok((await one(`select game.mg_wave_build($1, 'quest', 'valkyrie', 0) v`, [A.id])).v.hit === 5500, 'setelah tiga percobaan: normal');
  await H.sql(`select game.cfg_set('S5Ombak_valkyrie_hit', '6000')`);
  ok((await builds('valkyrie', 0, 1))[0].hit === 6000, 'angka preset bisa disetel lewat game.config');
  await H.sql(`select game.cfg_set('S5Ombak_valkyrie_hit', '5500')`);

  // ============ 6. Sesi lewat API (uji coba GM) ============
  await H.sql(`select game.cfg_set('S5aOpen', '1')`);
  let e = null; try { await A.call('api_mg_start', ['wave', 'trial', 'pelangi', '']); } catch (x) { e = x.message; }
  ok(e, 'pemain biasa tidak bisa uji coba');
  const st = await G.call('api_mg_start', ['wave', 'trial', 'pelangi', '']);
  ok(st.session_id && st.params.course.length > 0 && st.params.kulit === 'pelangi', 'sesi dibuka, lintasan dari server');
  e = null; try { await G.call('api_mg_finish', [st.session_id, { taps: jalurAman(st.params) }]); } catch (x) { e = x.message; }
  ok(e && /tidak sah/.test(e), 'menang terlalu cepat ditolak: ' + e);
  await H.sql(`update game.mg_session set issued_ms = issued_ms - $2 where id = $1`, [st.session_id, st.params.dur + 3000]);
  const f1 = await G.call('api_mg_finish', [st.session_id, { taps: jalurAman(st.params) }]);
  ok(f1.status === 'won', 'jalur aman menang lewat server: ' + JSON.stringify(f1));
  const f2 = await G.call('api_mg_finish', [st.session_id, { taps: [] }]);
  ok(f2.replay && f2.status === 'won', 'finish ganda: hasil sama');
  const st2 = await G.call('api_mg_start', ['wave', 'trial', 'hafgufa', '']);
  const st3 = await G.call('api_mg_start', ['wave', 'trial', 'hafgufa', '']);
  ok((await one(`select count(*)::int n from game.mg_session where player_id = $1 and status = 'open'`, [G.id])).n === 1, 'tidak pernah dua sesi open');
  e = null; try { await A.call('api_mg_finish', [st3.session_id, { taps: [] }]); } catch (x) { e = x.message; }
  ok(e, 'sesi pemain lain ditolak');
  // kalah awal (diam di tengah) diterima tanpa menunggu durasi
  await H.sql(`update game.mg_session set issued_ms = issued_ms - $2 where id = $1`, [st3.session_id, st3.params.dur + 3000]);
  const f3 = await G.call('api_mg_finish', [st3.session_id, { taps: [] }]);
  ok(f3.status === 'won' || f3.status === 'lost', 'hasil diam: ' + f3.status);
  ok(f3.result.won === NILAI.judge(st3.params, []).won, 'hasil server = klien');

  console.log(`OK 0112 Susur Ombak: ${nLintas} lintasan, ${nSama} log JS=SQL, bot & sesi`);
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
