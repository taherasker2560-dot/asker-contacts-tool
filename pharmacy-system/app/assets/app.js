// صيدلية عسكر — الشاشات. صفحة واحدة: الدخول، الهيكل (القائمة + البحث فوق كل حاجة)، والتنقل بين الشاشات.
import * as api from './api.js';
import { h, raw, esc, render, $, $$, icon, toast, modal, modalOpen, initials, debounce, money, qty, dateLong, time } from './ui.js';
import { initKeyboard, guide } from './kbd.js';

const root = document.getElementById('root');

// ---------------------------------------------------------------- الشاشات والصلاحيات
const ALL = ['owner', 'manager', 'pharmacist', 'cashier'];
const MGMT = ['owner', 'manager'];
const CLIN = ['owner', 'manager', 'pharmacist'];
export const ROUTES = [
  { path: '', view: 'dashboard', label: 'لوحة النهارده', icon: 'home', roles: CLIN, grp: 'اليوم' },
  { path: 'pos', view: 'pos', label: 'البيع', icon: 'pos', roles: ALL, grp: 'اليوم', key: 'F2' },
  { path: 'items', view: 'items', label: 'الأصناف والمخزون', icon: 'pill', roles: ALL, grp: 'المخزن' },
  { path: 'purchases', view: 'purchases', label: 'المشتريات', icon: 'box', roles: CLIN, grp: 'المخزن' },
  { path: 'expiry', view: 'expiry', label: 'الصلاحية', icon: 'hourglass', roles: CLIN, grp: 'المخزن', badge: 'expiring_30d' },
  { path: 'orders', view: 'orders', label: 'الطلبيات الذكية', icon: 'truck', roles: CLIN, grp: 'المخزن', badge: 'shortages' },
  { path: 'customers', view: 'customers', label: 'العملاء', icon: 'users', roles: CLIN, grp: 'الناس والفلوس', badge: 'refills_due' },
  { path: 'suppliers', view: 'suppliers', label: 'الموردين', icon: 'factory', roles: MGMT, grp: 'الناس والفلوس' },
  { path: 'cash', view: 'cash', label: 'الخزن', icon: 'wallet', roles: MGMT, grp: 'الناس والفلوس' },
  { path: 'reports', view: 'reports', label: 'التقارير', icon: 'chart', roles: MGMT, grp: 'الإدارة' },
  { path: 'settings', view: 'settings', label: 'الإعدادات والتجربة', icon: 'gear', roles: MGMT, grp: 'الإدارة', badge: 'open_notes' },
];
const ROLE_AR = { owner: 'المالك', manager: 'المدير', pharmacist: 'صيدلي', cashier: 'كاشير', delivery: 'دليفري', bot: 'البوت' };

export const state = { user: null, settings: null, dash: null, cleanup: null, view: null };
export const can = (roles) => !!state.user && roles.includes(state.user.role);
export const go = (hash) => { if (location.hash === hash) route(); else location.hash = hash; };

// ---------------------------------------------------------------- البداية
api.setUnauthorizedHandler(() => { if (state.user) { logout(); toast('انتهت الجلسة: ادخل تاني', 'bad'); } });

function start() {
  const s = api.session.get();
  if (s && s.token && (!s.expires_at || new Date(s.expires_at) > new Date())) { state.user = s; boot(); }
  else showLogin();
}

function logout() {
  api.session.clear(); state.user = null; state.dash = null;
  if (state.cleanup) { try { state.cleanup(); } catch (e) {} state.cleanup = null; }
  showLogin();
}

