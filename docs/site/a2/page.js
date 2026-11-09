// Halftype landing: marks, nav border, copy, and the motion. Three demos (hero field, Mail beat, Korean),
// each running only while on screen; the nav's one pause control holds them and every CSS animation (rule 16).
const rmq = matchMedia('(prefers-reduced-motion: reduce)');
const $ = s => document.querySelector(s);

$('#mark').innerHTML = MARK;
$('.mark2').innerHTML = MARK.replace(/hta/g, 'hta2');

const navEl = $('.nav');
addEventListener('scroll', () => navEl.classList.toggle('scrolled', scrollY > 8), { passive: true });

const BREW = 'brew tap hrsong99/halftype && brew trust hrsong99/halftype\nbrew install --cask halftype';
document.querySelectorAll('[data-copy]').forEach(b => b.addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(BREW); b.textContent = 'Copied'; setTimeout(() => { b.textContent = 'Copy'; }, 1600); }
  catch {
    // No clipboard: show both lines, selected, for Cmd-C.
    const brew = b.closest('.brew');
    let pre = brew.nextElementSibling;
    if (!pre || !pre.matches('.brew-lines')) { pre = document.createElement('pre'); pre.className = 'brew-lines'; pre.textContent = BREW; brew.after(pre); }
    getSelection().selectAllChildren(pre);
    b.textContent = 'Select below';
  }
}));

// Motion.held (demo.js's gate) is the pause control or reduced motion, which can change after load.
const pauseBtn = $('#pause'), root = document.documentElement;
let paused = false;
const heroOut = $('#hero-text'), realOut = $('#real-text'), koOut = $('#ko-text'), realKey = $('#real-key');
const keysEl = $('.keys'), cards = [...keysEl.querySelectorAll('.key')];
const rt = $('.ribbon textPath'), rpath = $('#rp'), ribbon = $('.ribbon');
const STILL = new Map([[heroOut, "Thanks for the update. I'll t<span class=\"caret\"></span><span class=\"ghost\">ake a look and get back to you.</span>"],
  [realOut, realOut.innerHTML], [koOut, koOut.innerHTML]]);
const afters = cards.map(c => c.querySelectorAll('.mini')[1].innerHTML);
const done = new Set();  // key cards that have played

function update() {
  const reduced = rmq.matches;
  Motion.held = paused || reduced;
  root.classList.toggle('reduced', reduced);
  root.classList.toggle('held', paused && !reduced);
  pauseBtn.hidden = reduced;
  if (reduced) {
    // Still, finished states.
    STILL.forEach((html, el) => { el.innerHTML = html; });
    document.querySelectorAll('.kc.down').forEach(k => k.classList.remove('down'));
    realKey.textContent = 'tab';
    cards.forEach((c, i) => { c.querySelectorAll('.mini')[1].innerHTML = afters[i]; c.classList.add('played'); done.add(c); });
  }
  Motion.wake(); ribbonRun();
}

const io = new IntersectionObserver(es => {
  es.forEach(e => { e.isIntersecting ? Motion.on.add(e.target) : Motion.on.delete(e.target); e.target.classList.toggle('off', !e.isIntersecting); });
  Motion.wake(); ribbonRun();
});
[heroOut, realOut, koOut, ribbon, ...cards].forEach(el => io.observe(el));
pauseBtn.addEventListener('click', () => {
  paused = !paused;
  pauseBtn.setAttribute('aria-pressed', paused);
  pauseBtn.setAttribute('aria-label', paused ? 'Play the motion' : 'Pause the motion');
  update();
});
rmq.addEventListener('change', update);

// 1. Hero field: the README demo.
runDemo(heroOut, $('#hero-key'));

