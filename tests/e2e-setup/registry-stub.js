// A registry that serves one tarball and resets the connection of the
// first N requests (GET /__reset/N sets N again; GET /__count says how
// many requests it saw). Prints its port, which the kernel picks.
const http = require('http');
const fs = require('fs');
const tarball = fs.readFileSync(process.argv[2]);
let resets = 0;
let seen = 0;
http.createServer((req, res) => {
  const m = /^\/__reset\/(\d+)$/.exec(req.url);
  if (m) { resets = Number(m[1]); seen = 0; res.end('ok'); return; }
  if (req.url === '/__count') { res.end(String(seen)); return; }
  seen += 1;
  if (resets > 0) { resets -= 1; req.socket.destroy(); return; }
  res.setHeader('content-type', 'application/octet-stream');
  res.end(tarball);
}).listen(0, '127.0.0.1', function () { console.log(this.address().port); });