// ---------------------------------------------------------------- الدخول
function showLogin(msg = '') {
  document.title = 'صيدلية عسكر — الدخول';
  render(root, h`<div class="login">
    <section class="art"><div class="inner">
      <img class="logo logo-lg" src="assets/logo-256.webp" width="168" height="168" alt="لوجو صيدلية عسكر">
      <h1>صيدلية عسكر</h1>
      <p>البيع والمخزن والحسابات… في مكان واحد</p>
      <span class="since">من ١٩٨١</span>
    </div></section>
    <form id="login" autocomplete="on">
      <div><h2>أهلًا بيك</h2><p class="muted" style="margin:4px 0 0">ادخل باسمك وكلمة السر</p></div>
      ${msg ? h`<div class="err">${msg}</div>` : ''}
      <div class="field"><label for="u">اسم الدخول</label><input class="input ltr" id="u" name="username" autocomplete="username" required autofocus></div>
      <div class="field"><label for="p">كلمة السر</label><input class="input ltr" id="p" name="password" type="password" autocomplete="current-password" required></div>
      <button class="btn lg" type="submit">دخول</button>
      <p class="muted" style="font-size:13px;margin:0">٥ محاولات غلط بتقفل الحساب ربع ساعة. البرنامج شغال على جهاز الصيدلية بس.</p>
    </form></div>`);
  $('#login').addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = e.target.querySelector('button'); btn.disabled = true; btn.textContent = 'لحظة…';
    try {
      const r = await api.login($('#u').value.trim(), $('#p').value);
      state.user = api.session.get();
      if (r.role === 'bot' || r.role === 'delivery') { api.session.clear(); state.user = null; return showLogin('اليوزر ده للبوت/الدليفري: مالوش شاشات هنا'); }
      if (location.hash === '' || location.hash === '#/') location.hash = r.role === 'cashier' ? '#/pos' : '#/';
      boot();
    } catch (err) { showLogin(err.message || 'اسم الدخول أو كلمة السر غلط'); }
  });
}

// ---------------------------------------------------------------- الهيكل
async function boot() {
  try { state.settings = await api.one('settings', { id: 'eq.1' }); } catch (e) { state.settings = null; }
  renderShell();
  window.addEventListener('hashchange', route);
  route();
  refreshBadges();
  clearInterval(state.badgeTimer); state.badgeTimer = setInterval(refreshBadges, 60000);
  clearInterval(state.clockTimer); state.clockTimer = setInterval(tickClock, 15000);
  api.outbox.flush().then((r) => { if (r.sent) toast(`اتبعت ${r.sent} فاتورة كانت مستنية الشبكة ✓`, 'good'); }).catch(() => {});
}

function navLinks() {
  let grp = '', out = '', n = 0;
  for (const r of ROUTES) {
    if (!can(r.roles)) continue;
    if (r.grp !== grp) { grp = r.grp; out += `<div class="grp">${esc(grp)}</div>`; }
    n++;
    const k = n <= 9 ? String(n) : n === 10 ? '0' : '';
    out += String(h`<a href="#/${r.path}" data-path="${r.path}" title="${k ? 'Alt+' + k : ''}">${icon(r.icon)}<span>${r.label}</span>${r.badge ? h`<span class="badge" data-badge="${r.badge}" hidden></span>` : ''}${k ? h`<kbd class="nav-k">${k}</kbd>` : ''}</a>`);
  }
  return raw(out);
}