// 2. Mail: one Tab / Shift-Tab beat with its own line, about 8 s a loop.
const typed = 'Can we move it to Th', word = 'ursday', rest = ' afternoon? I have a clash at ten.';
const show = (t, ghost, taken = '') => { realOut.innerHTML = escHtml(t) + (taken ? `<span class="taken">${escHtml(taken)}</span>` : '') + '<span class="caret"></span>' + (ghost ? `<span class="ghost">${escHtml(ghost)}</span>` : ''); };
const press = async (shift) => { realKey.innerHTML = shift ? SHIFT_TAB : 'tab'; realKey.classList.add('down'); await wait(180, realOut); realKey.classList.remove('down'); };
(async () => {
  for (;;) {
    await wait(0, realOut);  // starts when the section scrolls into view
    show('', ''); await wait(500, realOut);
    for (let i = 1; i < typed.length; i++) { show(typed.slice(0, i), ''); await wait(55 + ((i * 37) % 50), realOut); }
    show(typed, word + rest); await wait(900, realOut);
    show(typed, rest, word); press(false); await wait(1000, realOut);
    show(typed + word, '', rest); press(true); await wait(2600, realOut);
    realKey.textContent = 'tab';
  }
})();

// 4. Keys: each card, once in view, presses its key and its after state appears with the glint. Once, no loop.
// Cards in one row (desktop) take turns; stacked cards (phones) each start when they scroll in.
cards.forEach((c, i) => {
  if (rmq.matches) return;
  const m = c.querySelectorAll('.mini'); m[1].innerHTML = m[0].innerHTML; c.classList.remove('played');
  (async () => {
    await wait(0, c);
    if (done.has(c)) return;
    const turn = cards.filter(d => d.offsetTop === c.offsetTop && !done.has(d)).indexOf(c);
    await wait(400 + Math.max(0, turn) * 880, c);
    if (done.has(c)) return;
    const k = c.querySelector('.kc'); k.classList.add('down'); await wait(180, c); k.classList.remove('down');
    if (done.has(c)) return;
    m[1].innerHTML = afters[i]; c.classList.add('played'); done.add(c);
  })();
});

// 1b. Hero ribbon: a slow eased drift along the arch (60 s each way), its frame loop running only while on screen and moving.
// The text is longer than the arch, so it starts at 40 and drifts until its end reaches the arch's end, then back.
const span = Math.max(0, rt.parentNode.getComputedTextLength() - rpath.getTotalLength() + 80);
let t = 0, last = 0, raf = 0;
const moving = () => !Motion.held && Motion.on.has(ribbon);
const drift = now => {
  if (!moving()) { raf = 0; return; }
  if (last) t += now - last;
  last = now;
  rt.setAttribute('startOffset', 40 - span * (1 - Math.cos(t / 60000 * Math.PI)) / 2);
  raf = requestAnimationFrame(drift);
};
function ribbonRun() { if (!raf && moving()) { last = 0; raf = requestAnimationFrame(drift); } }

// 5. Korean: Tab presses the jamo left, and the input method composes them (반갑 → 반값 → 반갑스 → … → 반갑습니다.).
const tab = $('#ko-tab'), keys = [...document.querySelectorAll('.jamo .kc')];
const FRAMES = ['반값', '반갑스', '반갑습', '반갑습ㄴ', '반갑습니', '반갑습닏', '반갑습니다', '반갑습니다.'];
(async () => {
  for (;;) {
    await wait(0, koOut);
    koOut.innerHTML = '만나서 반갑<span class="caret"></span><span class="ghost">습니다.</span>';
    await wait(2600, koOut);
    tab.classList.add('down'); await wait(160, koOut); tab.classList.remove('down');
    for (let i = 0; i < FRAMES.length; i++) {
      keys[i].classList.add('down');
      koOut.innerHTML = '만나서 ' + FRAMES[i] + '<span class="caret"></span>';
      await wait(110, koOut); keys[i].classList.remove('down'); await wait(30, koOut);
    }
    koOut.innerHTML = '만나서 반갑<span class="taken">습니다.</span><span class="caret"></span>';
    await wait(3200, koOut);
  }
})();

update();
