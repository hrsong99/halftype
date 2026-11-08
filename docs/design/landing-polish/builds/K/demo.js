// The README demo (scripts/demo.sh, docs/design/readme-demo/round4/B-script.txt), copied from ../../demo.js:
// the same messages, suggestions and rules. Tab takes a short suggestion a word at a time, Shift-Tab a long one
// that's right to the end, and a wrong one is typed over. Added here: pause/play, and a still under reduced motion.
const SPEED = Number(new URLSearchParams(location.search).get('speed')) || 1;
document.documentElement.style.setProperty('--speed', SPEED);
const REDUCED = matchMedia('(prefers-reduced-motion: reduce)').matches;
const SCRIPT = new Map(Object.entries({
  'Ha': 'ppy birthday', 'Happy birthday! I ': 'hope you have a great day',
  'Th': 'anks for the update.', "Thanks for the update. I'll t": 'ake a look and get back to you.',
  'Ru': 'nning', 'Running 10 m': 'inutes late', 'Running 10 minutes late, sorry! S': 'ee you soon!', 'Running 10 minutes late, sorry! Sa': 've me a seat.',
}));
const MESSAGES = ['Happy birthday! I hope you have a great day!', "Thanks for the update. I'll take a look and get back to you.", 'Running 10 minutes late, sorry! Save me a seat.'];
const escHtml = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

// Returns { pause, play }. Reduced motion: one still, a typed line with its suggestion.
function runDemo(out, key) {
  const show = (typed, ghost, taken = '') => { out.innerHTML = escHtml(typed) + (taken ? `<span class="taken">${escHtml(taken)}</span>` : '') + '<span class="caret"></span>' + (ghost ? `<span class="ghost">${escHtml(ghost)}</span>` : ''); };
  if (REDUCED) { show("Thanks for the update. I'll t", 'ake a look and get back to you.'); return { pause() {}, play() {} }; }
  let paused = false, wake = null;
  const wait = ms => new Promise(r => setTimeout(() => paused ? (wake = r) : r(), ms / SPEED));
  const press = async (shift, text, took, ghost) => {
    if (key) { key.textContent = shift ? '⇧ tab' : 'tab'; key.classList.add('down'); }
    show(text.slice(0, -took.length), ghost, took);
    await wait(180); if (key) key.classList.remove('down');
  };
  (async () => {
    for (let m = 0; ; m = (m + 1) % MESSAGES.length) {
      const target = MESSAGES[m]; let text = '', ghost = '';
      show('', ''); await wait(300);
      while (text.length < target.length) {
        const rest = target.slice(text.length);
        if (ghost && rest.startsWith(ghost) && ghost.trim().split(/\s+/).length >= 3) {
          await wait(400); const took = ghost; text += took; ghost = SCRIPT.get(text) || '';
          await press(true, text, took, ghost); await wait(500); continue;
        }
        const word = ghost && ghost.match(/^\s*\S+/)[0];
        if (word && rest.startsWith(word)) {
          await wait(260); text += word; ghost = ghost.slice(word.length) || SCRIPT.get(text) || '';
          await press(false, text, word, ghost); continue;
        }
        if (ghost) await wait(350);  // a wrong suggestion stays a moment, so it's seen being typed over
        const letter = rest[0]; text += letter;
        ghost = ghost[0] === letter && ghost.length > 1 ? ghost.slice(1) : SCRIPT.get(text) || '';
        show(text, ghost); await wait(45 + ((text.length * 37) % 60));  // uneven like hands, the same every run
      }
      if (key) key.textContent = 'tab'; show(text, ''); await wait(1600);
    }
  })();
  return {
    pause() { paused = true; },
    play() { paused = false; if (wake) { const w = wake; wake = null; w(); } },
  };
}