function renderShell() {
  const u = state.user, demo = state.settings && state.settings.demo_data;
  const mobile = ROUTES.filter((r) => can(r.roles)).slice(0, 4);
  render(root, h`<div class="shell">
    <aside class="side" aria-label="القائمة">
      <div class="brand"><img class="logo" src="assets/logo-96.png" width="48" height="48" alt="لوجو صيدلية عسكر"><div><b>${(state.settings && state.settings.pharmacy_name) || 'صيدلية عسكر'}</b><small>برنامج الصيدلية</small></div></div>
      <nav class="nav">${navLinks()}</nav>
      <div class="side-foot">
        <div class="me"><div class="avatar">${initials(u.name)}</div><div><b>${u.name}</b><small>${ROLE_AR[u.role] || u.role}</small></div></div>
        <div class="side-btns">
          <button id="theme" title="نهاري / ليلي">${icon('moon')}</button>
          <button id="out" title="خروج">${icon('logout')} خروج</button>
        </div>
      </div>
    </aside>
    <div class="main">
      ${demo ? h`<div class="demo-ribbon">نسخة تجريبية ببيانات وهمية — للعرض والتجربة بس</div>` : ''}
      <header class="top">
        <button class="omni" id="omni" aria-label="ابحث أو اكتب أمر">${icon('search')}<span>دوّر على صنف، عميل، أو أمر…</span><kbd>F3</kbd></button>
        <button class="btn quiet sm kb-help" id="kbhelp" title="دليل الاختصارات">${icon('key')} الاختصارات <kbd>F1</kbd></button>
        <div class="clock" id="clock"></div>
      </header>
      <main class="page" id="page" tabindex="-1"></main>
    </div>
    <nav class="bottom-nav" aria-label="القائمة">${mobile.map((r) => h`<a href="#/${r.path}" data-path="${r.path}">${icon(r.icon)}<span>${r.label.split(' ')[0]}</span></a>`)}<a href="#" id="more">${icon('gear')}<span>المزيد</span></a></nav>
  </div>
  <button class="fab" id="fab" title="سجّل مشكلة أو فكرة في التجربة (Alt+N)">${icon('note')}<span>سجّل ملاحظة <kbd>Alt+N</kbd></span></button>`);
  $('#out').addEventListener('click', logout);
  $('#theme').addEventListener('click', toggleTheme);
  $('#omni').addEventListener('click', openPalette);
  $('#kbhelp').addEventListener('click', () => guide({ routes: ROUTES, can, screenKeys: (state.view && state.view.keys) || [] }));
  $('#fab').addEventListener('click', noteDialog);
  // الموبايل: «المزيد» بيفتح القايمة كلها (التقارير والعملاء والإعدادات…)
  $('#more').addEventListener('click', (e) => {
    e.preventDefault();
    const m = modal({ title: 'القايمة', body: h`<div class="list">${ROUTES.filter((r) => can(r.roles)).map((r) => h`<a class="li" href="#/${r.path}" style="text-decoration:none;color:inherit"><span class="ico i-crimson">${icon(r.icon)}</span><div class="grow"><b>${r.label}</b></div></a>`)}
      <button class="li" id="m-theme" style="border:0;background:none;width:100%;text-align:start"><span class="ico i-gold">${icon('moon')}</span><div class="grow"><b>نهاري / ليلي</b></div></button>
      <button class="li" id="m-out" style="border:0;background:none;width:100%;text-align:start"><span class="ico i-bad">${icon('logout')}</span><div class="grow"><b>خروج</b></div></button></div>` });
    m.el.addEventListener('click', (ev) => { if (ev.target.closest('a')) m.close(); });
    $('#m-theme', m.el).addEventListener('click', () => { m.close(); toggleTheme(); });
    $('#m-out', m.el).addEventListener('click', () => { m.close(); logout(); });
  });
  tickClock();
  syncThemeIcon();
}

function tickClock() {
  const c = $('#clock'); if (!c) return;
  const now = new Date();
  c.innerHTML = String(h`<b>${time(now)}</b>${dateLong(now)}`);
}

