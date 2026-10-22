// A registry that mirrors one pnpm release (the wrapper's tarball and the
// native binary's package, from files) for tests/android/pnpm.sh, and
// answers the binary's package metadata as the mode says:
//   ok         every request
//   late-once  the first request is answered after LATE_MS (past the
//              downloader's 30 s timeout), the others at once
//   down       503 Service Unavailable for ever
// GET /__count says how many requests the binary's metadata saw. Prints its
// port, which the kernel picks.
// usage: node pnpm-registry.js <dir> <package> <mode>
//   <dir> holds wrapper.tgz and binary.tgz, and wrapper.json and
//   binary.json (npm view --json) of the two
const http = require('http');
const fs = require('fs');
const [dir, packageName, mode] = process.argv.slice(2);
const lateMs = Number(process.env.LATE_MS || 31000);
const file = (name) => fs.readFileSync(`${dir}/${name}`);
const base = packageName.split('/')[1];
let seen = 0;
http.createServer((req, res) => {
  const url = req.url.replace(/%2f/gi, '/');
  if (url === '/__count') { res.end(String(seen)); return; }
  if (url === '/pnpm/-/pnpm-12.9.1.tgz') { res.end(file('wrapper.tgz')); return; }
  if (url === '/pnpm/12.9.1') { res.setHeader('content-type', 'application/json'); res.end(file('wrapper.json')); return; }
  if (url === `/${packageName}/-/${base}-12.9.1.tgz`) { res.end(file('binary.tgz')); return; }
  if (url === `/${packageName}/12.9.1`) {
    seen += 1;
    if (mode === 'down') { res.statusCode = 503; res.end('down'); return; }
    const answer = () => { res.setHeader('content-type', 'application/json'); res.end(file('binary.json')); };
    if (mode === 'late-once' && seen === 1) { setTimeout(answer, lateMs); return; }
    answer(); return;
  }
  res.statusCode = 404; res.end(`no ${req.url}`);
}).listen(0, '127.0.0.1', function () { console.log(this.address().port); });
