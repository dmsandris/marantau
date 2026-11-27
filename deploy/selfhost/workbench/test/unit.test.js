// Tes unit tanpa database/jaringan: penjagaan jalur & rahasia PR, pengaturan profil. Jalankan: node --test test/unit.test.js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
process.env.OPS_PG_HOST = '127.0.0.1';
const tools = require('../tools');
const settings = require('../settings');

test('checkFiles menolak jalur dan isi berbahaya', () => {
  const bad = [
    { path: '.github/workflows/x.yml', content: 'a' }, { path: 'a/.env', content: 'a' }, { path: '../x.sql', content: 'a' },
    { path: 'a.sql', content: 'ghp_' + 'a'.repeat(36) }, { path: 'a.sql', content: '-----BEGIN PRIVATE KEY-----' }, { path: 'a.exe', content: 'a' },
    { path: 'deploy/selfhost/volumes/x.sql', content: 'a' },
  ];
  for (const f of bad) assert.throws(() => tools.checkFiles([f]), undefined, f.path);
  assert.throws(() => tools.checkFiles([]));
  assert.throws(() => tools.checkFiles(Array.from({ length: 13 }, (_, i) => ({ path: `a${i}.sql`, content: 'x' }))));
  assert.throws(() => tools.checkFiles([{ path: 'a.sql', content: 'x' }, { path: 'a.sql', content: 'y' }]));
});
test('checkFiles menerima migrasi biasa', () => {
  const r = tools.checkFiles([{ path: 'supabase/migrations/0108-hadiah.sql', content: 'select 1;' }]);
  assert.strictEqual(r[0].path, 'supabase/migrations/0108-hadiah.sql');
});
test('safePath menolak traversal dan .git', () => {
  assert.throws(() => tools.safePath('../a')); assert.throws(() => tools.safePath('a/.git/config'));
  assert.strictEqual(tools.safePath('/a/b/'), 'a/b');
});
test('pengaturan: kunci tak pernah keluar utuh, kunci lama dipertahankan, peran dibersihkan', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wb-'));
  const s = settings.create(dir, {});
  s.ubah({ profiles: [{ id: 'a', label: 'A', provider: 'anthropic', model: 'claude-opus-5-5', key: 'sk-ant-SECRETSECRETSECRET1234' }, { id: 'b', label: 'B', provider: 'gemini', model: 'gemini-2.5-pro', key: 'AIzaSECRET' }], roles: { orkestrator: 'a', gambar: 'b' } });
  assert.ok(!JSON.stringify(s.publik()).includes('SECRET'));
  s.ubah({ profiles: [{ id: 'a', label: 'A2', provider: 'anthropic', model: 'claude-opus-5-5' }] });
  assert.strictEqual(s.profile('a').key, 'sk-ant-SECRETSECRETSECRET1234');
  assert.strictEqual(s.get().roles.gambar, '');           // profil b dihapus -> peran dikosongkan
  assert.strictEqual(s.forRole('coder').id, 'a');           // peran kosong -> ikut orkestrator
  assert.strictEqual(s.forRole('gambar'), null);            // gambar tidak jatuh ke orkestrator
  assert.strictEqual(fs.statSync(path.join(dir, 'wb-settings.json')).mode & 0o777, 0o600);
  s.ubah({ profiles: [{ id: 'x', label: 'X', provider: 'openai', model: 'm1', baseUrl: 'http://evil', key: 'k' }] });
  assert.strictEqual(s.profile('x').baseUrl, '');           // hanya https
});