function toggleTheme() {
  const night = document.documentElement.dataset.theme === 'dark';
  window.AskerTheme.setNight(!night);
  syncThemeIcon();
  route(true);   // الرسوم بتتلوّن من جديد
}
function syncThemeIcon() {
  const b = $('#theme'); if (!b) return;
  b.innerHTML = String(icon(document.documentElement.dataset.theme === 'dark' ? 'sun' : 'moon'));
}
// ألوان البرنامج: نفس الـ 25 لون بتوع البوت والموقع + «لون من اختيارك» + الليلي. محفوظة على الجهاز ده
export function colorDialog() {
  const T = window.AskerTheme;
  const draw = () => {
    const c = T.choice();
    return h`<div class="stack">
      <p class="muted" style="margin:0">نفس ألوان البوت والموقع. «أزرق عسكر» هو لون اللوجو. الاختيار بيتحفظ على الجهاز ده.</p>
      <div class="swatches" id="sw" role="radiogroup" aria-label="اللون">${T.PRESETS.map((p) => h`<button type="button" class="sw ${p.id === c.id ? 'on' : ''}" role="radio" aria-checked="${p.id === c.id}" data-accent="${p.id}"><i style="background:${T.palette(p.hex, false).main}"></i>${p.name}</button>`)}</div>
      <div class="row wrap" style="gap:14px">
        <label class="row" style="gap:8px"><input type="color" id="swc" value="${c.hex}" style="width:44px;height:34px;border:0;background:none;padding:0"> لون من اختيارك</label>
        <label class="row" style="gap:8px;margin-inline-start:auto"><input type="checkbox" id="swn" ${c.night ? 'checked' : ''}> الوضع الليلي <kbd>Alt+T</kbd></label>
      </div></div>`;
  };
  const m = modal({ title: 'ألوان البرنامج', wide: true, body: draw(), footer: h`<span class="muted" style="margin-inline-end:auto;font-size:13px"><kbd>←</kbd><kbd>→</kbd><kbd>↑</kbd><kbd>↓</kbd> اختار اللون · <kbd>Esc</kbd> تمام</span><button class="btn quiet" id="swr">رجّع أزرق عسكر</button><button class="btn" data-close>تمام</button>` });
  const body = m.card.querySelector('.body');
  const redraw = (focusId) => { body.innerHTML = String(draw()); bind(); const f = body.querySelector(`[data-accent="${focusId}"]`) || body.querySelector('.sw.on'); if (f) f.focus(); syncThemeIcon(); };
  function bind() {
    $('#sw', m.el).addEventListener('click', (e) => { const b = e.target.closest('[data-accent]'); if (b) { T.setAccent(b.dataset.accent); redraw(b.dataset.accent); } });
    $('#sw', m.el).addEventListener('keydown', (e) => {   // الألوان بالأسهم (الشبكة من اليمين للشمال)
      const all = [...m.el.querySelectorAll('.sw')], i = all.indexOf(document.activeElement); if (i < 0) return;
      const cols = Math.max(1, Math.round($('#sw', m.el).clientWidth / all[0].offsetWidth));
      const d = { ArrowLeft: 1, ArrowRight: -1, ArrowDown: cols, ArrowUp: -cols }[e.code];
      if (d == null) return;
      e.preventDefault(); const n = all[Math.max(0, Math.min(all.length - 1, i + d))]; T.setAccent(n.dataset.accent); redraw(n.dataset.accent);
    });
    const custom = (e) => { if (/^#[0-9a-f]{6}$/i.test(e.target.value)) { T.setAccent('c:' + e.target.value.toLowerCase()); syncThemeIcon(); body.querySelectorAll('.sw').forEach((x) => x.classList.remove('on')); } };
    $('#swc', m.el).addEventListener('input', custom); $('#swc', m.el).addEventListener('change', custom);
    $('#swn', m.el).addEventListener('change', (e) => { T.setNight(e.target.checked); syncThemeIcon(); });
  }
  bind();
  $('#swr', m.el).addEventListener('click', () => { T.setAccent('asker'); redraw('asker'); });
  setTimeout(() => { const f = m.el.querySelector('.sw.on'); if (f) f.focus(); }, 40);
  m.done.then(() => route(true));   // الرسوم تتلوّن باللون الجديد
}

export async function refreshBadges() {
  if (!can(CLIN)) return;
  try {
    state.dash = await api.one('v_dashboard');
    if (!state.dash) return;
    $$('[data-badge]').forEach((b) => { const v = Number(state.dash[b.dataset.badge] || 0); b.textContent = v; b.hidden = !v; });
  } catch (e) {}
}

// ---------------------------------------------------------------- التنقل
const viewCache = {};
let routeSeq = 0;
async function route(soft) {
  if (!state.user) return;
  const raw0 = location.hash.replace(/^#\/?/, '');
  const [path, ...rest] = raw0.split('/');
  let r = ROUTES.find((x) => x.path === path);
  if (!r || !can(r.roles)) {
    r = ROUTES.find((x) => can(x.roles));
    if (!r) return;
    if (location.hash !== '#/' + r.path) { history.replaceState(null, '', '#/' + r.path); }
  }
  $$('.nav a, .bottom-nav a').forEach((a) => a.classList.toggle('on', a.dataset.path === r.path));
  document.title = r.label + ' — صيدلية عسكر';
  if (state.cleanup) { try { state.cleanup(); } catch (e) {} state.cleanup = null; }
  const page = $('#page');
  const seq = ++routeSeq;
  if (soft !== true) { page.style.animation = 'none'; void page.offsetWidth; page.style.animation = ''; }
  try {
    const mod = viewCache[r.view] || (viewCache[r.view] = await import(`./views/${r.view}.js`));
    if (seq !== routeSeq) return;
    state.view = mod;
    // كل شاشة في عنصر جديد: أي مستمع اتسجل على الشاشة القديمة بيتشال معاها
    page.innerHTML = '';
    const view = document.createElement('div'); page.appendChild(view);
    const cleanup = await mod.default({ el: view, params: rest.map(decodeURIComponent), api, state, can, go });
    if (seq === routeSeq) state.cleanup = typeof cleanup === 'function' ? cleanup : null; else if (typeof cleanup === 'function') cleanup();
  } catch (e) {
    console.error(e);
    page.innerHTML = String(h`<div class="card empty"><b>الشاشة دي وقعت</b>${e.message}</div>`);
  }
  if (soft !== true) window.scrollTo(0, 0);
}

// ---------------------------------------------------------------- لوحة الأوامر Ctrl+K
const COMMANDS = () => [
  ...ROUTES.filter((r) => can(r.roles)).map((r, i) => ({ grp: 'روح لـ', label: r.label, icon: r.icon, run: () => go('#/' + r.path), kw: r.path, end: i < 9 ? 'Alt+' + (i + 1) : i === 9 ? 'Alt+0' : '' })),
  { grp: 'أوامر', label: 'فاتورة جديدة', icon: 'receipt', run: () => go('#/pos'), kw: 'new sale بيع', roles: ALL },
  { grp: 'أوامر', label: 'فاتورة شرا جديدة', icon: 'box', run: () => go('#/purchases/new'), kw: 'purchase شرا مشتريات', roles: CLIN },
  { grp: 'أوامر', label: 'مصروف / تحويل بين الخزن', icon: 'wallet', run: () => go('#/cash'), kw: 'cash expense خزنة مصروف توريد', roles: MGMT },
  { grp: 'أوامر', label: 'جهّز طلبيات النهارده', icon: 'truck', run: () => go('#/orders'), kw: 'order طلب', roles: CLIN },
  { grp: 'أوامر', label: 'مواعيد صرف العملاء', icon: 'bell', run: () => go('#/customers'), kw: 'refill مزمن', roles: CLIN },
  { grp: 'أوامر', label: 'افحص سلامة القاعدة', icon: 'shield', run: () => go('#/settings'), kw: 'health فحص', roles: MGMT },
  { grp: 'أوامر', label: 'سجّل ملاحظة في التجربة', icon: 'note', run: noteDialog, kw: 'note bug مشكلة', roles: ALL, end: 'Alt+N' },
  { grp: 'أوامر', label: 'نهاري / ليلي', icon: 'moon', run: toggleTheme, kw: 'theme dark ليل', roles: ALL, end: 'Alt+T' },
  { grp: 'أوامر', label: 'ألوان البرنامج', icon: 'sparkle', run: colorDialog, kw: 'color theme لون ألوان ازرق عنابي', roles: ALL, end: 'Alt+K' },
  { grp: 'أوامر', label: 'دليل الاختصارات', icon: 'key', run: () => guide({ routes: ROUTES, can, screenKeys: (state.view && state.view.keys) || [] }), kw: 'keys shortcuts اختصارات كيبورد', roles: ALL, end: 'F1' },
  { grp: 'أوامر', label: 'خروج', icon: 'logout', run: logout, kw: 'logout', roles: ALL },
].filter((c) => !c.roles || can(c.roles));

export function openPalette(initial = '') {
  if (document.querySelector('.palette')) return;
  const m = modal({ cls: 'palette', body: h`<div class="p-in">${icon('search')}<input id="pq" placeholder="اسم صنف بالعربي أو الإنجليزي، باركود، عميل، أو أمر…" autocomplete="off"><kbd>Esc</kbd></div><div class="p-list" id="pl"></div>` });
  m.card.querySelector('.body').style.padding = '0';
  const input = $('#pq', m.el), list = $('#pl', m.el);
  input.value = typeof initial === 'string' ? initial : '';
  let items = [], sel = 0, seq = 0;
  const draw = () => {
    if (!items.length) { list.innerHTML = '<div class="empty"><b>مفيش نتايج</b>جرّب جزء من الاسم</div>'; return; }
    let grp = '', out = '';
    items.forEach((it, i) => {
      if (it.grp !== grp) { grp = it.grp; out += `<div class="p-grp">${esc(grp)}</div>`; }
      out += String(h`<div class="p-item ${i === sel ? 'on' : ''}" data-i="${i}"><span class="ico ${it.tone || 'i-crimson'}">${icon(it.icon)}</span><div class="grow"><b>${it.label}</b>${it.sub ? h`<span class="muted" style="font-size:13px">${it.sub}</span>` : ''}</div>${it.end ? h`<span class="muted num">${it.end}</span>` : ''}</div>`);
    });
    list.innerHTML = out;
    const on = list.querySelector('.p-item.on'); if (on) on.scrollIntoView({ block: 'nearest' });
  };
  const search = async () => {
    const q = input.value.trim(), my = ++seq;
    const cmds = COMMANDS().filter((c) => !q || (c.label + ' ' + c.kw).toLowerCase().includes(q.toLowerCase()));
    items = cmds.slice(0, q ? 6 : 12); sel = 0; draw();
    if (q.length < 2) return;
    const [its, cs] = await Promise.all([
      api.rpc('pos_lookup', { q, max_rows: 7 }).catch(() => []),
      can(CLIN) ? api.select('v_customer_pick', { or: `(name.ilike.*${q.replace(/[(),*]/g, ' ')}*,phone.like.*${q.replace(/\D/g, '') || '~'}*)`, limit: 5 }).catch(() => []) : [],
    ]);
    if (my !== seq) return;
    items = [
      ...its.map((it) => ({ grp: 'أصناف', icon: it.is_fridge ? 'fridge' : 'pill', label: it.name_ar || it.name_en, sub: it.name_en + ' · ' + (Number(it.onhand_units) > 0 ? 'موجود ' + qty(it.onhand_units, it.pack_parts, it.pack_name, it.unit_name) : 'ناقص'), end: money(it.price_pack) + ' ج', tone: Number(it.onhand_units) > 0 ? 'i-good' : 'i-bad', run: () => go('#/items/' + it.id) })),
      ...cs.map((c) => ({ grp: 'عملاء', icon: 'user', label: c.name, sub: (c.phone || '') + (c.area ? ' · ' + c.area : ''), end: Number(c.balance) > 0 ? 'عليه ' + money(c.balance) : '', tone: 'i-gold', run: () => go('#/customers/' + c.id) })),
      ...cmds.slice(0, 4),
    ];
    sel = 0; draw();
  };
  const runSel = () => { const it = items[sel]; if (!it) return; m.close(); it.run(); };
  input.addEventListener('input', debounce(search, 140));
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); sel = Math.min(items.length - 1, sel + 1); draw(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); sel = Math.max(0, sel - 1); draw(); }
    else if (e.key === 'Enter') { e.preventDefault(); runSel(); }
  });
  list.addEventListener('click', (e) => { const p = e.target.closest('.p-item'); if (p) { sel = +p.dataset.i; runSel(); } });
  search();
  setTimeout(() => input.focus(), 20);
}

