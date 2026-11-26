// S5 Dengar Tanah (0106) + Bagian I langkah 1-19 (0107): penilaian (termasuk JS = SQL), pemicu, alur penuh, alat GM.
const fs = require('fs'), path = require('path');
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
// muat blok penilaian klien (S5DengarNilai) apa adanya dari berkas klien
const src = fs.readFileSync(path.join(__dirname, '..', 'web', 'src', 'S5Dengar.html'), 'utf8');
const blok = src.slice(src.indexOf('/*NILAI-MULAI*/'), src.indexOf('/*NILAI-SELESAI*/'));
const NILAI = new Function(blok + '; return S5DengarNilai;')();

(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const clock = f => H.sql(`select game.cfg_set('WorldStartTimestamp', (game.now_ms() - ($1::numeric * game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint)::text)`, [f]);
  const SIANG = 20.5, MALAM = 20.8;
  await clock(SIANG);
  await H.sql(`select game.cfg_set('GmUsernames', 's5b_gm'), game.cfg_set('S5MgJedaMs', '0'), game.cfg_set('S5MgPerJam', '999')`);
  const G = await H.user('s5b_gm'); await G.call('api_createCharacter', ['Juru Uji', 'merchant']);
  const A = await H.user('s5b_ana'); await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const B = await H.user('s5b_budi'); await B.call('api_createCharacter', ['Kapten Budi', 'merchant']);
  const ke = (u, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, c]);
  const gold = async u => Number((await one(`select gold from game.players where player_id = $1`, [u.id])).gold);
  const tamatS4 = (u, hariLalu) => H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'mahkota2', 20, '{}', now() - make_interval(mins => $2 * game.cfg_num('GameDayLengthRealMinutes', 60)::int))
     on conflict (player_id, quest_id) do update set step = 20, done_at = excluded.done_at`, [u.id, hariLalu]);

  // ================= 1. Penilaian Dengar Tanah: SQL vs JS =================
  await H.sql(`create or replace function public.t_judge(p jsonb, l jsonb, e bigint) returns jsonb language plpgsql as $$
    begin return game.mg_listen_judge(p, l, e); exception when others then return jsonb_build_object('err', sqlerrm); end $$`);
  const build = async (preset, assist) => (await one(`select game.mg_listen_build(null, 'quest', $1, $2) v`, [preset, assist])).v;
  const jsJudge = (p, l, e) => { try { return NILAI.judge(p, l, e); } catch (x) { return { err: x.message }; } };
  const sama = (a, b) => (!!a.err === !!b.err) && (a.err ? true : (a.won === b.won && (a.hits == null || a.hits === b.hits)));
  const R = (n) => Math.floor(Math.random() * n);
  const perfect = (p) => {
    if (p.preset === 'cari_lereng') return { probes: [{ p: R(9), t_ms: 2000 }], answers: [{ p: p.S, t_ms: 9000 }], pattern_picks: [{ opsi: 'A', t_ms: 12000 }] };
    if (p.preset === 'akar_selatan') return { dir_answers: [{ d: 4, t_ms: 4000 }], t0_ms: 8000, taps: [0, 1, 2, 3, 4, 5].map(k => ({ t_ms: 8000 + k * p.interval_ms + R(41) - 20 })) };
    let t = 3000; const phrases = p.urutan.map(n => { const fr = p.frasa[String(n)], base = t; const att = fr.map(b => ({ pad: b[0], t_ms: base + b[1] * p.beat_ms + R(41) - 20 })); att[0].t_ms = base; t = base + 12000; return { n, attempts: [att], replays: 0 }; });
    return { phrases };
  };
  const acak = (p) => {
    const T = () => R(p.max_ms);
    const inc = (arr) => arr.sort((a, b) => a.t_ms - b.t_ms);
    if (p.preset === 'cari_lereng') {
      const ans = inc(Array.from({ length: R(p.answers + 2) }, () => ({ p: R(10), t_ms: T() })));
      const picks = inc(Array.from({ length: R(p.tries + 2) }, () => ({ opsi: 'ABCD'[R(4)], t_ms: T() })));
      return { probes: inc(Array.from({ length: R(p.probes + 2) }, () => ({ p: R(9), t_ms: T() }))), answers: ans, pattern_picks: picks };
    }
    if (p.preset === 'akar_selatan') {
      const da = inc(Array.from({ length: R(p.answers + 1) + (Math.random() < .5 ? 0 : 0) }, () => ({ d: Math.random() < .5 ? 4 : R(8), t_ms: R(20000) })));
      const t0 = 20000 + R(5000);
      return { dir_answers: da, t0_ms: t0, taps: inc(Array.from({ length: R(13) }, () => ({ t_ms: t0 - 500 + R(12000) }))) };
    }
    let t = 0;
    return { phrases: p.urutan.slice(0, 1 + R(p.urutan.length)).map(n => {
      const fr = p.frasa[String(n)];
      return { n, attempts: Array.from({ length: 1 + R(p.tries) }, () => { const base = (t += 4000); return fr.map((b, j) => ({ pad: Math.random() < .85 ? b[0] : R(3), t_ms: base + b[1] * p.beat_ms + (j === 0 ? 0 : R(2 * p.tol_ms + 200) - p.tol_ms - 100) })).sort((a, b) => a.t_ms - b.t_ms).map((x, j, arr) => { t = Math.max(t, x.t_ms); return x; }); }) };
    }) };
  };
  let nCek = 0, nMenang = { cari_lereng: 0, lagu_tidur: 0, lagu_tidur_pendek: 0, akar_selatan: 0 };
  for (const preset of ['cari_lereng', 'lagu_tidur', 'lagu_tidur_pendek', 'akar_selatan']) {
    for (const assist of [0, 15, 30]) {
      const p = await build(preset, assist);
      // sempurna menang di kedua sisi
      const l = perfect(p), e = p.max_ms;
      const s1 = (await one(`select t_judge($1, $2, $3) v`, [p, l, e])).v, j1 = jsJudge(p, l, e);
      ok(s1.won === true && j1.won === true, `bot sempurna menang ${preset}/${assist}: ${JSON.stringify(s1)} ${JSON.stringify(j1)}`);
      // acak: SQL = JS (dikirim sekaligus per kelompok)
      const logs = Array.from({ length: 700 }, () => acak(p));
      const rows = await H.sql(`select i, t_judge($1, x, $3) v from jsonb_array_elements($2::jsonb) with ordinality as t(x, i) order by i`, [p, JSON.stringify(logs), e]);
      rows.forEach((r, k) => {
        const js = jsJudge(p, logs[k], e);
        if (!sama(r.v, js)) { console.error('BEDA', preset, assist, JSON.stringify(logs[k]), JSON.stringify(r.v), JSON.stringify(js)); process.exit(1); }
        if (js.won) nMenang[preset]++;
        nCek++;
      });
    }
  }
  ok(nMenang.lagu_tidur <= 10, 'bot setengah-acak (85% nada benar) hampir tak pernah menamatkan tiga frasa: ' + nMenang.lagu_tidur + ' dari 2100');
  // kasus khusus
  const pc = await build('cari_lereng', 0), pl = await build('lagu_tidur', 0), pa = await build('akar_selatan', 0);
  const J = async (p, l, e) => (await one(`select t_judge($1, $2, $3) v`, [p, l, e == null ? p.max_ms : e])).v;
  ok((await J(pc, { answers: [{ p: pc.S, t_ms: 100 }], pattern_picks: [{ opsi: 'A', t_ms: 50 }] })).err, 'cari_lereng: waktu mundur ditolak');
  ok((await J(pc, { answers: [{ p: (pc.S + 1) % 9, t_ms: 1 }, { p: (pc.S + 2) % 9, t_ms: 2 }], pattern_picks: [{ opsi: 'A', t_ms: 5 }] })).err, 'cari_lereng: memilih napas tanpa gali benar ditolak');
  ok((await J(pc, { answers: [{ p: pc.S, t_ms: 1 }, { p: pc.S, t_ms: 2 }] })).err, 'cari_lereng: gali setelah benar ditolak');
  ok((await J(pc, { answers: [{ p: pc.S, t_ms: 1 }], pattern_picks: [{ opsi: 'B', t_ms: 2 }, { opsi: 'C', t_ms: 3 }] })).won === false, 'cari_lereng: dua pilihan salah kalah');
  ok((await J(pc, { answers: [{ p: pc.S, t_ms: 90000 }], pattern_picks: [{ opsi: 'A', t_ms: 95000 }] }, 1000)).err, 'cari_lereng: waktu melebihi jam server ditolak');
  const lp = perfect(pl); lp.phrases[1].attempts[0][3].pad = (lp.phrases[1].attempts[0][3].pad + 1) % 3;
  ok((await J(pl, lp)).err, 'lagu: frasa gagal tapi frasa berikutnya ada -> ditolak');
  const lp2 = perfect(pl); lp2.phrases[0].attempts[0][2].t_ms += pl.tol_ms + 5; lp2.phrases.length = 1;
  ok((await J(pl, lp2)).won === false && !(await J(pl, lp2)).err, 'lagu: lewat toleransi -> kalah');
  const lp3 = perfect(pl); lp3.phrases[0].attempts.unshift(lp3.phrases[0].attempts[0].map(x => ({ pad: x.pad, t_ms: x.t_ms - 6000 })));
  ok((await J(pl, lp3)).err, 'lagu: percobaan setelah cocok ditolak');
  const lp4 = perfect(pl); lp4.phrases[0].replays = 3;
  ok((await J(pl, lp4)).err, 'lagu: dengar ulang melebihi batas ditolak');
  const ap = perfect(pa); ap.taps = [...ap.taps, ...ap.taps.map(x => ({ t_ms: x.t_ms + 5 }))].sort((a, b) => a.t_ms - b.t_ms);
  ok((await J(pa, ap)).hits === 6, 'akar: dua ketukan pada satu detak dihitung satu');
  ok((await J(pa, { dir_answers: [{ d: 3, t_ms: 1 }, { d: 5, t_ms: 2 }], taps: [{ t_ms: 3 }] })).err, 'akar: ketuk tanpa arah benar ditolak');
  ok((await J(pa, { dir_answers: [{ d: 4, t_ms: 5000 }], t0_ms: 100, taps: [] })).err, 'akar: t0 sebelum arah dikunci ditolak');
  ok((await J(pa, { dir_answers: [{ d: 4, t_ms: 1 }], t0_ms: 3000, taps: [0, 1, 2].map(k => ({ t_ms: 3000 + k * 1800 })) })).won === false, 'akar: 3 dari 6 kalah');
  ok((await J({ preset: 'lain', max_ms: 1000 }, {})).err, 'preset tak dikenal ditolak');

  // ================= 2. Pemicu Bagian I =================
  const st = async u => (await u.call('api_getGameState', [])).s5;
  ok((await st(A)) === undefined, 'gerbang tertutup: tanpa key s5');
  await H.sql(`select game.cfg_set('FiturPenguji', 's5b_ana,s5b_budi')`);
  ok((await st(A)) === undefined, 'Saga 4 belum tamat: tanpa key s5');
  await tamatS4(A, 1);
  ok((await st(A)) === undefined, 'baru 1 hari setelah Saga 4');
  await tamatS4(A, 3);
  let s = await st(A);
  ok(s && s.step === 0 && s.d.n === 1 && s.ada >= 19, 'tiga hari game setelah Saga 4 -> langkah 1');
  await H.expectError(() => B.call('api_s5', ['maju', 1, 'ok']), /Aksi tidak dikenal/);
  await H.expectError(() => A.call('api_mg_start', ['listen', 'quest', 'cari_lereng', 3]), /bergeser/);
  await H.expectError(() => A.call('api_mg_start', ['listen', 'trial', 'cari_lereng']), /Belum ada yang menunggu/);   // trial hanya GM

  // ================= 3. Alur penuh 1-19 =================
  const maju = (u, n, res) => u.call('api_s5', ['maju', n, res || 'ok']);
  const dengar = async (u, n, preset) => {
    const r = await u.call('api_mg_start', ['listen', 'quest', preset, n]);
    await H.sql(`update game.mg_session set issued_ms = issued_ms - 200000 where id = $1`, [r.session_id]);
    const f = await u.call('api_mg_finish', [r.session_id, perfect(r.params)]);
    ok(f.status === 'won' && f.efek.siap === true, `Dengar Tanah langkah ${n} menang: ` + JSON.stringify(f));
  };
  await ke(A, 'skitraw');
  const g0 = await gold(A);
  await maju(A, 1);                                                                     // pulau mana pun
  await H.expectError(() => maju(A, 3), /bergeser/);
  await H.expectError(() => maju(A, 2), /Tidak ada yang perlu/);                        // salah pulau
  await ke(A, 'toogood');
  await H.expectError(() => maju(A, 2, 'gagal'), /Belum berhasil/);
  await maju(A, 2);
  await ke(A, 'bjorneo');
  await H.expectError(() => maju(A, 3), /Tanah belum menjawab/);                        // tanpa Dengar Tanah
  // gagal Dengar Tanah tidak memajukan
  let rr = await A.call('api_mg_start', ['listen', 'quest', 'cari_lereng', 3]);
  await H.sql(`update game.mg_session set issued_ms = issued_ms - 200000 where id = $1`, [rr.session_id]);
  const f0 = await A.call('api_mg_finish', [rr.session_id, { answers: [{ p: (rr.params.S + 1) % 9, t_ms: 1 }, { p: (rr.params.S + 2) % 9, t_ms: 2 }] }]);
  ok(f0.status === 'lost', 'Dengar Tanah kalah');
  await H.expectError(() => maju(A, 3), /Tanah belum menjawab/);
  await dengar(A, 3, 'cari_lereng');
  await maju(A, 3); await maju(A, 4);
  await ke(A, 'joungjava'); await maju(A, 5);
  let r6 = await maju(A, 6);
  ok(r6.gold === 250000 && r6.q === 23 && (await gold(A)) === g0 + 250000, 'hadiah Q23 250.000');
  await ke(A, 'bjorneo'); await maju(A, 7); await maju(A, 8); await maju(A, 9);
  await ke(A, 'karang_garam'); await maju(A, 10); await maju(A, 11);
  await ke(A, 'joungjava');
  await H.expectError(() => maju(A, 12), /Keputusannya/);
  await H.expectError(() => A.call('api_s5', ['pilih', 12, 'bakar']), /tidak dikenali/);
  const r12 = await A.call('api_s5', ['pilih', 12, 'luruskan']);
  ok(r12.gold === 300000 && r12.s5.data.kabar_buku === 'luruskan', 'pilihan kabar_buku + hadiah Q24');
  await ke(A, 'otoland'); await maju(A, 13); await maju(A, 14);
  await ke(A, 'sowtour');
  await H.expectError(() => maju(A, 15), /lampu dinyalakan/);                          // siang
  await clock(MALAM); await maju(A, 15); await clock(SIANG); await maju(A, 16);
  await ke(A, 'zentul');
  s = await st(A); ok(s.warlord && s.warlord.terpasang === false && s.warlord.oli === 10, 'kartu Yaptob membawa status Warlord: ' + JSON.stringify(s.warlord));
  await H.expectError(() => maju(A, 17), /Mesin Jolt Warlord belum terpasang/);
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'speed') on conflict do nothing`, [A.id]);
  await maju(A, 17);
  await ke(A, 'bjorneo'); await maju(A, 18);
  await H.expectError(() => A.call('api_mg_start', ['listen', 'quest', 'lagu_tidur', 19]), /lampu dinyalakan/);
  await clock(MALAM);
  await H.expectError(() => A.call('api_mg_start', ['listen', 'quest', 'cari_lereng', 19]), /bergeser/);    // preset salah
  await dengar(A, 19, 'lagu_tidur');
  await clock(SIANG);
  await H.expectError(() => maju(A, 19), /lampu dinyalakan/);
  await clock(MALAM);
  const r19 = await maju(A, 19);
  ok(r19.s5.step === 19 && (r19.s5.d === null || r19.s5.d.n === 20), 'langkah 19 selesai (Bagian I tuntas)');
  if (!r19.s5.gerbangB) await H.expectError(() => maju(A, 20), /Bersambung/);   // langkah 20+ diuji di 0113
  ok((await gold(A)) === g0 + 550000, 'total hadiah Bagian I (Q25 dibayar di langkah 20)');
  await clock(SIANG);

  // Saat berlayar / di seberang tidak bisa maju
  await H.sql(`select game.admin_s5('s5b_ana', 4)`);
  await H.sql(`update game.player_location set destination_city_id = 'joungjava', depart_at = now(), arrive_at = now() + interval '1 hour' where player_id = $1`, [A.id]);
  await H.expectError(() => maju(A, 4), /Merapat dulu/);
  await ke(A, 'bjorneo');
  await H.sql(`insert into game.s5_state(player_id, dunia) values ($1, 'seberang') on conflict (player_id) do update set dunia = 'seberang'`, [A.id]);
  await H.expectError(() => maju(A, 4), /Tidak ada yang perlu/);
  await H.sql(`update game.s5_state set dunia = 'mare' where player_id = $1`, [A.id]);
  await maju(A, 4);

  // ================= 4. Alat uji GM =================
  ok((await st(G)) === undefined, 'GM tanpa mode uji: tertutup');
  await H.expectError(() => B.call('api_s5', ['gm_uji', '1']), /Aksi tidak dikenal/);
  let g = await G.call('api_s5', ['gm_uji', '1']);
  ok(g.gm.uji === true, 'GM mode uji menyala');
  ok((await st(G)) === undefined, 'mode uji tanpa Saga 4 tamat: belum ada langkah');
  g = await G.call('api_s5', ['gm_langkah', '19']);
  ok(g.s5 && g.s5.d.n === 19 && g.gm.langkah === 19, 'GM lompat ke langkah 19');
  const t1 = await G.call('api_mg_start', ['listen', 'trial', 'akar_selatan']);
  ok(t1.params.target === 4, 'GM uji coba akar_selatan (trial)');
  await H.sql(`update game.mg_session set issued_ms = issued_ms - 200000 where id = $1`, [t1.session_id]);
  const tf = await G.call('api_mg_finish', [t1.session_id, perfect(t1.params)]);
  ok(tf.status === 'won' && Object.keys(tf.efek).length === 0, 'trial tanpa efek quest');
  await H.expectError(() => G.call('api_s5', ['gm_langkah', '99']), /Langkah 1 sampai/);
  await G.call('api_s5', ['gm_uji', '0']);
  ok((await st(G)) === undefined, 'mode uji dimatikan: tertutup lagi');
  ok((await G.call('api_s5', ['gm_status'])).gm.uji === false, 'status uji mati');

  console.log(`OK 0107-s5-bagian1: ${nCek} log acak SQL = JS, kasus khusus, pemicu, langkah 1-19, Dengar Tanah server, alat GM. Menang acak: ${JSON.stringify(nMenang)}`);
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