// ---- Pengaman PR (kasus #124: berkas ditulis ulang terpotong, tag alat bocor ke isi berkas) ----
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'wb-repo-'));
fs.mkdirSync(path.join(dataDir, 'repo/web/src'), { recursive: true });
const big = '<style>\n' + Array.from({ length: 300 }, (_, i) => `.k${i}{color:red}`).join('\n') + '\n</style>\n';
fs.writeFileSync(path.join(dataDir, 'repo/web/src/Gaya.html'), big);
fs.writeFileSync(path.join(dataDir, 'repo/web/src/Dobel.html'), '<script>\nvar a=1;\nvar a=1;\n</script>\n');
fs.writeFileSync(path.join(dataDir, 'repo/catatan.md'), '# Catatan\nlama\n');
test('inspect: pengaman berkas (jalankan terpisah karena REPO_DIR dibaca saat load)', async () => {
  const sp = require('child_process').spawnSync(process.execPath, ['-e', `
    process.env.WB_DATA=${JSON.stringify(dataDir)}; process.env.OPS_PG_HOST='x';
    const t=require(${JSON.stringify(path.resolve(__dirname, '../tools.js'))}); const assert=require('assert'); const fs=require('fs'); const big=${JSON.stringify(big)};
    (async()=>{
      const m=async(f,o)=>(await t.inspect([f],o))[0];
      // 1. tulis ulang berkas ada (seperti #124) ditolak
      let r=await m({path:'web/src/Gaya.html',content:'<style>\\n.a{}\\n</style>\\n'}); assert(/Mengganti seluruh isi.*dilarang/.test(r.masalah.join()), 'timpa ditolak');
      // 2. tambalan kecil lolos, dan hasil = berkas asli + 1 perubahan
      r=await m({path:'web/src/Gaya.html',ops:[{cari:'.k5{color:red}',ganti:'.k5{color:blue}'}]}); assert(!r.masalah.length && r.plus===1 && r.minus===1 && !r.baru,'tambal ok '+JSON.stringify(r.masalah));
      // 3. cari yang tidak ada / ganda ditolak
      r=await m({path:'web/src/Gaya.html',ops:[{cari:'.tidak-ada{}',ganti:'x'}]}); assert(/tidak ditemukan/.test(r.masalah.join()));
      r=await m({path:'web/src/Dobel.html',ops:[{cari:'var a=1;',ganti:'var a=2;'}]}); assert(/muncul 2 kali/.test(r.masalah.join()));
      // 4. tambalan yang merusak sintaks / tag ditolak
      r=await m({path:'web/src/Dobel.html',ops:[{cari:'var a=1;\\nvar a=1;',ganti:'function ('}]}); assert(/Galat sintaks/.test(r.masalah.join()));
      r=await m({path:'web/src/Gaya.html',ops:[{cari:'</style>',ganti:''}]}); assert(/tidak pernah ditutup/.test(r.masalah.join()));
      // 5. pemangkasan besar lewat tambalan ditolak kecuali diizinkan
      r=await m({path:'web/src/Gaya.html',ops:[{cari:big.split('\\n').slice(1,260).join('\\n'),ganti:'.z{}'}]}); assert(/memangkas besar/.test(r.masalah.join()),'pangkas ditolak');
      r=await m({path:'web/src/Gaya.html',ops:[{cari:big.split('\\n').slice(1,260).join('\\n'),ganti:'.z{}'}]},{izinkanHapus:['web/src/Gaya.html']}); assert(!r.masalah.length,'pangkas diizinkan');
      // 6. placeholder dan tag bocor ditolak (berkas baru)
      r=await m({path:'web/src/Baru.html',content:'<script>\\nfunction a(){}\\n// ... existing code\\n</script>'}); assert(/existing code|kode lama/.test(r.masalah.join()));
      r=await m({path:'web/src/Baru.html',content:'<script>\\nvar x=1;\\n</script>\\n<antml nama="repo_read">a</antml>'}); assert(/sisa tag/.test(r.masalah.join()));
      // 7. berkas baru valid lolos; .md boleh ditulis ulang
      r=await m({path:'supabase/migrations/0200-x.sql',content:'select 1;'}); assert(!r.masalah.length && r.baru);
      r=await m({path:'catatan.md',content:'# Catatan\\nbaru\\n'}); assert(!r.masalah.length && !r.baru);
      // 8. berkas CRLF
      fs.writeFileSync(${JSON.stringify(path.join(dataDir, 'repo/crlf.js'))}, 'var a = 1;\\r\\nvar b = 2;\\r\\n');
      r=await m({path:'crlf.js',ops:[{cari:'var a = 1;\\nvar b = 2;',ganti:'var a = 9;\\nvar b = 2;'}]}); assert(!r.masalah.length,'crlf '+r.masalah);
      console.log('OK');
    })().catch(e=>{console.log('GAGAL',e.message);process.exit(1)});
  `], { encoding: 'utf8' }); const out = sp.stdout + sp.stderr;
  assert.match(out, /OK/, out.slice(0, 600));
});
test('settings: preset penyedia tersedia dan model gaya Cloudflare diterima', () => {
  assert.ok(['openrouter', 'groq', 'cloudflare'].every(id => settings.PRESETS.some(p => p.id === id)));
  assert.strictEqual(settings.PRESETS.find(p => p.id === 'groq').baseUrl, 'https://api.groq.com/openai/v1');
  const s = settings.create(fs.mkdtempSync(path.join(os.tmpdir(), 'wb-')), {});
  s.ubah({ profiles: [{ id: 'cf', label: 'CF', provider: 'openai', baseUrl: 'https://api.cloudflare.com/client/v4/accounts/' + 'a'.repeat(32) + '/ai/v1', model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast', key: 'k' }] });
  assert.strictEqual(s.profile('cf').model, '@cf/meta/llama-3.3-70b-instruct-fp8-fast');
  assert.ok(s.profile('cf').baseUrl.endsWith('/ai/v1'));
});
