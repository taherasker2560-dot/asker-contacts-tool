// البرنامج كله بالكيبورد، من غير ماوس خالص.
// 1) المفاتيح بتتقري بمكانها على الكيبورد (e.code) مش بالحرف: بتشتغل والكيبورد عربي أو إنجليزي.
// 2) الاختصارات كلها في جدول واحد (KEYS) ← تتغير من مكان واحد (ومنه نعمل نسخة «زي فارمافلاي» لما الدليل يوصل).
// 3) أي قايمة أو جدول: ↑ ↓ للاختيار، Enter يفتح، والحرف اللي جنب الزرار بيدوسه في الصف المختار.
// 4) F4 «وضع الحروف»: حرف على كل حاجة تتداس في الشاشة ← تكتبه ← اتداست. يعني مفيش حاجة محتاجة ماوس، ولا في شاشة جاية.
// 5) F1 الدليل: بيتبني من الشاشة اللي إنت فيها، فاللي مكتوب فيه = اللي شغال فعلًا.
import { h, raw, esc, modal, modalOpen, toast } from './ui.js';

// ---------------------------------------------------------------- الجدول (مفتاح ← أمر)
// الصيغة: 'Alt+Digit1'، 'F2'، 'Ctrl+KeyK'، 'Shift+Slash'… (اسم المفتاح من e.code)
export const KEYS = {
  global: [
    { k: ['F1', 'Shift+Slash', 'Ctrl+Slash'], do: 'guide', t: 'دليل الاختصارات (للشاشة اللي إنت فيها)' },
    { k: ['F2'], do: 'pos', t: 'البيع / فاتورة جديدة' },
    { k: ['F3', 'Ctrl+KeyK'], do: 'palette', t: 'دوّر على أي حاجة: صنف، عميل، أمر' },
    { k: ['F4'], do: 'hints', t: 'وضع الحروف: حرف على كل زرار في الشاشة' },
    { k: ['F5'], do: 'refresh', t: 'حدّث البيانات (من غير ما يضيع حاجة)' },
    { k: ['Alt+Digit1', 'Alt+Digit2', 'Alt+Digit3', 'Alt+Digit4', 'Alt+Digit5', 'Alt+Digit6', 'Alt+Digit7', 'Alt+Digit8', 'Alt+Digit9'], do: 'nav', t: 'روح للشاشة رقم 1…9 (بترتيب القايمة)' },
    { k: ['Alt+KeyN'], do: 'note', t: 'سجّل ملاحظة في التجربة' },
    { k: ['Alt+KeyT'], do: 'theme', t: 'نهاري / ليلي' },
    { k: ['Alt+KeyK'], do: 'colors', t: 'ألوان البرنامج (نفس ألوان البوت والموقع)' },
    { k: ['Escape'], do: 'back', t: 'رجوع خطوة / اقفل النافذة' },
  ],
  lists: [
    { k: ['ArrowDown', 'ArrowUp'], t: 'اختار الصف اللي بعده / قبله' },
    { k: ['Home', 'End', 'PageDown', 'PageUp'], t: 'أول / آخر / نزّل / طلّع صفحة' },
    { k: ['Enter'], t: 'افتح الصف المختار' },
    { k: ['Slash'], t: 'خانة البحث في الشاشة' },
    { k: ['BracketRight', 'BracketLeft'], t: 'التاب اللي بعده / قبله' },
    { k: ['Shift+BracketRight', 'Shift+BracketLeft'], t: 'الفترة اللي بعدها / قبلها (التقارير)' },
    { k: ['Equal', 'Minus'], t: 'زوّد / قلّل الكمية في الصف المختار' },
    { k: ['Delete'], t: 'شيل الصف المختار (لو ينفع)' },
  ],
};
const ROW_AR = { ArrowDown: '↓', ArrowUp: '↑', Enter: 'Enter', Escape: 'Esc', Slash: '/', BracketRight: ']', BracketLeft: '[', Equal: '+', Minus: '−', Delete: 'Del', Home: 'Home', End: 'End', PageDown: 'PgDn', PageUp: 'PgUp', Backspace: '⌫' };
export function keyLabel(k) {
  return k.split('+').map((p) => ROW_AR[p] || p.replace(/^Key/, '').replace(/^Digit/, '').replace('Slash', '/').replace('Shift', 'Shift').replace('Ctrl', 'Ctrl')).join('+');
}
export function combo(e) {
  const parts = [];
  if (e.ctrlKey || e.metaKey) parts.push('Ctrl');
  if (e.altKey) parts.push('Alt');
  if (e.shiftKey && !/^Shift/.test(e.code)) parts.push('Shift');
  parts.push(e.code);
  return parts.join('+');
}
export const typing = (el) => !!el && (el.isContentEditable || (el.tagName === 'INPUT' && !/^(checkbox|radio|button|submit)$/.test(el.type)) || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT');
const visible = (el) => { if (!el || !el.isConnected) return false; const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden'; };
// الحرف بتاع الزرار بيتعرف من مكانه: data-key="w" ← KeyW، "+" ← Equal، "Delete"
const codeFor = (k) => (k.length === 1 && /[a-z]/i.test(k) ? 'Key' + k.toUpperCase() : k === '+' ? 'Equal' : k === '-' ? 'Minus' : k);

// ---------------------------------------------------------------- الاختيار في القوايم
let sel = null;
const rows = (root) => [...root.querySelectorAll('[data-row]')].filter(visible);
function select(el, root) {
  if (sel) sel.classList.remove('kb-sel');
  sel = el || null;
  if (!sel) return;
  sel.classList.add('kb-sel');
  sel.scrollIntoView({ block: 'nearest', behavior: 'auto' });
  if (root && document.activeElement && typing(document.activeElement) && root.contains(document.activeElement)) document.activeElement.blur();
}
export function clearSelection() { if (sel) sel.classList.remove('kb-sel'); sel = null; }
function moveSel(root, d) {
  const list = rows(root); if (!list.length) return false;
  let i = sel && list.includes(sel) ? list.indexOf(sel) : -1;
  if (d === 'first') i = 0; else if (d === 'last') i = list.length - 1;
  else if (d === 'pgdn') i = Math.min(list.length - 1, Math.max(0, i) + 10); else if (d === 'pgup') i = Math.max(0, i - 10);
  else i = i < 0 ? (d > 0 ? 0 : list.length - 1) : Math.max(0, Math.min(list.length - 1, i + d));
  select(list[i], root); return true;
}
function openSel() {
  if (!sel || !sel.isConnected) return false;
  const t = sel.querySelector('[data-open]') || (sel.matches('a,button,[onclick]') ? sel : sel.querySelector('a[href]:not([target])')) || (sel.matches('.click') ? sel : null);
  if (t) { t.click(); return true; }
  return false;
}
// زرار بحرف: في الصف المختار الأول، وبعدين المجموعة اللي هو فيها (كارت المورد مثلًا)
function rowAction(code) {
  if (!sel || !sel.isConnected) return false;
  const scopes = [sel, sel.closest('[data-group]')].filter(Boolean);
  for (const s of scopes) {
    const b = [...s.querySelectorAll('[data-key]')].find((x) => codeFor(x.dataset.key) === code && visible(x) && !x.disabled);
    if (b) { b.click(); return true; }
  }
  if (code === 'Equal' || code === 'Minus') {
    const inp = sel.querySelector('input[type=number]');
    if (inp) { inp.value = Math.max(0, (+inp.value || 0) + (code === 'Equal' ? 1 : -1)); inp.dispatchEvent(new Event('input', { bubbles: true })); return true; }
  }
  return false;
}
function cycleTabs(root, dir, kind) {
  const box = root.querySelector(kind ? `[data-tabs="${kind}"]` : '[data-tabs]:not([data-tabs="period"])');
  if (!box) return false;
  const chips = [...box.querySelectorAll('button, a')].filter(visible);
  if (!chips.length) return false;
  let i = chips.findIndex((c) => c.classList.contains('on') || c.getAttribute('aria-pressed') === 'true');
  // [ ] على الشاشة العربي: ] = اللي بعده (يمين ← شمال)
  i = (i + dir + chips.length) % chips.length;
  chips[i].click(); chips[i].focus({ preventScroll: true });
  clearSelection();
  return true;
}

// ---------------------------------------------------------------- وضع الحروف (F4)
const HINT_CODES = 'ASDFGHJKLQWERTYUIOPZXCVBNM'.split('');
let hint = null;
function interactive(root) {
  const sels = 'a[href], button, input:not([type=hidden]), select, textarea, [data-row], tr.click, [tabindex]:not([tabindex="-1"])';
  const seen = new Set();
  return [...root.querySelectorAll(sels)].filter((el) => {
    if (!visible(el) || el.disabled || el.closest('[hidden]') || el.closest('.kb-hints')) return false;
    const r = el.getBoundingClientRect();
    if (r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth) return false;   // اللي ظاهر في الشاشة بس
    const key = Math.round(r.left) + ':' + Math.round(r.top);
    if (seen.has(key)) return false; seen.add(key); return true;
  });
}
export function hintMode() {
  if (hint) return endHints();
  const m = [...document.querySelectorAll('.modal')].pop();
  const roots = m ? [m] : [document.querySelector('.side'), document.querySelector('.top'), document.querySelector('#page'), document.querySelector('.bottom-nav'), document.querySelector('.fab')].filter(Boolean);
  const els = roots.flatMap((r) => (r.matches && r.matches('.fab') ? [r] : interactive(r)));
  if (!els.length) return;
  const two = els.length > HINT_CODES.length;
  const codes = els.map((_, i) => (two ? HINT_CODES[Math.floor(i / HINT_CODES.length) % HINT_CODES.length] + HINT_CODES[i % HINT_CODES.length] : HINT_CODES[i]));
  const layer = document.createElement('div');
  layer.className = 'kb-hints'; layer.setAttribute('aria-hidden', 'true');
  els.forEach((el, i) => {
    const r = el.getBoundingClientRect(), s = document.createElement('span');
    s.textContent = codes[i]; s.dataset.code = codes[i];
    s.style.top = Math.max(2, r.top + 2) + 'px'; s.style.left = Math.max(2, r.left + 2) + 'px';
    layer.appendChild(s);
  });
  document.body.appendChild(layer);
  hint = { els, codes, typed: '', layer };
  toast('اكتب الحرف اللي على الزرار · Esc يلغي');
}
function endHints() { if (hint) { hint.layer.remove(); hint = null; } }
function hintKey(e) {
  if (e.code === 'Escape' || e.code === 'F4') { endHints(); return true; }
  const m = /^Key([A-Z])$/.exec(e.code); if (!m) { if (!/^(Shift|Control|Alt|Meta)/.test(e.code)) endHints(); return !!hint; }
  hint.typed += m[1];
  const matches = hint.codes.map((c, i) => [c, i]).filter(([c]) => c.startsWith(hint.typed));
  [...hint.layer.children].forEach((s) => { s.classList.toggle('dim', !s.dataset.code.startsWith(hint.typed)); });
  if (matches.length === 1 && matches[0][0] === hint.typed) {
    const el = hint.els[matches[0][1]]; endHints();
    if (typing(el)) { el.focus(); if (el.select) try { el.select(); } catch (er) {} }
    else if (el.matches('[data-row]') && !el.matches('a,button,tr.click')) { select(el, document.querySelector('#page')); }
    else { el.focus({ preventScroll: true }); el.click(); }
  } else if (!matches.length) endHints();
  return true;
}

// ---------------------------------------------------------------- الدليل (F1): بيتبني من الشاشة اللي إنت فيها
export function guide({ routes, can, screenKeys = [] }) {
  if (document.querySelector('.kb-guide')) return;
  const page = document.querySelector('#page');
  const rowKeys = new Map(), pageKeys = new Map();
  // اسم الزرار من غير الـ <kbd> اللي جواه
  const labelOf = (b) => b.getAttribute('title') || b.getAttribute('aria-label') || (b.placeholder || '').replace(/\s*\(.*?\)\s*/g, ' ').split('—')[0].trim()
    || [...b.childNodes].filter((n) => !(n.nodeType === 1 && n.tagName === 'KBD')).map((n) => n.textContent).join(' ').replace(/\s+/g, ' ').trim();
  const norm = (k) => k.toLowerCase().replace(/key/g, '').replace(/digit/g, '');
  const covered = new Set(screenKeys.flatMap((x) => x.k.map(norm)));
  if (page) {
    page.querySelectorAll('[data-row] [data-key], [data-group] [data-key]').forEach((b) => { const k = b.dataset.key; if (!rowKeys.has(k)) rowKeys.set(k, labelOf(b)); });
    page.querySelectorAll('[data-hot]').forEach((b) => { const k = b.dataset.hot; if (!pageKeys.has(k) && !covered.has(k)) pageKeys.set(k, labelOf(b)); });
  }
  const navs = routes.filter((r) => can(r.roles));
  const kbd = (k) => h`<kbd>${keyLabel(k)}</kbd>`;
  const list = (items) => h`<div class="kb-list">${items.map(([keys, t]) => h`<div class="kb-row"><span class="kb-keys">${keys.map((k, i) => h`${i ? ' ' : ''}${kbd(k)}`)}</span><span>${t}</span></div>`)}</div>`;
  const glob = KEYS.global.filter((g) => g.do !== 'nav').map((g) => [g.k.slice(0, 2), g.t]);
  const nav = navs.slice(0, 9).map((r, i) => [['Alt+Digit' + (i + 1)], r.label]);
  const scr = screenKeys.map((s) => [s.k, s.t]);
  const hot = [...pageKeys].map(([k, t]) => [[k.split('+').map((p) => (p.length === 1 ? 'Key' + p.toUpperCase() : p[0].toUpperCase() + p.slice(1))).join('+')], t]);
  const row = [...rowKeys].map(([k, t]) => [[codeFor(k)], t + ' (في الصف المختار)']);
  const m = modal({ title: 'دليل الاختصارات', wide: true, cls: 'kb-guide', body: h`
    <p class="muted" style="margin-top:0">كل حاجة في البرنامج بتتعمل من الكيبورد، والكيبورد عربي أو إنجليزي مش فارقة. مش لاقي اختصار لزرار؟ <kbd>F4</kbd> بيحط حرف على كل زرار.</p>
    <div class="grid g2">
      <div><h3 class="kb-h">في كل الشاشات</h3>${list(glob)}<h3 class="kb-h">الشاشات</h3>${list(nav)}</div>
      <div>${scr.length || hot.length || row.length ? h`<h3 class="kb-h">في الشاشة دي</h3>${list([...scr, ...hot, ...row])}` : ''}<h3 class="kb-h">أي قايمة أو جدول</h3>${list(KEYS.lists.map((x) => [x.k.slice(0, 2), x.t]))}</div>
    </div>`,
    footer: h`<button class="btn quiet" id="kb-print" data-hot="alt+p">اطبع الدليل كله</button><button class="btn" data-close>تمام</button>` });
  m.el.querySelector('#kb-print').addEventListener('click', () => printSheet(navs));
}
// ورقة A4 بكل الاختصارات (تتعلق جنب الكاونتر)
export function printSheet(navs) {
  const sheet = document.createElement('div');
  sheet.className = 'print-sheet';
  const rowsOf = (arr) => arr.map((g) => `<tr><td>${g.k.slice(0, 3).map((k) => `<kbd>${esc(keyLabel(k))}</kbd>`).join(' ')}</td><td>${esc(g.t)}</td></tr>`).join('');
  sheet.innerHTML = `<h1>اختصارات برنامج صيدلية عسكر</h1>
    <h2>في كل الشاشات</h2><table>${rowsOf(KEYS.global.filter((g) => g.do !== 'nav'))}${navs.slice(0, 9).map((r, i) => `<tr><td><kbd>Alt+${i + 1}</kbd></td><td>${esc(r.label)}</td></tr>`).join('')}</table>
    <h2>البيع</h2><table>${rowsOf(POS_KEYS)}</table>
    <h2>أي قايمة أو جدول</h2><table>${rowsOf(KEYS.lists)}</table>
    <p>مش لاقي اختصار؟ F4 بيحط حرف على كل زرار في الشاشة.</p>`;
  document.body.appendChild(sheet);
  document.body.classList.add('printing-sheet');
  setTimeout(() => { window.print(); document.body.classList.remove('printing-sheet'); sheet.remove(); }, 50);
}
// مفاتيح البيع (للدليل والورقة المطبوعة؛ التنفيذ في views/pos.js)
export const POS_KEYS = [
  { k: ['F2'], t: 'خانة البحث (باركود أو اسم)' },
  { k: ['Enter'], t: 'ضيف الصنف / خلّص لو في خانة المستلم' },
  { k: ['ArrowDown', 'ArrowUp'], t: 'النتايج، أو أصناف الفاتورة لو البحث فاضي' },
  { k: ['Equal', 'Minus'], t: 'زوّد / قلّل كمية الصنف المختار' },
  { k: ['Shift+Digit8'], t: 'علبة ↔ شريط للصنف المختار (*)' },
  { k: ['Delete'], t: 'شيل الصنف المختار' },
  { k: ['Alt+KeyB'], t: 'بدايل الصنف (في النتايج)' },
  { k: ['Alt+KeyC'], t: 'العميل' },
  { k: ['Alt+KeyX'], t: 'الخصم' },
  { k: ['Alt+KeyR'], t: 'المستلم من العميل' },
  { k: ['F8'], t: 'كاش' }, { k: ['F9'], t: 'آجل' }, { k: ['F10'], t: 'فيزا' }, { k: ['Shift+F8'], t: 'محفظة / InstaPay' },
  { k: ['Ctrl+Enter'], t: 'خلّص الفاتورة' },
  { k: ['Alt+KeyP', 'F6'], t: 'علّق الفاتورة (العميل بيدوّر على حاجة)' },
  { k: ['Alt+Shift+KeyP'], t: 'رجّع آخر فاتورة معلّقة' },
  { k: ['Alt+KeyL'], t: 'اطبع آخر فاتورة تاني' },
  { k: ['Alt+KeyO'], t: 'فتح / قفل الوردية' },
];

// ---------------------------------------------------------------- المفتاح العام
export function initKeyboard(api) {
  const actions = {
    guide: () => api.guide(),
    pos: () => api.go('#/pos'),
    palette: () => api.palette(),
    hints: () => hintMode(),
    refresh: () => api.refresh(),
    note: () => api.note(),
    theme: () => api.theme(),
    colors: () => api.colors(),
  };
  const map = new Map();
  for (const g of KEYS.global) for (const k of g.k) map.set(k, g.do);

  document.addEventListener('keydown', (e) => {
    if (!api.ready()) return;
    if (hint) { if (hintKey(e)) { e.preventDefault(); e.stopPropagation(); } return; }
    if (e.defaultPrevented || e.isComposing) return;
    const c = combo(e), act = map.get(c);
    const inModal = modalOpen();
    const page = document.querySelector('#page');

    // النوافذ: Enter = الزرار الأساسي (من خانة)، Ctrl+Enter من أي حتة
    if (inModal) {
      const m = [...document.querySelectorAll('.modal')].pop();
      if (m.querySelector('.palette, .p-in')) return;   // لوحة الأوامر ليها مفاتيحها
      const prim = [...m.querySelectorAll('footer .btn:not([data-close]):not([disabled])')].pop();
      if ((c === 'Enter' && typing(e.target) && e.target.tagName !== 'TEXTAREA' && e.target.tagName !== 'SELECT') || c === 'Ctrl+Enter') {
        if (prim) { e.preventDefault(); prim.click(); }
        return;
      }
      if (c === 'F4') { e.preventDefault(); hintMode(); return; }
      if (c === 'ArrowRight' || c === 'ArrowLeft') {   // اختيارات (chips) جوه النافذة
        const box = e.target.closest && e.target.closest('.chips');
        if (box) { const ch = [...box.querySelectorAll('.chip')]; const i = ch.indexOf(e.target); const n = ch[(i + (c === 'ArrowLeft' ? 1 : -1) + ch.length) % ch.length]; if (n) { e.preventDefault(); n.focus(); n.click(); } }
      }
      return;
    }

    if (act === 'nav') { const n = +c.slice(-1); e.preventDefault(); api.nav(n); return; }
    if (act && act !== 'back') {
      // F-keys وAlt شغالين حتى وإنت بتكتب؛ ? بس لما مش بتكتب
      if (c === 'Shift+Slash' && typing(e.target)) return;
      e.preventDefault(); actions[act](); return;
    }
    if (!page) return;

    // أزرار الشاشة: data-hot="alt+p"
    if (e.altKey || e.ctrlKey) {
      const hot = c.toLowerCase().replace(/key/g, '').replace('digit', '');
      const b = [...page.querySelectorAll('[data-hot]')].find((x) => x.dataset.hot === hot && visible(x) && !x.disabled);
      if (b) { e.preventDefault(); typing(b) ? b.focus() : b.click(); }
      return;
    }

    const inField = typing(e.target);
    if (c === 'Escape') {
      if (inField && e.target.value) return;   // الشاشة نفسها بتمسح
      if (sel) { clearSelection(); e.preventDefault(); return; }
      if (inField) { e.target.blur(); e.preventDefault(); return; }
      const back = page.querySelector('[data-back]');
      if (back) { e.preventDefault(); back.click(); }
      return;
    }
    if (inField) {
      // من خانة البحث: ↓ ينزل على القايمة
      if (c === 'ArrowDown' && e.target.matches('[data-search]') && rows(page).length) { e.preventDefault(); moveSel(page, 1); }
      // «/» وإنت أصلًا في خانة البحث الفاضية: ماتكتبهوش
      if (c === 'Slash' && e.target.matches('[data-search]') && !e.target.value) e.preventDefault();
      return;
    }
    if (c === 'Slash') { const s = page.querySelector('[data-search]'); if (s && visible(s)) { e.preventDefault(); clearSelection(); s.focus(); s.select && s.select(); } return; }
    if (c === 'ArrowDown' || c === 'ArrowUp') { if (moveSel(page, c === 'ArrowDown' ? 1 : -1)) e.preventDefault(); return; }
    if (c === 'Home' || c === 'End' || c === 'PageDown' || c === 'PageUp') { if (moveSel(page, { Home: 'first', End: 'last', PageDown: 'pgdn', PageUp: 'pgup' }[c])) e.preventDefault(); return; }
    if (c === 'Enter') { if (openSel()) e.preventDefault(); return; }
    if (c === 'BracketRight' || c === 'BracketLeft') { if (cycleTabs(page, c === 'BracketRight' ? 1 : -1)) e.preventDefault(); return; }
    if (c === 'Shift+BracketRight' || c === 'Shift+BracketLeft') { if (cycleTabs(page, c === 'Shift+BracketRight' ? 1 : -1, 'period')) e.preventDefault(); return; }
    if (rowAction(c.replace(/^Shift\+/, ''))) { e.preventDefault(); return; }
  });
  // الاختيار بيتمسح لما الشاشة تتغير
  window.addEventListener('hashchange', () => { clearSelection(); endHints(); });
}
