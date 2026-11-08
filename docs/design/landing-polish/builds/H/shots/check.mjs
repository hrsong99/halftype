import { chromium } from '/Users/johnsong/.npm/_npx/dd4723f69cd11a73/node_modules/playwright/index.mjs';
const OUT = process.argv[2], URL = 'http://127.0.0.1:8765/builds/H/index.html';
const b = await chromium.launch({ executablePath: '/Users/johnsong/Library/Caches/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-mac-arm64/chrome-headless-shell' });
const measure = p => p.evaluate(() => {
  const sizes = new Set(); const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n; n = w.nextNode();) { if (!n.textContent.trim()) continue; const e = n.parentElement, cs = getComputedStyle(e); if (cs.display === 'none' || cs.visibility === 'hidden' || !e.getClientRects().length || e.closest('.sr,.skip,[hidden]')) continue; sizes.add(parseFloat(cs.fontSize)); }
  const r = s => { const e = document.querySelector(s); if (!e) return null; const x = e.getBoundingClientRect(); return [Math.round(x.left), Math.round(x.right), Math.round(x.top + scrollY), Math.round(x.height)]; };
  const faq = [...document.querySelectorAll('.faq dd')].map(d => Math.round(d.getBoundingClientRect().height));
  return { sw: document.documentElement.scrollWidth, vw: innerWidth, sizes: [...sizes].sort((a, b) => a - b),
    faqH: faq, faqLink: r('.faq dd a'), msg: r('.app--msg'), notes: r('.app--mail'), chat: r('.app--chat'), keys: r('.keys'), charts: r('.charts'), wrap: r('#keys .wrap'),
    hint: r('.hint'), escMini: r('.key:nth-child(3) .mini:last-of-type'), realHead: r('#real-h'), win: r('.win--big'), pause: getComputedStyle(document.querySelector('#pause')).display };
});
const results = {};
for (const [name, w, h, rm] of [['1440', 1440, 900], ['1440-reduced', 1440, 900, 'reduce'], ['1024', 1024, 800], ['768', 768, 1024], ['390', 390, 844], ['320', 320, 640]]) {
  const p = await b.newPage({ viewport: { width: w, height: h }, reducedMotion: rm || 'no-preference' });
  const errs = []; p.on('console', m => m.type() === 'error' && errs.push(m.text())); p.on('pageerror', e => errs.push(String(e)));
  await p.goto(URL, { waitUntil: 'networkidle' }); await p.waitForTimeout(rm ? 500 : 5000);
  await p.screenshot({ path: `${OUT}/${name}-first.png` });
  // scroll through so per-card triggers and demos play, then back
  for (let y = 0; y < await p.evaluate(() => document.body.scrollHeight); y += h / 2) { await p.evaluate(y => scrollTo(0, y), y); await p.waitForTimeout(rm ? 50 : 700); }
  await p.evaluate(() => scrollTo(0, 0)); await p.waitForTimeout(300);
  await p.screenshot({ path: `${OUT}/${name}-full.png`, fullPage: true });
  results[name] = { errs, ...(await measure(p)) };
  await p.close();
}
// Runtime reduced motion toggle at 1440
{
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(URL, { waitUntil: 'networkidle' }); await p.waitForTimeout(1500);
  const snap = () => p.evaluate(() => ({ hero: document.querySelector('#hero-text').innerHTML, off: document.querySelector('.ribbon textPath').getAttribute('startOffset'), pause: getComputedStyle(document.querySelector('#pause')).display, caret: getComputedStyle(document.querySelector('#hero-text .caret')).animationName }));
  const a0 = await snap(); await p.waitForTimeout(800); const a1 = await snap();
  await p.emulateMedia({ reducedMotion: 'reduce' }); await p.waitForTimeout(300);
  const r0 = await snap(); await p.waitForTimeout(2500); const r1 = await snap();
  // the Mail beat while reduced: scroll to it
  await p.evaluate(() => document.querySelector('#real-text').scrollIntoView({ block: 'center' })); await p.waitForTimeout(300);
  const m0 = await p.evaluate(() => document.querySelector('#real-text').innerHTML); await p.waitForTimeout(1500);
  const m1 = await p.evaluate(() => document.querySelector('#real-text').innerHTML);
  await p.emulateMedia({ reducedMotion: 'no-preference' }); await p.waitForTimeout(1500);
  const m2 = await p.evaluate(() => document.querySelector('#real-text').innerHTML);
  await p.evaluate(() => scrollTo(0, 0)); await p.waitForTimeout(800); const b0 = await snap(); await p.waitForTimeout(800); const b1 = await snap();
  results.toggle = { errs, beforeMoves: a0.hero !== a1.hero && a0.off !== a1.off, reducedStill: r0.hero === r1.hero && r0.off === r1.off, reducedPause: r0.pause, reducedCaret: r0.caret,
    mailStillReduced: m0 === m1, mailResumes: m1 !== m2, afterMoves: b0.hero !== b1.hero && b0.off !== b1.off, afterPause: b0.pause };
  // pause stops ribbon rAF; start reduced then switch on
  await p.click('#pause'); const pz0 = await snap(); await p.waitForTimeout(800); const pz1 = await snap();
  results.toggle.pausedStill = pz0.hero === pz1.hero && pz0.off === pz1.off;
  await p.close();
  const q = await b.newPage({ viewport: { width: 1440, height: 900 }, reducedMotion: 'reduce' });
  await q.goto(URL, { waitUntil: 'networkidle' }); await q.waitForTimeout(500);
  await q.emulateMedia({ reducedMotion: 'no-preference' }); await q.waitForTimeout(600);
  const c0 = await q.evaluate(() => [document.querySelector('#hero-text').innerHTML, getComputedStyle(document.querySelector('#pause')).display]); await q.waitForTimeout(900);
  const c1 = await q.evaluate(() => document.querySelector('#hero-text').innerHTML);
  results.loadReducedThenOff = { moves: c0[0] !== c1, pause: c0[1] };
  // clipboard failure
  await q.evaluate(() => { Object.defineProperty(navigator, 'clipboard', { value: { writeText: () => Promise.reject(new Error('no')) } }); });
  await q.click('.hero [data-copy]'); await q.waitForTimeout(200);
  results.clip = await q.evaluate(() => ({ pre: document.querySelector('.brew-lines')?.textContent, sel: String(getSelection()), btn: document.querySelector('.hero [data-copy]').textContent }));
  await q.locator('.install').first().screenshot({ path: `${OUT}/clipboard-fallback.png` });
  await q.close();
}
console.log(JSON.stringify(results, null, 1));
await b.close();
