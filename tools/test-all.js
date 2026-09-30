// Jalankan semua tes (test/0*.test.js) berurutan. Keluar kode 1 bila ada yang gagal.
const { execFileSync } = require('child_process'), fs = require('fs'), path = require('path');
const dir = path.join(__dirname, '..', 'test');
let bad = 0;
for (const f of fs.readdirSync(dir).filter(f => /^0.*\.test\.js$/.test(f)).sort()) {
  process.stdout.write(f.padEnd(34));
  try { const out = execFileSync('node', [path.join(dir, f)], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    console.log('OK  ' + out.trim().split('\n').pop()); }
  catch (e) { bad++; console.log('GAGAL'); console.log((e.stdout || '') + (e.stderr || '')); }
}
if (bad) { console.error(bad + ' tes gagal.'); process.exit(1); }
console.log('Semua tes lulus.');
