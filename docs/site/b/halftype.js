// The hero's ghost-completed headline and the replay of six real suggestions (docs/media/{en,ko}.gif, scripts/demo.sh).
const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
const wait = ms => new Promise(r => setTimeout(r, ms));

// 2-set typing, one key state at a time: per syllable the initial, then initial+vowel, then the whole syllable.
const INITIALS = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
export function keyStates(text) {
  const out = []; let done = '';
  for (const ch of text) {
    const c = ch.codePointAt(0) - 0xAC00;
    if (c >= 0 && c < 11172) {
      const L = Math.floor(c / 588), V = Math.floor((c % 588) / 28), T = c % 28;
      out.push(done + INITIALS[L], done + String.fromCharCode(0xAC00 + (L * 21 + V) * 28));
      if (T) out.push(done + ch);
    } else out.push(done + ch);
    done += ch;
  }
  return out;
}
console.assert(keyStates('반').join() === 'ㅂ,바,반' && keyStates('a반').length === 4, 'keyStates');

// Copy the brew commands without the prompts.
document.querySelectorAll('[data-copy]').forEach(b => b.addEventListener('click', async () => {
  const text = document.getElementById(b.dataset.copy).textContent.replace(/^\$ /gm, '');
  try { await navigator.clipboard.writeText(text); b.textContent = 'Copied'; } catch { b.textContent = 'Select and copy'; }
  setTimeout(() => (b.textContent = 'Copy commands'), 1800);
}));

// Hero: the caret waits after the typed half, then Tab takes the ghost, English first, then Korean.
const gags = [...document.querySelectorAll('[data-gag]')];
const tabCap = document.querySelector('.hero__tab');
if (still) gags.forEach(g => g.classList.add('is-taken'));
else (async () => {
  await wait(1100);
  for (const g of gags) {
    const caret = document.createElement('span'); caret.className = 'caret'; caret.setAttribute('aria-hidden', 'true');
    g.querySelector('.ghost').before(caret); g.classList.add('has-caret');
    await wait(1300);
    tabCap.classList.add('is-down'); await wait(160); tabCap.classList.remove('is-down');
    g.classList.add('is-taken'); g.classList.remove('has-caret'); caret.remove();
    await wait(700);
  }
})();

// The replay, interleaved English and Korean, each exactly as the model and gate gave it.
const SENTENCES = [
  ['Let me know if you have any quest', 'ions', 'English'],
  ['안녕하세요. 만나서 반갑', '습니다.', '한국어'],
  ['See you tomor', 'row.', 'English'],
  ['감사합니다. 좋은 하루 보내', '세요!', '한국어'],
  ['As soon as possi', 'ble,', 'English'],
  ['이번 주 금요일까지 보내주시면 감사하겠', '습니다.', '한국어'],
];
const line = document.querySelector('[data-replay]');
const lang = document.querySelector('[data-replay-lang]');
const pauseBtn = document.querySelector('[data-replay-pause]');
const tabKey = document.querySelector('[data-key="tab"]');
let paused = false, visible = false;
pauseBtn.addEventListener('click', () => { paused = !paused; pauseBtn.textContent = paused ? 'Play the replay' : 'Pause the replay'; });
new IntersectionObserver(([e]) => (visible = e.isIntersecting)).observe(line);
const gate = async ms => { await wait(ms); while (paused || !visible || document.hidden) await wait(200); };

function draw(typed, ghost, taken) {
  line.replaceChildren(typed);
  const caret = document.createElement('span'); caret.className = 'caret';
  if (ghost) { const g = document.createElement('span'); g.className = 'ghost' + (taken ? ' is-taken' : ''); g.textContent = ghost; line.append(taken ? g : caret, taken ? caret : g); }
  else line.append(caret);
}

if (still) { pauseBtn.hidden = true; }
else (async () => {
  for (;;) for (const [typed, ghost, name] of SENTENCES) {
    lang.textContent = name; lang.lang = name === '한국어' ? 'ko' : 'en';
    for (const s of keyStates(typed)) { draw(s, '', false); await gate(55 + Math.random() * 70); }
    draw(typed, ghost, false); await gate(1500);
    tabKey.classList.add('is-down'); await gate(170); tabKey.classList.remove('is-down');
    draw(typed, ghost, true); await gate(1600);
  }
})();