// ---------------------------------------------------------------- ملاحظات التجربة (أي حد بيجرب)
export function noteDialog() {
  const m = modal({ title: 'سجّل ملاحظة في التجربة',
    body: h`<form id="nf" class="stack">
      <p class="muted" style="margin:0">اكتب اللي حصل بالظبط وإنت فين. بتتسجل باسمك ووقتها، وأنا بشوفها وأصلّحها.</p>
      <div class="field"><label>نوعها</label><div class="chips" id="sev">
        <button type="button" class="chip" data-v="blocker">واقف خالص</button><button type="button" class="chip on" data-v="bug">غلط</button>
        <button type="button" class="chip" data-v="annoyance">مزعج</button><button type="button" class="chip" data-v="idea">فكرة</button></div></div>
      <div class="field"><label for="na">في أنهي جزء</label><select class="input" id="na">
        <option value="sales">البيع</option><option value="stock">المخزن</option><option value="purchases">الشرا</option><option value="accounts">الحسابات</option>
        <option value="reports">التقارير</option><option value="bot">البوت</option><option value="other" selected>حاجة تانية</option></select></div>
      <div class="field"><label for="nt">الملاحظة</label><textarea class="input" id="nt" rows="4" required minlength="3" autofocus placeholder="مثلاً: لما بدوّر على بنادول بالعربي مش بيطلع"></textarea></div>
    </form>`,
    footer: h`<span class="muted" style="margin-inline-end:auto;font-size:13px"><kbd>Ctrl</kbd>+<kbd>Enter</kbd> سجّل · <kbd>←</kbd><kbd>→</kbd> النوع</span><button class="btn quiet" data-close>إلغاء</button><button class="btn" id="ns">سجّل</button>` });
  let sev = 'bug';
  $('#sev', m.el).addEventListener('click', (e) => { const c = e.target.closest('.chip'); if (!c) return; sev = c.dataset.v; $$('#sev .chip', m.el).forEach((x) => x.classList.toggle('on', x === c)); });
  const area = { pos: 'sales', items: 'stock', expiry: 'stock', orders: 'purchases', purchases: 'purchases', cash: 'accounts', customers: 'accounts', suppliers: 'accounts', reports: 'reports' }[location.hash.replace(/^#\/?/, '').split('/')[0]];
  if (area) $('#na', m.el).value = area;
  $('#ns', m.el).addEventListener('click', async () => {
    const note = $('#nt', m.el).value.trim();
    if (note.length < 3) { $('#nt', m.el).focus(); return; }
    try { await api.insert('trial_notes', { area: $('#na', m.el).value, severity: sev, note: note + ' [' + (location.hash || '#/') + ']' }); m.close(); toast('اتسجلت ✓ شكرًا', 'good'); refreshBadges(); }
    catch (e) { toast(e.message, 'bad'); }
  });
}

// ---------------------------------------------------------------- الكيبورد (kbd.js): البرنامج كله من غير ماوس
initKeyboard({
  ready: () => !!state.user && !!document.getElementById('page'),
  go, palette: () => openPalette(), note: noteDialog, theme: toggleTheme, colors: colorDialog,
  refresh: () => { route(true); refreshBadges(); toast('اتحدّث ✓'); },
  nav: (n) => { const r = ROUTES.filter((x) => can(x.roles))[n - 1]; if (r) go('#/' + r.path); },
  guide: () => guide({ routes: ROUTES, can, screenKeys: (state.view && state.view.keys) || [] }),
});
window.addEventListener('online', () => api.outbox.flush().then((r) => { if (r.sent) toast(`الشبكة رجعت: اتبعت ${r.sent} فاتورة ✓`, 'good'); }));

start();
