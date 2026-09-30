// Harness uji lokal: Postgres asli (PGlite, WASM) + tiruan kecil Supabase Auth.
// Pemakaian:
//   const H = await require('./harness').create();
//   const alice = await H.user('alice');            // login sebagai username
//   await alice.call('api_createCharacter', ['Alice', 'merchant', null]);
//   await H.expectError(() => alice.call('api_buy', [...]), /Gold tidak cukup/);
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { PGlite } = require('@electric-sql/pglite');

const MIG_DIR = path.join(__dirname, '..', 'supabase', 'migrations');

// Meniru bagian Supabase yang dipakai migrasi kita: role anon/authenticated,
// schema auth dengan uid()/email()/jwt(), dan schema realtime.send() (no-op).
const SUPABASE_STUB = `
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;
-- Seperti Supabase asli: fungsi baru di schema public otomatis bisa dieksekusi anon/authenticated
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text unique, created_at timestamptz default now());
create or replace function auth.uid() returns uuid language sql stable as $f$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $f$;
create or replace function auth.email() returns text language sql stable as $f$
  select nullif(current_setting('request.jwt.claim.email', true), '') $f$;
create or replace function auth.jwt() returns jsonb language sql stable as $f$
  select jsonb_build_object('sub', auth.uid(), 'email', auth.email()) $f$;
create schema if not exists realtime;
create table if not exists realtime.sent (id bigserial primary key, topic text, event text, payload jsonb, private boolean, at timestamptz default now());
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true) returns void
language sql as $f$ insert into realtime.sent(topic, event, payload, private) values (topic, event, payload, private) $f$;
`;

async function create(opts = {}) {
  const db = new PGlite();
  await db.exec(SUPABASE_STUB);
  const files = fs.readdirSync(MIG_DIR).filter(f => f.endsWith('.sql')).sort();
  for (const f of files) {
    if (opts.only && !opts.only(f)) continue;
    try { await db.exec(fs.readFileSync(path.join(MIG_DIR, f), 'utf8')); }
    catch (e) { e.message = `[migrasi ${f}] ${e.message}`; throw e; }
  }
  const H = {
    db,
    users: {},
    async sql(q, params) { return (await db.query(q, params || [])).rows; },
    async anon() { return mkClient(null, null); },
    async user(username) {
      if (H.users[username]) return H.users[username];
      const id = crypto.randomUUID(), email = `${username}@marantau.game`;
      await db.query('insert into auth.users(id, email) values ($1, $2)', [id, email]);
      return (H.users[username] = mkClient(id, email));
    },
    async expectError(fn, re) {
      try { await fn(); } catch (e) {
        if (re && !re.test(e.message)) throw new Error(`error salah: "${e.message}" (diharapkan ${re})`);
        return e.message;
      }
      throw new Error('seharusnya error ' + re);
    },
    // Majukan jam dunia (menggeser WorldStartTimestamp & semua timestamp voyage) untuk tes waktu
    async shiftTime(ms) {
      await db.query(`update game.config set value = (value::bigint - $1)::text where key = 'WorldStartTimestamp'`, [ms]);
      await db.query(`update game.player_location set depart_at = depart_at - ($1 || ' milliseconds')::interval, arrive_at = arrive_at - ($1 || ' milliseconds')::interval where depart_at is not null`, [String(ms)]);
    }
  };
  function mkClient(id, email) {
    return {
      id, email,
      async call(name, args) {
        const fn = name.toLowerCase();
        if (!/^api_[a-z0-9_]+$/.test(fn)) throw new Error('nama fungsi tidak valid ' + name);
        await db.query(`select set_config('request.jwt.claim.sub', $1, false), set_config('request.jwt.claim.email', $2, false)`, [id || '', email || '']);
        try {
          const r = await db.query(`select public.${fn}($1::jsonb) as r`, [JSON.stringify(args || [])]);
          return r.rows[0].r;
        } catch (e) {
          const err = new Error(e.message); err.pg = e; throw err;
        }
      }
    };
  }
  return H;
}

module.exports = { create, MIG_DIR };
