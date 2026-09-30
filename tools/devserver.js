// Server uji lokal: menyajikan dist/ + meniru Supabase (Auth + RPC) di atas PGlite.
// Pemakaian: node tools/devserver.js [port]   lalu buka http://localhost:8787/
// HANYA untuk uji di komputer pengembang - bukan untuk produksi.
const http = require('http'), fs = require('fs'), path = require('path'), crypto = require('crypto');
const PORT = Number(process.argv[2] || 8787);
const DIST = path.join(__dirname, '..', 'dist');

(async () => {
  const H = await require('../test/harness').create();
  const db = H.db;
  const pw = {}, tokens = {}; // email -> hash, token -> {id,email}
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  function session(u) {
    const exp = Math.floor(Date.now() / 1000) + 3600;
    const access = b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64({ sub: u.id, email: u.email, role: 'authenticated', aud: 'authenticated', exp }) + '.' + crypto.randomBytes(16).toString('base64url');
    const refresh = crypto.randomBytes(16).toString('hex');
    tokens[access] = u; tokens['r:' + refresh] = u;
    return { access_token: access, refresh_token: refresh, token_type: 'bearer', expires_in: 3600, expires_at: exp,
      user: { id: u.id, aud: 'authenticated', role: 'authenticated', email: u.email, app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() } };
  }
  const hash = p => crypto.createHash('sha256').update(p).digest('hex');
  async function body(req) { let s = ''; for await (const c of req) s += c; try { return JSON.parse(s || '{}'); } catch (e) { return {}; } }
  function send(res, code, obj, type) {
    res.writeHead(code, { 'content-type': type || 'application/json', 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' });
    res.end(type ? obj : JSON.stringify(obj));
  }
  const ANON_OK = new Set();
  const grants = await H.sql(`select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'api_%' and has_function_privilege('anon', p.oid, 'execute')`);
  grants.forEach(r => ANON_OK.add(r.proname));

  http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    if (req.method === 'OPTIONS') return send(res, 204, '', 'text/plain');
    try {
      const auth = (req.headers.authorization || '').replace(/^Bearer /, '');
      const user = tokens[auth] || null;
      if (url.pathname === '/auth/v1/signup') {
        const b = await body(req);
        const ex = await H.sql('select id from auth.users where email = $1', [b.email]);
        if (ex.length) return send(res, 422, { code: 422, error_code: 'user_already_exists', msg: 'User already registered' });
        const id = crypto.randomUUID();
        await H.sql('insert into auth.users(id, email) values ($1, $2)', [id, b.email]);
        pw[b.email] = hash(b.password);
        return send(res, 200, session({ id, email: b.email }));
      }
      if (url.pathname === '/auth/v1/token') {
        const b = await body(req);
        if (url.searchParams.get('grant_type') === 'refresh_token') {
          const u = tokens['r:' + b.refresh_token]; if (!u) return send(res, 400, { error: 'invalid_grant', error_description: 'Invalid Refresh Token' });
          return send(res, 200, session(u));
        }
        const r = await H.sql('select id from auth.users where email = $1', [b.email]);
        if (!r.length || pw[b.email] !== hash(b.password)) return send(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials', code: 'invalid_credentials', msg: 'Invalid login credentials' });
        return send(res, 200, session({ id: r[0].id, email: b.email }));
      }
      if (url.pathname === '/auth/v1/user') {
        if (!user) return send(res, 401, { msg: 'invalid JWT' });
        if (req.method === 'PUT') { const b = await body(req); if (b.password) pw[user.email] = hash(b.password); }
        return send(res, 200, session(user).user);
      }
      if (url.pathname === '/auth/v1/logout') { delete tokens[auth]; return send(res, 204, '', 'text/plain'); }
      const m = url.pathname.match(/^\/rest\/v1\/rpc\/([a-z0-9_]+)$/);
      if (m) {
        const fn = m[1], b = await body(req);
        if (!user && !ANON_OK.has(fn)) return send(res, 401, { code: '42501', message: `permission denied for function ${fn}` });
        await db.query(`select set_config('request.jwt.claim.sub', $1, false), set_config('request.jwt.claim.email', $2, false)`, [user ? user.id : '', user ? user.email : '']);
        try {
          const r = await db.query(`select public.${fn}($1::jsonb) as r`, [JSON.stringify(b.a || [])]);
          if (process.env.SLOW) await new Promise(r => setTimeout(r, Number(process.env.SLOW)));
          return send(res, 200, r.rows[0].r);
        } catch (e) { return send(res, 400, { code: 'P0001', message: e.message }); }
      }
      if (url.pathname.startsWith('/__sql') && process.env.DEVSQL) { const b = await body(req); return send(res, 200, await H.sql(b.q, b.p)); }
      // statis
      let p = url.pathname === '/' ? '/index.html' : url.pathname;
      if (p === '/config.js') return send(res, 200, `window.MT_CONFIG={supabaseUrl:'http://localhost:${PORT}',supabaseKey:'sb_publishable_local',emailDomain:'marantau.game'};`, 'application/javascript');
      const f = path.join(DIST, path.normalize(p));
      if (!f.startsWith(DIST) || !fs.existsSync(f)) return send(res, 404, 'not found', 'text/plain');
      const type = f.endsWith('.html') ? 'text/html; charset=utf-8' : f.endsWith('.js') ? 'application/javascript' : 'application/octet-stream';
      return send(res, 200, fs.readFileSync(f), type);
    } catch (e) { console.error(e); return send(res, 500, { message: e.message }); }
  }).listen(PORT, () => console.log('devserver http://localhost:' + PORT));
})();
