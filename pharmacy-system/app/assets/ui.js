// أدوات الشاشات: الكتابة الآمنة، الأرقام والتواريخ بالمصري، الأيقونات، الرسايل، النوافذ.

// ---------------------------------------------------------------- كتابة HTML آمنة
export function esc(v) {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
class Raw { constructor(s) { this.s = s; } toString() { return this.s; } }
export const raw = (s) => new Raw(String(s ?? ''));
const part = (v) => (v instanceof Raw ? v.s : Array.isArray(v) ? v.map(part).join('') : v === false || v == null ? '' : esc(v));
// h`<b>${name}</b>` → كل قيمة بتتنضف إلا لو raw() أو ناتج h تاني
export function h(strings, ...vals) {
  let out = strings[0];
  vals.forEach((v, i) => { out += part(v) + strings[i + 1]; });
  return new Raw(out);
}
export function render(el, tpl) { el.innerHTML = String(tpl); return el; }
export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

// ---------------------------------------------------------------- أرقام وتواريخ
const nf0 = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
const nf2 = new Intl.NumberFormat('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
export const num = (v) => nf2.format(Number(v || 0));
export const int = (v) => nf0.format(Math.round(Number(v || 0)));
export const money = (v) => nf2.format(Math.round(Number(v || 0) * 100) / 100);
export const moneyR = (v) => nf0.format(Math.round(Number(v || 0)));
export const pct = (v, d = 0) => (v == null || isNaN(v) ? '—' : Number(v).toFixed(d) + '%');
const LOC = 'ar-EG-u-nu-latn';
export const dateLong = (d) => new Intl.DateTimeFormat(LOC, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(toDate(d));
export const dateShort = (d) => (d ? new Intl.DateTimeFormat(LOC, { day: 'numeric', month: 'short' }).format(toDate(d)) : '—');
export const dateMY = (d) => (d ? new Intl.DateTimeFormat(LOC, { month: 'short', year: 'numeric' }).format(toDate(d)) : '—');
export const time = (d) => new Intl.DateTimeFormat(LOC, { hour: 'numeric', minute: '2-digit' }).format(toDate(d));
export const dateTime = (d) => (d ? new Intl.DateTimeFormat(LOC, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }).format(toDate(d)) : '—');
export function toDate(d) { if (d instanceof Date) return d; if (typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d)) return new Date(d + 'T12:00:00'); return new Date(d); }
export function days(n) {
  n = Math.abs(Math.round(n));
  if (n === 0) return 'النهارده'; if (n === 1) return 'يوم'; if (n === 2) return 'يومين';
  if (n <= 10) return n + ' أيام'; return n + ' يوم';
}
export function inDays(n) { if (n == null) return '—'; if (n === 0) return 'النهارده'; return n > 0 ? 'بعد ' + days(n) : 'من ' + days(n); }
export function ago(ts) {
  const s = (Date.now() - toDate(ts).getTime()) / 1000;
  if (s < 60) return 'دلوقتي'; if (s < 3600) return 'من ' + Math.round(s / 60) + ' دقيقة';
  if (s < 86400) { const hh = Math.round(s / 3600); return 'من ' + (hh === 1 ? 'ساعة' : hh === 2 ? 'ساعتين' : hh + ' ساعات'); }
  return 'من ' + days(s / 86400);
}
// الكمية بالعلبة والشريط: 7 علب و2 شريط
export function qty(units, parts, packName = 'علبة', unitName = 'شريط') {
  units = Number(units || 0); parts = Number(parts || 1);
  const neg = units < 0; units = Math.abs(units);
  const p = Math.floor(units / parts + 1e-9), u = Math.round((units - p * parts) * 100) / 100;
  let s = '';
  if (p) s += int(p) + ' ' + packName;
  if (u) s += (s ? ' و' : '') + num(u) + ' ' + unitName;
  return (neg ? '−' : '') + (s || '0');
}
export function expiryPill(d) {
  if (!d) return h`<span class="pill p-muted">من غير صلاحية</span>`;
  const left = Math.round((toDate(d) - new Date()) / 86400000);
  const cls = left < 0 ? 'p-bad' : left <= 90 ? 'p-bad' : left <= 180 ? 'p-warn' : 'p-good';
  return h`<span class="pill ${cls}" title="${inDays(left)}">${dateMY(d)}</span>`;
}
export function initials(name) { return String(name || '؟').replace(/^د\.\s*/, '').trim().slice(0, 1); }

// ---------------------------------------------------------------- أيقونات (خط 1.8)
const P = {
  home: '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V20h14V9.5"/><path d="M10 20v-6h4v6"/>',
  pos: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M7 20h10M12 16v4M7 8h4M7 11h7"/>',
  pill: '<path d="M10.5 20.5a5 5 0 0 1-7-7l7-7a5 5 0 0 1 7 7z"/><path d="m8.5 8.5 7 7"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  hourglass: '<path d="M6 3h12M6 21h12M7 3c0 5 10 5 10 9s-10 4-10 9M17 3c0 5-10 5-10 9s10 4 10 9"/>',
  truck: '<path d="M3 6h11v10H3zM14 9h4l3 3v4h-7"/><circle cx="7" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6 6 0 0 1 3.5 6"/>',
  factory: '<path d="M3 21V10l6 3V10l6 3V6l6 3v12z"/><path d="M7 17h2M12 17h2M17 17h2"/>',
  chart: '<path d="M4 20V4M4 20h16"/><rect x="7" y="11" width="3" height="6" rx="1"/><rect x="12" y="7" width="3" height="10" rx="1"/><rect x="17" y="13" width="3" height="4" rx="1"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-1-1.5 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>', minus: '<path d="M5 12h14"/>', x: '<path d="M6 6l12 12M18 6 6 18"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  moon: '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>',
  logout: '<path d="M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10"/>',
  note: '<path d="M4 4h16v12l-4 4H4z"/><path d="M16 20v-4h4M8 9h8M8 13h5"/>',
  printer: '<path d="M7 9V3h10v6"/><rect x="3" y="9" width="18" height="8" rx="2"/><path d="M7 14h10v7H7z"/>',
  whatsapp: '<path d="M4 20l1.3-4A8 8 0 1 1 8 18.8z"/><path d="M9 9.5c0 3 2.5 5.5 5.5 5.5l1.2-1.2-1.8-.9-.8.8a4 4 0 0 1-2.3-2.3l.8-.8-.9-1.8z"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7"/>', alert: '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17v.5"/>',
  refresh: '<path d="M20 11a8 8 0 0 0-14.6-4.5L4 8M4 4v4h4M4 13a8 8 0 0 0 14.6 4.5L20 16M20 20v-4h-4"/>',
  wallet: '<path d="M4 7h15a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z"/><path d="M4 7l11-3v3M16 13.5h.5"/>',
  cash: '<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 9v.01M18 15v.01"/>',
  card: '<rect x="2.5" y="5" width="19" height="14" rx="2"/><path d="M2.5 10h19M6 15h4"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  barcode: '<path d="M4 5v14M7 5v14M10 5v14M14 5v14M16 5v14M20 5v14"/>',
  sparkle: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 15l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z"/>',
  shield: '<path d="M12 3 4 6v6c0 4.5 3.4 8 8 9 4.6-1 8-4.5 8-9V6z"/><path d="m8.5 12 2.5 2.5 4.5-5"/>',
  heart: '<path d="M12 20s-7.5-4.6-7.5-10A4.5 4.5 0 0 1 12 7a4.5 4.5 0 0 1 7.5 3c0 5.4-7.5 10-7.5 10z"/><path d="M8 12h2.5l1-2 2 4 1-2H16"/>',
  bell: '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
  pause: '<rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/>',
  arrow: '<path d="M14 6l-6 6 6 6"/>', back: '<path d="M10 6l6 6-6 6"/>',
  key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 6l2 2M15 8l2 2"/>',
  bot: '<rect x="4" y="8" width="16" height="11" rx="3"/><path d="M12 4v4M9 13v1M15 13v1M9.5 16.5h5"/>',
  fridge: '<rect x="6" y="2.5" width="12" height="19" rx="2"/><path d="M6 9h12M9 5.5v1.5M9 12v3"/>',
  rx: '<path d="M6 20V4h5a3.5 3.5 0 0 1 0 7H6M10 11l8 9M18 13l-5 6"/>',
  box: '<path d="M3 7.5 12 3l9 4.5v9L12 21l-9-4.5z"/><path d="M3 7.5 12 12l9-4.5M12 12v9"/>',
  swap: '<path d="M7 4 3 8l4 4M3 8h14M17 12l4 4-4 4M21 16H7"/>',
  download: '<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>',
  receipt: '<path d="M5 3h14v18l-2.5-1.5L14 21l-2-1.5-2 1.5-2.5-1.5L5 21z"/><path d="M8.5 8h7M8.5 12h7M8.5 16h4"/>',
};
export function icon(name, cls = '') {
  return raw(`<svg class="${cls}" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[name] || ''}</svg>`);
}

// ---------------------------------------------------------------- رسايل ونوافذ
export function toast(msg, kind = '') {
  const box = document.getElementById('toasts');
  const t = document.createElement('div');
  t.className = 'toast ' + kind; t.textContent = msg; t.setAttribute('role', kind === 'bad' ? 'alert' : 'status');
  box.appendChild(t);
  setTimeout(() => { t.style.opacity = '0'; t.style.transition = 'opacity .3s'; }, kind === 'bad' ? 5200 : 3200);
  setTimeout(() => t.remove(), kind === 'bad' ? 5600 : 3600);
}

let modalDepth = 0;
// modal({title, body, footer, wide}) → {el, close, done: Promise}
export function modal({ title, body = '', footer = '', wide = false, cls = '', onClose } = {}) {
  const wrap = document.createElement('div');
  wrap.className = 'modal';
  wrap.innerHTML = `<div class="modal-card ${wide ? 'wide' : ''} ${cls}" role="dialog" aria-modal="true" aria-label="${esc(title || '')}">
    ${title ? `<header><h2>${esc(title)}</h2><button class="x-btn" data-close aria-label="قفل">×</button></header>` : ''}
    <div class="body">${String(body)}</div>${footer ? `<footer>${String(footer)}</footer>` : ''}</div>`;
  document.body.appendChild(wrap);
  modalDepth++;
  let resolve; const done = new Promise((r) => { resolve = r; });
  const prev = document.activeElement;
  const close = (v) => {
    if (!wrap.isConnected) return;
    wrap.remove(); modalDepth--; document.removeEventListener('keydown', onKey, true);
    if (onClose) onClose(v); resolve(v);
    if (prev && prev.focus) try { prev.focus(); } catch (e) {}
  };
  const onKey = (e) => { if (e.key === 'Escape' && wrap === [...document.querySelectorAll('.modal')].pop()) { e.preventDefault(); e.stopPropagation(); close(); } };
  document.addEventListener('keydown', onKey, true);
  wrap.addEventListener('mousedown', (e) => { if (e.target === wrap) close(); });
  wrap.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => close()));
  setTimeout(() => { const f = wrap.querySelector('[autofocus]') || wrap.querySelector('input, select, textarea') || wrap.querySelector('footer .btn:last-child'); if (f) f.focus(); }, 30);
  return { el: wrap, card: wrap.firstElementChild, close, done };
}
export const modalOpen = () => modalDepth > 0;

