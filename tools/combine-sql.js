// Gabungkan semua migrasi jadi satu file: dist/marantau_all.sql
// Cadangan kalau deploy otomatis belum jalan: buka file itu, salin semua, tempel di Supabase > SQL Editor > Run.
const fs = require('fs'), path = require('path');
const dir = path.join(__dirname, '..', 'supabase', 'migrations');
const out = path.join(__dirname, '..', 'dist', 'marantau_all.sql');
fs.mkdirSync(path.dirname(out), { recursive: true });
const parts = fs.readdirSync(dir).filter(f => f.endsWith('.sql')).sort()
  .map(f => `-- ===== ${f} =====\n` + fs.readFileSync(path.join(dir, f), 'utf8'));
fs.writeFileSync(out, 'begin;\n' + parts.join('\n\n') + '\ncommit;\n');
console.log(out, Math.round(fs.statSync(out).size / 1024) + ' KB');
