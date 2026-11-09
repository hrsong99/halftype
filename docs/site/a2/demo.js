// Shared by the variants: the README demo (scripts/demo.sh, docs/design/readme-demo/round4/B-script.txt), on one clock.
// ?speed=0.5 slows everything; each variant calls runDemo(textEl, keyEl, { onTab }).
const SPEED = Number(new URLSearchParams(location.search).get('speed')) || 1;
document.documentElement.style.setProperty('--speed', SPEED);
const SCRIPT = new Map(Object.entries({
  'Ha': 'ppy birthday', 'Happy birthday! I ': 'hope you have a great day',
  'Th': 'anks for the update.', "Thanks for the update. I'll t": 'ake a look and get back to you.',
  'Ru': 'nning', 'Running 10 m': 'inutes late', 'Running 10 minutes late, sorry! S': 'ee you soon!', 'Running 10 minutes late, sorry! Sa': 've me a seat.',
}));
const MESSAGES = ['Happy birthday! I hope you have a great day!', "Thanks for the update. I'll take a look and get back to you.", 'Running 10 minutes late, sorry! Save me a seat.'];
// H: a demo runs only while its element is on screen and the page's pause control isn't held (page.js sets both).
const Motion = { held: false, on: new Set(), waiting: [],
  gate(el) { return !el || (!Motion.held && Motion.on.has(el)) ? null : new Promise(r => Motion.waiting.push([el, r])); },
  wake() { Motion.waiting = Motion.waiting.filter(([el, r]) => (!Motion.held && Motion.on.has(el)) ? (r(), false) : true); } };
const wait = (ms, el) => new Promise(r => setTimeout(r, ms / SPEED)).then(() => Motion.gate(el));
const SHIFT_TAB = '<span class="sh">⇧</span> tab';
const escHtml = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
function runDemo(out, key, { onTab = () => {}, onMessage = () => {} } = {}) {
  const show = (typed, ghost, taken = '') => { out.innerHTML = escHtml(typed) + (taken ? `<span class="taken">${escHtml(taken)}</span>` : '') + '<span class="caret"></span>' + (ghost ? `<span class="ghost">${escHtml(ghost)}</span>` : ''); };
  const press = async (shift, text, took, ghost) => {
    if (key) { key.innerHTML = shift ? SHIFT_TAB : 'tab'; key.classList.add('down'); }
    show(text.slice(0, -took.length), ghost, took); onTab(shift);
    await wait(180, out); if (key) key.classList.remove('down');
  };
  (async () => {
    for (let m = 0; ; m = (m + 1) % MESSAGES.length) {
      const target = MESSAGES[m]; let text = '', ghost = '';
      onMessage(m); show('', ''); await wait(300, out);
      while (text.length < target.length) {
        const rest = target.slice(text.length);
        if (ghost && rest.startsWith(ghost) && ghost.trim().split(/\s+/).length >= 3) {
          await wait(400, out); const took = ghost; text += took; ghost = SCRIPT.get(text) || '';
          await press(true, text, took, ghost); await wait(500, out); continue;
        }
        const word = ghost && ghost.match(/^\s*\S+/)[0];
        if (word && rest.startsWith(word)) {
          await wait(260, out); text += word; ghost = ghost.slice(word.length) || SCRIPT.get(text) || '';
          await press(false, text, word, ghost); continue;
        }
        if (ghost) await wait(350, out);
        const letter = rest[0]; text += letter;
        ghost = ghost[0] === letter && ghost.length > 1 ? ghost.slice(1) : SCRIPT.get(text) || '';
        show(text, ghost); await wait(45 + ((text.length * 37) % 60), out);  // uneven like hands, the same every run
      }
      if (key) key.textContent = 'tab'; show(text, ''); await wait(2600, out);  // H: hold the finished message so the field is rarely empty
    }
  })();
}
const MARK = '<svg viewBox="0 0 18 18" width="22" height="22" fill="none" stroke="#1d1c1a" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><defs><linearGradient id="hta" x1="4.9" x2="15.2" y1="0" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#1d1c1a"/><stop offset=".45" stop-color="#a9cdf0"/><stop offset="1" stop-color="#f6c3a4"/></linearGradient></defs><path d="M8.4 3.6 C7.6 1.6 5 1.7 4.9 4.6 C4.8 7.5 4.7 11.5 4.6 15.6"/><path d="M4.9 12.2 C6.5 9.4 8.7 8 10.2 8.4 C11.8 8.8 11.2 11.6 11.3 13.4 C11.4 15.4 13.2 15.6 15.2 13.9" stroke="url(#hta)"/></svg>';
const FIELD_BAR = '<div class="bar"><span class="kc" data-key>tab</span><span style="flex:1"></span><span class="pill">Gemma 4 E2B</span><span class="power"><svg viewBox="0 0 24 24"><path d="M12 3v8"/><path d="M6.3 7.3a8 8 0 1 0 11.4 0"/></svg></span></div>';
function nav(extra = '') { return `<nav class="top"><span class="logo">${MARK}Halftype</span><span class="links"><span>Keys</span><span>Privacy</span><span>Compare</span></span><a class="btn small">Download</a>${extra}</nav>`; }