export function confirmBox(title, text, okLabel = 'تمام', danger = false) {
  const m = modal({ title, body: h`<p style="margin:0">${text}</p>`,
    footer: h`<button class="btn quiet" data-close>لأ</button><button class="btn ${danger ? '' : 'ok'}" data-ok>${okLabel}</button>` });
  m.el.querySelector('[data-ok]').addEventListener('click', () => m.close(true));
  return m.done.then((v) => v === true);
}

export async function copyText(t) {
  try { await navigator.clipboard.writeText(t); toast('اتنسخ ✓', 'good'); return true; }
  catch (e) {
    const ta = document.createElement('textarea'); ta.value = t; document.body.appendChild(ta); ta.select();
    let ok = false; try { ok = document.execCommand('copy'); } catch (er) {} ta.remove();
    toast(ok ? 'اتنسخ ✓' : 'مقدرتش أنسخ: انسخ بإيدك', ok ? 'good' : 'bad'); return ok;
  }
}
// رابط واتساب: بيفتح المحادثة والرسالة مكتوبة، والمالك هو اللي بيدوس إرسال (مفيش إرسال أوتوماتيك)
export function waLink(phone, text) {
  let p = String(phone || '').replace(/\D/g, '');
  if (p.startsWith('0')) p = '2' + p; else if (p && !p.startsWith('20')) p = '20' + p;
  return 'https://wa.me/' + (p || '') + '?text=' + encodeURIComponent(text);
}

export function debounce(fn, ms) { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; }
export function skeleton(rows = 4) { return raw(Array.from({ length: rows }, () => '<div class="skel" style="margin:12px 0"></div>').join('')); }
export function empty(title, text = '') { return h`<div class="empty"><b>${title}</b>${text}</div>`; }
export function errorBox(e) { return h`<div class="empty"><b>مقدرتش أجيب البيانات</b>${e && e.message || ''}</div>`; }

// صوت صغير لما الصنف يدخل الفاتورة (الكاشير بيعرف إن الباركود اتقرا من غير ما يبص)
let actx;
export function beep(ok = true) {
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const o = actx.createOscillator(), g = actx.createGain();
    o.type = 'sine'; o.frequency.value = ok ? 1320 : 220;
    g.gain.setValueAtTime(0.0001, actx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.12, actx.currentTime + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, actx.currentTime + (ok ? 0.09 : 0.25));
    o.connect(g).connect(actx.destination); o.start(); o.stop(actx.currentTime + 0.3);
  } catch (e) {}
}
