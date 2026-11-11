const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const b = await chromium.launch();
  for (const f of process.argv.slice(2)) {
    const svg = fs.readFileSync(f, 'utf8');
    const m = svg.match(/viewBox="0 0 (\d+) (\d+)"/);
    const w = +m[1], h = +m[2];
    const p = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
    await p.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await p.screenshot({ path: f.replace(/\.svg$/, '.png'), omitBackground: true });
    await p.close();
  }
  await b.close();
})();
