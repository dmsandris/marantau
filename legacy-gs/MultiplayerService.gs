/**
 * MultiplayerService.gs  (Tide v6 - Multiplayer)
 * ------------------------------------------------------------------
 * Fitur antar-pemain di atas Apps Script tanpa server realtime:
 *   - Presence   : siapa sedang di kota mana (CacheService, ringan)
 *   - Chat       : kanal pelabuhan & dunia (CacheService, 60 pesan terakhir)
 *   - Inbox      : notifikasi (tantangan duel, order terjual, hadiah)
 *   - Duel PvP   : duel kapal ber-ronde (taktik rahasia serentak) + duel dadu,
 *                  dengan taruhan gold yang di-escrow server
 *   - Bursa      : order jual antar-pemain per kota (sheet PlayerOrders)
 *   - Hadiah gold antar-pemain
 *   - Mini game  : mancing di dermaga & dadu besar/kecil di lapau
 *
 * Polling client (api_mpPulse) HANYA membaca CacheService - tidak menyentuh
 * sheet, supaya murah dan tidak menguras kuota walau dipanggil tiap
 * beberapa detik oleh banyak pemain.
 * ------------------------------------------------------------------
 */

var MP = (function () {
  var TTL = 21600;              // 6 jam (maks CacheService)
  var ONLINE_MS = 120000;       // dianggap online kalau pulse < 2 menit lalu
  var CHAT_MAX = 60;
  var ROUND_MS = 25000;         // batas waktu memilih taktik setelah lawan memilih
  var IDLE_MS = 60000;          // ronde tanpa aksi sama sekali
  var INVITE_MS = 60000;
  var MAX_ROUNDS = 12;

  function cache_() { return CacheService.getScriptCache(); }
  function cget(k) { var v = cache_().get(k); if (!v) return null; try { return JSON.parse(v); } catch (e) { return null; } }
  function cput(k, o, ttl) { cache_().put(k, JSON.stringify(o), ttl || TTL); }
  function now() { return Date.now(); }
  function uid(p) { return (p || '') + now().toString(36) + Math.floor(Math.random() * 1e6).toString(36); }
  function withLock_(fn, ms) {
    var lock = LockService.getScriptLock();
    if (!lock.tryLock(ms || 5000)) throw new Error('Server sedang sibuk, coba lagi sebentar.');
    try { return fn(); } finally { lock.releaseLock(); }
  }
  function me_() { return PlayerService.getCurrentPlayerId(); }
  /* id publik (tidak membocorkan email / id internal ke pemain lain) */
  var pubSalt_ = null;
  function pub_(playerId) {
    if (!pubSalt_) { var pr = PropertiesService.getScriptProperties(); pubSalt_ = pr.getProperty('pub_salt'); if (!pubSalt_) { pubSalt_ = Utilities.getUuid(); pr.setProperty('pub_salt', pubSalt_); } }
    var b = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, pubSalt_ + '|' + playerId, Utilities.Charset.UTF_8);
    return 'p' + b.slice(0, 7).map(function (x) { var v = (x < 0 ? x + 256 : x).toString(16); return v.length === 1 ? '0' + v : v; }).join('');
  }
  function unpub_(pub) {
    var id = cache_().get('pub:' + String(pub || ''));
    if (!id) throw new Error('Kapten itu sudah tidak terlihat di pelabuhan.');
    return id;
  }
  function clampInt(v, lo, hi) { v = Math.floor(Number(v) || 0); return Math.max(lo, Math.min(hi, v)); }
  function cleanText(t, max) { return String(t == null ? '' : t).replace(/[\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max || 140); }

  /* ============================ PRESENCE ============================ */
  function touchFromState(state) {
    try {
      var p = state.player || {}, v = state.voyage || {};
      var info = {
        id: p.playerId, n: p.characterName, a: p.archetype, f: state.appearance || null,
        t: state.ship ? Number(state.ship.Tier) || 1 : 1,
        c: state.city ? state.city.CityId : '', sea: !!v.inTransit, dest: v.inTransit ? v.destinationCityId : '',
        b: state.meta && state.meta.u ? Object.keys(state.meta.u).length : 0, ts: now()
      };
      info.pub = pub_(info.id);
      cput('pp:' + info.id, info);
      cache_().put('pub:' + info.pub, info.id, TTL);
      addToRoster_(info.id);
    } catch (e) { Logger.log('presence gagal: ' + e.message); }
  }
  function markSea(playerId, destCityId) {
    var info = cget('pp:' + playerId); if (!info) return;
    info.sea = true; info.dest = destCityId || ''; info.ts = now(); cput('pp:' + playerId, info);
  }
  function addToRoster_(id) {
    var r = cget('roster') || {};
    if (r[id] && now() - r[id] < 60000) return;
    var lock = LockService.getScriptLock();
    if (!lock.tryLock(1500)) return;
    try {
      r = cget('roster') || {}; r[id] = now();
      Object.keys(r).forEach(function (k) { if (now() - r[k] > 36 * 3600e3) delete r[k]; });
      cput('roster', r);
    } finally { lock.releaseLock(); }
  }
  function online_() {
    var r = cget('roster') || {}, ids = Object.keys(r);
    if (!ids.length) return [];
    var got = cache_().getAll(ids.map(function (i) { return 'pp:' + i; })), out = [];
    ids.forEach(function (i) { var v = got['pp:' + i]; if (!v) return; try { var o = JSON.parse(v); if (now() - o.ts < ONLINE_MS) out.push(o); } catch (e) {} });
    return out;
  }
  function publicInfo_(o) { return { id: o.pub, n: o.n, a: o.a, f: o.f, t: o.t, b: o.b || 0, sea: !!o.sea, c: o.c, dest: o.dest || '' }; }

  /* ============================ CHAT ============================ */
  function chatKey_(ch, city) { return ch === 'global' ? 'chat:g' : 'chat:c:' + city; }
  function postChat(channel, text) {
    var id = me_(), meInfo = cget('pp:' + id);
    if (!meInfo) throw new Error('Muat ulang game dulu sebelum mengobrol.');
    var tx = cleanText(text, 140);
    if (!tx) throw new Error('Pesan kosong.');
    var rl = 'rl:' + id;
    if (cache_().get(rl)) throw new Error('Pelan-pelan, Kapten - tunggu sebentar sebelum kirim lagi.');
    cache_().put(rl, '1', 2);
    var key = chatKey_(channel === 'global' ? 'global' : 'city', meInfo.c);
    return withLock_(function () {
      var arr = cget(key) || [];
      var msg = { id: (arr.length ? arr[arr.length - 1].id : 0) + 1, p: meInfo.pub, n: meInfo.n, a: meInfo.a, tx: tx, ts: now(), city: meInfo.c };
      arr.push(msg); if (arr.length > CHAT_MAX) arr = arr.slice(-CHAT_MAX);
      cput(key, arr);
      return { msg: msg };
    }, 3000);
  }
  function chatSince_(key, since) { var arr = cget(key) || []; since = Number(since) || 0; return arr.filter(function (m) { return m.id > since; }).slice(-30); }

  /* ============================ INBOX ============================ */
  function pushInbox(playerId, item) {
    item.id = item.id || uid('n'); item.ts = now();
    var key = 'ib:' + playerId;
    var lock = LockService.getScriptLock();
    var locked = lock.tryLock(2000);
    try {
      var arr = (cget(key) || []).filter(function (x) { return now() - x.ts < 15 * 60000; });
      arr.push(item); if (arr.length > 30) arr = arr.slice(-30);
      cput(key, arr, 3600);
    } finally { if (locked) lock.releaseLock(); }
  }

  /* ============================ PULSE ============================ */
  function pulse(since) {
    since = since || {};
    var id = me_(), info = cget('pp:' + id);
    if (!info) return { needState: true, t: now() };
    info.ts = now(); cput('pp:' + id, info); addToRoster_(id);
    var all = online_(), here = all.filter(function (o) { return o.id !== id && !o.sea && !info.sea && o.c === info.c; });
    var inbox = (cget('ib:' + id) || []).filter(function (x) { return x.ts > (Number(since.ib) || 0); });
    var duelId = cache_().get('dz:' + id), duel = null;
    if (duelId) { duel = cget('duel:' + duelId); if (duel) duel = view_(duel, id); }
    return {
      t: now(), me: { c: info.c, sea: info.sea },
      here: here.map(publicInfo_), online: all.length, onlineList: all.slice(0, 40).map(function (o) { return { id: o.pub, n: o.n, a: o.a, c: o.c, sea: !!o.sea, me: o.id === id }; }), mePub: info.pub,
      chat: { g: chatSince_('chat:g', since.g), c: info.sea ? [] : chatSince_('chat:c:' + info.c, since.c) },
      inbox: inbox, duel: duel
    };
  }

  function profile(pubId) {
    var playerId = unpub_(pubId);
    var o = cget('pp:' + playerId), p = PlayerService.getPlayerById(playerId);
    if (!p || !p.hasCharacter) throw new Error('Kapten tidak ditemukan.');
    var ship = null; try { ship = ShipService.getShip(playerId); } catch (e) {}
    var rec = pvpRec_(playerId), meta = null; try { meta = MetaStore_.get(playerId); } catch (e) {}
    return {
      id: pubId, n: p.characterName, a: p.archetype, f: (o && o.f) || AppearanceStore_.get(playerId),
      t: ship ? Number(ship.Tier) || 1 : 1, shipName: ship ? ship.ShipName : '', online: !!(o && now() - o.ts < ONLINE_MS),
      c: o ? o.c : '', sea: o ? !!o.sea : false, badges: meta && meta.u ? Object.keys(meta.u).length : 0, pvp: rec
    };
  }

  /* ============================ PvP RECORD ============================ */
  function pvpRec_(id) { try { var v = PropertiesService.getScriptProperties().getProperty('pvp:' + id); return v ? JSON.parse(v) : { w: 0, l: 0, d: 0, r: 1000 }; } catch (e) { return { w: 0, l: 0, d: 0, r: 1000 }; } }
  function pvpSave_(id, rec) { PropertiesService.getScriptProperties().setProperty('pvp:' + id, JSON.stringify(rec)); }
  function pvpUpdate_(winId, loseId, draw) {
    var a = pvpRec_(winId), b = pvpRec_(loseId);
    var ea = 1 / (1 + Math.pow(10, (b.r - a.r) / 400)), k = 32, sa = draw ? 0.5 : 1;
    a.r = Math.round(a.r + k * (sa - ea)); b.r = Math.round(b.r + k * ((1 - sa) - (1 - ea)));
    if (draw) { a.d++; b.d++; } else { a.w++; b.l++; }
    pvpSave_(winId, a); pvpSave_(loseId, b);
  }
  function pvpBoard() {
    var props = PropertiesService.getScriptProperties().getProperties(), rows = [];
    Object.keys(props).forEach(function (k) { if (k.indexOf('pvp:') === 0) { try { var r = JSON.parse(props[k]); r.id = k.substr(4); rows.push(r); } catch (e) {} } });
    rows.sort(function (x, y) { return y.r - x.r; });
    return rows.slice(0, 8).map(function (r) { var p = PlayerService.getPlayerById(r.id); return { n: p ? p.characterName : '?', a: p ? p.archetype : '', w: r.w, l: r.l, d: r.d, r: r.r }; });
  }

  /* ============================ DUEL ============================ */
  var TACTICS = ['fire', 'evade', 'ram', 'brace', 'reload'];
  function fighter_(playerId) {
    var p = PlayerService.getPlayerById(playerId), ship = ShipService.getShip(playerId), st = CharacterService.getCharacterStats(playerId) || {};
    var tier = Number(ship && ship.Tier) || 1, cond = ship ? Number(ship.ConditionPct) || 100 : 100;
    var o = cget('pp:' + playerId) || {};
    return {
      id: playerId, pub: o.pub || pub_(playerId), n: p.characterName, a: p.archetype, f: o.f || null, tier: tier,
      maxHp: 80 + tier * 20 + Math.round(cond / 5), atk: 12 + (Number(st.Combat) || 0) * 0.18 + (Number(ship && ship.Combat) || 0) * 1.2 + (Number(ship && ship.CannonBonusPercent) || 0) * 0.08,
      luck: Number(st.Luck) || 0, ammoMax: Math.min(6, Number(ship && ship.MaxCannonAmmo) || 3)
    };
  }
  function newDuel_(a, b, stake, kind) {
    return { id: uid('d'), kind: kind, stake: stake, status: 'invited', created: now(), a: a, b: b, round: 0, hp: {}, ammo: {}, pick: {}, pickTs: 0, roundTs: 0, afk: {}, log: [], last: null, winner: null };
  }
  function challenge(targetPub, stake, kind) {
    var id = me_(), targetId = unpub_(targetPub);
    kind = kind === 'dice' ? 'dice' : 'naval';
    if (targetId === id) throw new Error('Tidak bisa menantang diri sendiri.');
    stake = clampInt(stake, 0, 100000);
    var t = cget('pp:' + targetId);
    if (!t || now() - t.ts > ONLINE_MS) throw new Error('Kapten itu sedang tidak online.');
    if (cache_().get('dz:' + id)) throw new Error('Kamu masih punya duel yang belum selesai.');
    if (cache_().get('dz:' + targetId)) throw new Error(t.n + ' sedang berduel dengan kapten lain.');
    var loc = LocationService.getCurrentCityId(id), voy = LocationService.getVoyageState(id);
    if (voy.inTransit) throw new Error('Duel hanya bisa saat kapal merapat.');
    if (t.sea || t.c !== loc) throw new Error(t.n + ' tidak berada di pelabuhan yang sama.');
    var mp = PlayerService.getPlayerById(id);
    if (mp.gold < stake) throw new Error('Gold-mu tidak cukup untuk taruhan ' + stake + '.');
    var d = newDuel_(fighter_(id), fighter_(targetId), stake, kind);
    d.city = loc;
    cput('duel:' + d.id, d, 3600);
    cache_().put('dz:' + id, d.id, 900);
    pushInbox(targetId, { type: 'duel_invite', duelId: d.id, kind: kind, from: d.a.n, fromId: d.a.pub, stake: stake, fa: d.a.a, ff: d.a.f });
    return view_(d, id);
  }
  function respond(duelId, accept) {
    var id = me_();
    return withLock_(function () {
      var d = cget('duel:' + duelId);
      if (!d || d.b.id !== id) throw new Error('Tantangan tidak ditemukan atau sudah kedaluwarsa.');
      if (d.status !== 'invited') return view_(d, id);
      if (now() - d.created > INVITE_MS) { d.status = 'expired'; save_(d); throw new Error('Tantangan sudah kedaluwarsa.'); }
      if (!accept) { d.status = 'declined'; save_(d); release_(d); pushInbox(d.a.id, { type: 'duel_declined', duelId: d.id, from: d.b.n }); return view_(d, id); }
      if (cache_().get('dz:' + id) && cache_().get('dz:' + id) !== d.id) throw new Error('Selesaikan duelmu yang lain dulu.');
      var pa = PlayerService.getPlayerById(d.a.id), pb = PlayerService.getPlayerById(id);
      if (pb.gold < d.stake) throw new Error('Gold-mu tidak cukup untuk taruhan ' + d.stake + '.');
      if (pa.gold < d.stake) { d.status = 'cancelled'; save_(d); release_(d); throw new Error(d.a.n + ' sudah tidak punya cukup gold untuk taruhan ini.'); }
      if (LocationService.getCurrentCityId(id) !== d.city || LocationService.getVoyageState(id).inTransit) throw new Error('Kamu harus berada di pelabuhan yang sama.');
      // escrow taruhan dari kedua kapten
      if (d.stake > 0) {
        PlayerService.updatePlayerRow(d.a.id, { Gold: pa.gold - d.stake });
        PlayerService.updatePlayerRow(id, { Gold: pb.gold - d.stake });
      }
      cache_().put('dz:' + id, d.id, 3600); cache_().put('dz:' + d.a.id, d.id, 3600);
      if (d.kind === 'dice') {
        d.status = 'active'; rollDice_(d); finish_(d);
      } else {
        d.status = 'active'; d.round = 1; d.roundTs = now();
        d.hp[d.a.id] = d.a.maxHp; d.hp[id] = d.b.maxHp;
        d.ammo[d.a.id] = d.a.ammoMax; d.ammo[id] = d.b.ammoMax;
        d.afk[d.a.id] = 0; d.afk[id] = 0;
      }
      save_(d);
      pushInbox(d.a.id, { type: 'duel_start', duelId: d.id, from: d.b.n, kind: d.kind });
      return view_(d, id);
    });
  }
  function rollDice_(d) {
    var tries = 0, ra, rb;
    function r3() { return [1 + Math.floor(Math.random() * 6), 1 + Math.floor(Math.random() * 6), 1 + Math.floor(Math.random() * 6)]; }
    function sum(x) { return x[0] + x[1] + x[2]; }
    do { ra = r3(); rb = r3(); tries++; } while (sum(ra) === sum(rb) && tries < 3);
    d.dice = {}; d.dice[d.a.id] = ra; d.dice[d.b.id] = rb;
    d.winner = sum(ra) === sum(rb) ? 'draw' : (sum(ra) > sum(rb) ? d.a.id : d.b.id);
  }
  function act(duelId, round, tactic) {
    var id = me_();
    if (TACTICS.indexOf(tactic) < 0) throw new Error('Taktik tidak dikenal.');
    return withLock_(function () {
      var d = cget('duel:' + duelId);
      if (!d || (d.a.id !== id && d.b.id !== id)) throw new Error('Duel tidak ditemukan.');
      tick_(d);
      if (d.status !== 'active' || d.kind !== 'naval') { save_(d); return view_(d, id); }
      if (Number(round) !== d.round) return view_(d, id);
      if (tactic === 'fire' && d.ammo[id] <= 0) tactic = 'brace';
      if (!d.pick[id]) { d.pick[id] = tactic; d.afk[id] = 0; if (!d.pickTs) d.pickTs = now(); }
      if (d.pick[d.a.id] && d.pick[d.b.id]) resolve_(d);
      save_(d);
      return view_(d, id);
    });
  }
  function state(duelId) {
    var id = me_();
    var d = cget('duel:' + duelId);
    if (!d || (d.a.id !== id && d.b.id !== id)) throw new Error('Duel tidak ditemukan.');
    if (!needsTick_(d)) return view_(d, id);
    // batas waktu terlewati: proses di bawah lock (baca ulang supaya tidak dobel bayar)
    return withLock_(function () {
      var d2 = cget('duel:' + duelId);
      var before = d2.status + '|' + d2.round;
      tick_(d2);
      if (d2.status + '|' + d2.round !== before) save_(d2);
      return view_(d2, id);
    });
  }
  function needsTick_(d) {
    var t = now();
    if (d.status === 'invited') return t - d.created > INVITE_MS;
    if (d.status !== 'active' || d.kind !== 'naval') return false;
    var one = d.pick[d.a.id] || d.pick[d.b.id];
    return one ? t - d.pickTs > ROUND_MS : t - d.roundTs > IDLE_MS;
  }
  function forfeit(duelId) {
    var id = me_();
    return withLock_(function () {
      var d = cget('duel:' + duelId);
      if (!d || (d.a.id !== id && d.b.id !== id)) throw new Error('Duel tidak ditemukan.');
      if (d.status === 'invited' && d.a.id === id) { d.status = 'cancelled'; save_(d); release_(d); return view_(d, id); }
      if (d.status !== 'active') return view_(d, id);
      d.winner = d.a.id === id ? d.b.id : d.a.id; d.forfeit = id;
      finish_(d); save_(d);
      return view_(d, id);
    });
  }
  /** Timeout: lawan diam -> otomatis "Bertahan"; 3x diam -> kalah (menyerah). */
  function tick_(d) {
    if (d.status === 'invited' && now() - d.created > INVITE_MS) { d.status = 'expired'; release_(d); return d; }
    if (d.status !== 'active' || d.kind !== 'naval') return d;
    var ids = [d.a.id, d.b.id], t = now();
    var one = d.pick[ids[0]] || d.pick[ids[1]];
    if ((one && t - d.pickTs > ROUND_MS) || (!one && t - d.roundTs > IDLE_MS)) {
      ids.forEach(function (i) { if (!d.pick[i]) { d.pick[i] = 'brace'; d.afk[i] = (d.afk[i] || 0) + 1; } });
      var gone = ids.filter(function (i) { return d.afk[i] >= 3; });
      if (gone.length === 1) { d.winner = gone[0] === d.a.id ? d.b.id : d.a.id; d.forfeit = gone[0]; finish_(d); return d; }
      if (gone.length === 2) { d.winner = 'draw'; finish_(d); return d; }
      resolve_(d);
    }
    return d;
  }
  /** Inti pertempuran (murni, bisa diuji): taktik rahasia serentak ala batu-gunting-kertas. */
  function resolve_(d) {
    var A = d.a, B = d.b, pa = d.pick[A.id], pb = d.pick[B.id];
    var res = {}; res[A.id] = hitOn_(d, B, A, pb, pa); res[B.id] = hitOn_(d, A, B, pa, pb);
    // res[x] = damage yang DITERIMA x
    [A, B].forEach(function (F) {
      var tac = d.pick[F.id];
      if (tac === 'fire') d.ammo[F.id] = Math.max(0, d.ammo[F.id] - 1);
      if (tac === 'reload') d.ammo[F.id] = Math.min(F.ammoMax, d.ammo[F.id] + 2);
    });
    d.hp[A.id] = Math.max(0, d.hp[A.id] - res[A.id].dmg); d.hp[B.id] = Math.max(0, d.hp[B.id] - res[B.id].dmg);
    var entry = { r: d.round, pick: {}, dmg: {}, note: {} };
    entry.pick[A.id] = pa; entry.pick[B.id] = pb; entry.dmg[A.id] = res[A.id].dmg; entry.dmg[B.id] = res[B.id].dmg;
    entry.note[A.id] = res[A.id].note; entry.note[B.id] = res[B.id].note;
    d.log.push(entry); if (d.log.length > 14) d.log = d.log.slice(-14);
    d.last = entry;
    var deadA = d.hp[A.id] <= 0, deadB = d.hp[B.id] <= 0;
    if (deadA || deadB || d.round >= MAX_ROUNDS) {
      if (deadA && deadB) d.winner = 'draw';
      else if (deadA) d.winner = B.id;
      else if (deadB) d.winner = A.id;
      else { var ra = d.hp[A.id] / A.maxHp, rb = d.hp[B.id] / B.maxHp; d.winner = Math.abs(ra - rb) < 0.02 ? 'draw' : (ra > rb ? A.id : B.id); }
      finish_(d);
      return;
    }
    d.round++; d.pick = {}; d.pickTs = 0; d.roundTs = now();
  }
  /** Damage yang diterima `def` (memakai taktik td) dari `att` (taktik ta). */
  function hitOn_(d, att, def, ta, td) {
    var roll = 0.85 + Math.random() * 0.3 + Math.min(0.1, att.luck / 500);
    var base = att.atk * roll, dmg = 0, note = '';
    if (ta === 'fire') {
      if (td === 'evade') { if (Math.random() < 0.7) { note = 'dodge'; dmg = 0; } else { dmg = base; note = 'hit'; } }
      else if (td === 'brace') { dmg = base * 0.5; note = 'braced'; }
      else if (td === 'reload') { dmg = base * 1.35; note = 'exposed'; }
      else { dmg = base; note = 'hit'; }
    } else if (ta === 'ram') {
      if (td === 'brace') { dmg = base * 0.3; note = 'braced'; }
      else if (td === 'evade' || td === 'reload') { dmg = base * 1.7; note = 'rammed'; }
      else if (td === 'fire') { dmg = base * 0.9; note = 'rammed'; }
      else if (td === 'ram') { dmg = base * 1.1; note = 'clash'; }
    }
    // hentakan: menabrak kapal yang bertahan / ditembak saat menerjang
    if (td === 'ram' && ta === 'brace') { dmg += att.atk * 0.9; note = note || 'recoil'; }
    return { dmg: Math.round(dmg), note: note };
  }
  function finish_(d) {
    d.status = 'done'; d.ended = now();
    var pot = d.stake * 2;
    if (d.winner === 'draw') {
      if (d.stake) { [d.a.id, d.b.id].forEach(function (i) { var p = PlayerService.getPlayerById(i); PlayerService.updatePlayerRow(i, { Gold: p.gold + d.stake }); }); }
      try { pvpUpdate_(d.a.id, d.b.id, true); } catch (e) {}
    } else {
      var w = d.winner, l = w === d.a.id ? d.b.id : d.a.id;
      if (pot) { var pw = PlayerService.getPlayerById(w); PlayerService.updatePlayerRow(w, { Gold: pw.gold + pot }); }
      try { pvpUpdate_(w, l, false); } catch (e) {}
    }
    var nameA = d.a.n, nameB = d.b.n, what = d.kind === 'dice' ? 'duel dadu' : 'duel kapal';
    [d.a, d.b].forEach(function (F) {
      var other = F.id === d.a.id ? nameB : nameA;
      var msg = d.winner === 'draw' ? ('Seri dalam ' + what + ' melawan ' + other + '.') :
        (d.winner === F.id ? ('Menang ' + what + ' melawan ' + other + (d.stake ? ' (+' + d.stake + ' gold).' : '.')) : ('Kalah ' + what + ' melawan ' + other + (d.stake ? ' (-' + d.stake + ' gold).' : '.')));
      try { LogService.addLog(F.id, msg); } catch (e) {}
    });
    release_(d);
  }
  function release_(d) { try { cache_().remove('dz:' + d.a.id); cache_().remove('dz:' + d.b.id); } catch (e) {} }
  function save_(d) { cput('duel:' + d.id, d, 3600); }
  function view_(d, viewer) {
    var meSide = d.a.id === viewer ? 'a' : 'b', you = d[meSide], foe = d[meSide === 'a' ? 'b' : 'a'];
    var v = { id: d.id, kind: d.kind, status: d.status, stake: d.stake, round: d.round, maxRounds: MAX_ROUNDS, created: d.created, t: now(),
      you: { id: you.pub, n: you.n, a: you.a, f: you.f, tier: you.tier, maxHp: you.maxHp, hp: d.hp[you.id], ammo: d.ammo[you.id], ammoMax: you.ammoMax, picked: !!d.pick[you.id], pick: d.pick[you.id] || null },
      foe: { id: foe.pub, n: foe.n, a: foe.a, f: foe.f, tier: foe.tier, maxHp: foe.maxHp, hp: d.hp[foe.id], ammo: d.ammo[foe.id], ammoMax: foe.ammoMax, picked: !!d.pick[foe.id] },
      challenger: d.a.id === viewer, pickDeadline: d.pickTs ? d.pickTs + ROUND_MS : 0, roundTs: d.roundTs,
      winner: d.winner === 'draw' ? 'draw' : (d.winner ? (d.winner === viewer ? 'you' : 'foe') : null), forfeit: d.forfeit ? (d.forfeit === viewer ? 'you' : 'foe') : null
    };
    if (d.last) v.last = { r: d.last.r, youPick: d.last.pick[you.id], foePick: d.last.pick[foe.id], youDmg: d.last.dmg[you.id], foeDmg: d.last.dmg[foe.id], youNote: d.last.note[you.id], foeNote: d.last.note[foe.id] };
    if (d.dice) v.dice = { you: d.dice[you.id], foe: d.dice[foe.id] };
    return v;
  }

  /* ============================ BURSA (order antar-pemain) ============================ */
  var ORD = 'PlayerOrders', ORD_H = ['OrderId', 'SellerId', 'SellerName', 'CityId', 'CommodityId', 'Qty', 'Price', 'CreatedAt', 'Status'];
  function ordSheet_() {
    var sh = SheetCache.getSheet(ORD);
    if (!sh) {
      sh = SpreadsheetApp.getActiveSpreadsheet().insertSheet(ORD);
      sh.getRange(1, 1, 1, ORD_H.length).setValues([ORD_H]); sh.setFrozenRows(1);
      SheetCache.reset();
      sh = SheetCache.getSheet(ORD);
    }
    return sh;
  }
  function ordRows_() { ordSheet_(); return SheetCache.getData(ORD); }
  function ordObj_(r, i) { var c = getCommodityById(r[4]); return { orderId: r[0], sellerId: r[1], seller: r[2], cityId: r[3], commodityId: r[4], name: c ? c.name : r[4], qty: Number(r[5]), price: Number(r[6]), createdAt: r[7] instanceof Date ? r[7].toISOString() : String(r[7] || ''), status: r[8], _row: i + 1 }; }
  function listOrders() {
    var id = me_(), city = LocationService.getCurrentCityId(id), rows = ordRows_(), here = [], mine = [];
    for (var i = 1; i < rows.length; i++) {
      if (rows[i][8] !== 'open' || Number(rows[i][5]) <= 0) continue;
      var o = ordObj_(rows[i], i); delete o._row;
      if (o.sellerId === id) { o.mine = true; mine.push(o); }
      if (o.cityId === city) { o.mine = o.sellerId === id; delete o.sellerId; here.push(o); }
      else if (o.sellerId === id) delete o.sellerId;
    }
    mine.forEach(function (o) { delete o.sellerId; });
    here.sort(function (a, b) { return a.commodityId === b.commodityId ? a.price - b.price : (a.commodityId < b.commodityId ? -1 : 1); });
    return { cityId: city, orders: here, mine: mine, inTransit: LocationService.getVoyageState(id).inTransit };
  }
  function postOrder(commodityId, qty, price) {
    var id = me_();
    qty = clampInt(qty, 0, 100000); price = clampInt(price, 0, 999999);
    if (qty <= 0) throw new Error('Jumlah tidak valid.');
    if (price <= 0) throw new Error('Harga tidak valid.');
    if (!getCommodityById(commodityId)) throw new Error('Komoditas tidak dikenal.');
    return withLock_(function () {
      if (LocationService.getVoyageState(id).inTransit) throw new Error('Pasang order saat kapal merapat.');
      var city = LocationService.getCurrentCityId(id), rows = ordRows_(), open = 0;
      for (var i = 1; i < rows.length; i++) if (rows[i][1] === id && rows[i][8] === 'open' && Number(rows[i][5]) > 0) open++;
      if (open >= 6) throw new Error('Maksimal 6 order aktif. Batalkan salah satu dulu.');
      var have = CargoService.getCargo(id).filter(function (c) { return c.commodityId === commodityId; })[0];
      if (!have || have.qty < qty) throw new Error('Barang di palka tidak cukup.');
      CargoService.adjustQty(id, commodityId, -qty);
      var p = PlayerService.getPlayerById(id), oid = uid('o');
      ordSheet_().appendRow([oid, id, p.characterName, city, commodityId, qty, price, new Date(), 'open']);
      SheetCache.invalidate(ORD);
      var c = getCommodityById(commodityId);
      LogService.addLog(id, 'Memasang order Bursa: ' + qty + ' ' + (c ? c.name : commodityId) + ' @ ' + price + ' gold.');
      return { orderId: oid, ok: true };
    }, 10000);
  }
  function buyOrder(orderId, qty) {
    var id = me_();
    qty = clampInt(qty, 0, 100000);
    if (qty <= 0) throw new Error('Jumlah tidak valid.');
    return withLock_(function () {
      var rows = ordRows_(), o = null;
      for (var i = 1; i < rows.length; i++) if (rows[i][0] === orderId) { o = ordObj_(rows[i], i); break; }
      if (!o || o.status !== 'open' || o.qty <= 0) throw new Error('Order sudah tidak tersedia.');
      if (o.sellerId === id) throw new Error('Itu order milikmu sendiri.');
      if (LocationService.getVoyageState(id).inTransit || LocationService.getCurrentCityId(id) !== o.cityId) throw new Error('Kamu harus berada di kota order ini.');
      if (qty > o.qty) qty = o.qty;
      var total = qty * o.price, buyer = PlayerService.getPlayerById(id);
      if (buyer.gold < total) throw new Error('Gold tidak cukup (butuh ' + total + ').');
      var ship = ShipService.getShip(id), used = CargoService.getTotalCargoQty(id);
      if (used + qty > ship.EffectiveCargo) throw new Error('Palka tidak cukup. Sisa ruang: ' + (ship.EffectiveCargo - used) + '.');
      PlayerService.updatePlayerRow(id, { Gold: buyer.gold - total });
      var seller = PlayerService.getPlayerById(o.sellerId);
      if (seller) PlayerService.updatePlayerRow(o.sellerId, { Gold: seller.gold + total });
      CargoService.adjustQty(id, o.commodityId, qty);
      var left = o.qty - qty, sh = ordSheet_();
      sh.getRange(o._row, 6).setValue(left);
      if (left <= 0) sh.getRange(o._row, 9).setValue('filled');
      SheetCache.invalidate(ORD);
      LogService.addLog(id, 'Membeli ' + qty + ' ' + o.name + ' dari ' + o.seller + ' di Bursa seharga ' + total + ' gold.');
      LogService.addLog(o.sellerId, (buyer.characterName || 'Seorang kapten') + ' membeli ' + qty + ' ' + o.name + ' dari order Bursa-mu (+' + total + ' gold).');
      pushInbox(o.sellerId, { type: 'order_filled', from: buyer.characterName, qty: qty, name: o.name, gold: total });
      return { ok: true, qty: qty, total: total, newGold: buyer.gold - total, left: left };
    }, 10000);
  }
  function cancelOrder(orderId) {
    var id = me_();
    return withLock_(function () {
      var rows = ordRows_(), o = null;
      for (var i = 1; i < rows.length; i++) if (rows[i][0] === orderId) { o = ordObj_(rows[i], i); break; }
      if (!o || o.sellerId !== id) throw new Error('Order tidak ditemukan.');
      if (o.status !== 'open' || o.qty <= 0) throw new Error('Order sudah tidak aktif.');
      var here = !LocationService.getVoyageState(id).inTransit && LocationService.getCurrentCityId(id) === o.cityId, where = 'palka';
      var space = 0;
      if (here) { var ship = ShipService.getShip(id); space = ship.EffectiveCargo - CargoService.getTotalCargoQty(id); }
      if (here && space >= o.qty) CargoService.adjustQty(id, o.commodityId, o.qty);
      else { warehouseAdd_(id, o.cityId, o.commodityId, o.qty); where = 'gudang ' + o.cityId; }
      var sh = ordSheet_(); sh.getRange(o._row, 9).setValue('cancelled'); SheetCache.invalidate(ORD);
      LogService.addLog(id, 'Membatalkan order Bursa ' + o.qty + ' ' + o.name + ' (dikembalikan ke ' + where + ').');
      return { ok: true, returnedTo: where };
    }, 10000);
  }
  function warehouseAdd_(playerId, cityId, commodityId, qty) {
    var sh = SheetCache.getSheet('Warehouse'), data = SheetCache.getData('Warehouse');
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId && data[i][1] === cityId && data[i][2] === commodityId) { sh.getRange(i + 1, 4).setValue(Number(data[i][3]) + qty); SheetCache.invalidate('Warehouse'); return; }
    }
    sh.appendRow([playerId, cityId, commodityId, qty]); SheetCache.invalidate('Warehouse');
  }

  /* ============================ HADIAH ============================ */
  function gift(targetPub, amount) {
    var id = me_(), targetId = unpub_(targetPub);
    amount = clampInt(amount, 0, 1000000);
    if (amount <= 0) throw new Error('Jumlah tidak valid.');
    if (targetId === id) throw new Error('Tidak bisa mengirim ke diri sendiri.');
    return withLock_(function () {
      var me = PlayerService.getPlayerById(id), to = PlayerService.getPlayerById(targetId);
      if (!to || !to.hasCharacter) throw new Error('Kapten tujuan tidak ditemukan.');
      if (me.gold < amount) throw new Error('Gold tidak cukup.');
      PlayerService.updatePlayerRow(id, { Gold: me.gold - amount });
      PlayerService.updatePlayerRow(targetId, { Gold: to.gold + amount });
      LogService.addLog(id, 'Mengirim ' + amount + ' gold ke ' + to.characterName + '.');
      LogService.addLog(targetId, me.characterName + ' mengirimimu ' + amount + ' gold.');
      pushInbox(targetId, { type: 'gift', from: me.characterName, gold: amount });
      return { ok: true, newGold: me.gold - amount };
    }, 10000);
  }

  /* ============================ MINI GAME: MANCING ============================ */
  var FISH = [
    { id: 'sepatu', name: 'Sepatu Butut', v: 2, w: 6, zone: 0.34, sp: 0.8 },
    { id: 'teri', name: 'Ikan Teri', v: 18, w: 34, zone: 0.3, sp: 1.0 },
    { id: 'kembung', name: 'Ikan Kembung', v: 40, w: 24, zone: 0.25, sp: 1.2 },
    { id: 'tongkol', name: 'Tongkol', v: 80, w: 15, zone: 0.2, sp: 1.45 },
    { id: 'kakap', name: 'Kakap Merah', v: 150, w: 9, zone: 0.16, sp: 1.7 },
    { id: 'kerapu', name: 'Kerapu Macan', v: 240, w: 6, zone: 0.13, sp: 1.95 },
    { id: 'tuna', name: 'Tuna Sirip Kuning', v: 450, w: 3, zone: 0.1, sp: 2.25 },
    { id: 'dewa', name: 'Ikan Dewa', v: 1400, w: 0.8, zone: 0.07, sp: 2.7 }
  ];
  function day_() { try { return TimeService.getCurrentGameDay(); } catch (e) { return 0; } }
  function fishCast() {
    var id = me_();
    if (LocationService.getVoyageState(id).inTransit) throw new Error('Mancing di dermaga saat kapal merapat.');
    if (cache_().get('fc:' + id)) throw new Error('Umpan belum siap - tunggu sebentar.');
    var dk = 'fd:' + id + ':' + day_(), n = Number(cache_().get(dk) || 0);
    if (n >= 20) throw new Error('Ikan di dermaga sudah jinak hari ini. Coba lagi besok (hari-game berikutnya).');
    var st = CharacterService.getCharacterStats(id) || {}, luck = Number(st.Luck) || 0, boost = 1 + luck / 60;
    var total = 0, weights = FISH.map(function (f, i) { var w = f.w * (i >= 4 ? boost : 1); total += w; return w; });
    var r = Math.random() * total, pick = FISH[1];
    for (var i = 0; i < FISH.length; i++) { r -= weights[i]; if (r <= 0) { pick = FISH[i]; break; } }
    var cast = { id: uid('c'), fish: pick.id, t0: now(), wait: 1500 + Math.floor(Math.random() * 3500) };
    cput('fk:' + id, cast, 180); cache_().put('fc:' + id, '1', 5);
    return { castId: cast.id, waitMs: cast.wait, fish: { id: pick.id, name: pick.name, zone: pick.zone, speed: pick.sp, rarity: FISH.indexOf(pick) }, left: 20 - n };
  }
  function fishReel(castId, hit) {
    var id = me_(), c = cget('fk:' + id);
    if (!c || c.id !== castId) throw new Error('Umpan sudah lepas. Lempar lagi.');
    cache_().remove('fk:' + id);
    var f = FISH.filter(function (x) { return x.id === c.fish; })[0];
    if (!hit || now() > c.t0 + c.wait + 9000) return { caught: false, fish: { id: f.id, name: f.name } };
    var dk = 'fd:' + id + ':' + day_(); cache_().put(dk, String(Number(cache_().get(dk) || 0) + 1), 26 * 3600);
    return withLock_(function () {
      var st = CharacterService.getCharacterStats(id) || {}, p = PlayerService.getPlayerById(id);
      var gold = Math.round(f.v * (1 + (Number(st.Luck) || 0) / 200) * (0.9 + Math.random() * 0.25));
      PlayerService.updatePlayerRow(id, { Gold: p.gold + gold });
      if (f.v >= 240) LogService.addLog(id, 'Memancing ' + f.name + ' di dermaga dan menjualnya ' + gold + ' gold!');
      return { caught: true, fish: { id: f.id, name: f.name, rarity: FISH.indexOf(f) }, gold: gold, newGold: p.gold + gold };
    });
  }

  /* ============================ MINI GAME: DADU BESAR/KECIL ============================ */
  function dice(bet, pickSide) {
    var id = me_();
    bet = clampInt(bet, 0, 5000);
    if (bet < 10) throw new Error('Taruhan minimal 10 gold.');
    if (pickSide !== 'besar' && pickSide !== 'kecil') throw new Error('Pilih Besar atau Kecil.');
    var dk = 'dd:' + id + ':' + day_(), n = Number(cache_().get(dk) || 0);
    if (n >= 40) throw new Error('Bandar lapau sudah tutup meja untukmu hari ini.');
    return withLock_(function () {
      var p = PlayerService.getPlayerById(id);
      if (p.gold < bet) throw new Error('Gold tidak cukup untuk taruhan itu.');
      var d = [1 + Math.floor(Math.random() * 6), 1 + Math.floor(Math.random() * 6), 1 + Math.floor(Math.random() * 6)];
      var sum = d[0] + d[1] + d[2], triple = d[0] === d[1] && d[1] === d[2];
      var side = sum >= 11 ? 'besar' : 'kecil', win = !triple && side === pickSide;
      var newGold = p.gold + (win ? bet : -bet);
      PlayerService.updatePlayerRow(id, { Gold: newGold });
      cache_().put(dk, String(n + 1), 26 * 3600);
      return { dice: d, sum: sum, triple: triple, side: side, win: win, delta: win ? bet : -bet, newGold: newGold, left: 39 - n };
    });
  }

  return {
    touchFromState: touchFromState, markSea: markSea, pulse: pulse, postChat: postChat, profile: profile, pushInbox: pushInbox,
    challenge: challenge, respond: respond, act: act, state: state, forfeit: forfeit, pvpBoard: pvpBoard,
    listOrders: listOrders, postOrder: postOrder, buyOrder: buyOrder, cancelOrder: cancelOrder, gift: gift,
    fishCast: fishCast, fishReel: fishReel, dice: dice,
    _resolve: resolve_, _hitOn: hitOn_, _newDuel: newDuel_
  };
})();
