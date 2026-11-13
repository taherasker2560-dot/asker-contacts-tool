// الكاشير: كل حاجة بالكيبورد. باركود أو جزء من الاسم ← Enter ← الصنف في الفاتورة (بصوت). Ctrl+Enter = خلّص.
// القاعدة هي اللي بتختار التشغيلة (الأقرب صلاحية) وبتحسب السعر الفعلي، والشاشة بتعرض تقدير لحد ما الفاتورة تترحّل.
import { h, render, $, $$, icon, money, moneyR, int, qty, dateMY, dateTime, toast, modal, beep, debounce, esc, expiryPill, confirmBox } from '../ui.js';
import { POS_KEYS, combo, typing } from '../kbd.js';

export const keys = POS_KEYS;   // للدليل (F1)

const PARK = 'asker.parked';
const METHODS = [
  { code: 'cash', label: 'كاش', key: 'F8' }, { code: 'card', label: 'فيزا', key: 'F10' },
  { code: 'wallet', label: 'محفظة', key: 'F11' }, { code: 'credit', label: 'آجل', key: 'F9' },
];

export default async function pos({ el, api, state }) {
  let cart = [], customer = null, method = 'cash', shift = null, results = [], sel = 0, seq = 0, lastQ = '', mult = 1, busy = false, csel = -1, cIdx = 0;
  const parked = () => { try { return JSON.parse(localStorage.getItem(PARK)) || []; } catch (e) { return []; } };
  const saveParked = (l) => { try { localStorage.setItem(PARK, JSON.stringify(l)); } catch (e) {} };

  render(el, h`
    <div class="head"><div><h1>البيع</h1><p>باركود أو اسم الصنف ← Enter. الأقرب صلاحية بيطلع الأول لوحده.</p></div>
      <div class="actions" id="parkbar"></div></div>
    <div class="shift-bar" id="shift"></div>
    <div id="outbox"></div>
    <div class="pos">
      <section>
        <div class="pos-search">${icon('barcode')}
          <input class="input" id="q" placeholder="امسح الباركود أو اكتب الاسم (عربي أو إنجليزي)… 3* قبل الباركود = 3 علب" autocomplete="off" aria-label="بحث الصنف">
          <div class="results" id="res" hidden></div></div>
        <div class="card cart" id="cart"></div>
        <div class="keys"><span><kbd>F2</kbd> البحث</span><span><kbd>↑</kbd><kbd>↓</kbd> أصناف الفاتورة</span><span><kbd>+</kbd><kbd>−</kbd> الكمية</span><span><kbd>*</kbd> علبة/شريط</span><span><kbd>Del</kbd> شيل</span>
          <span><kbd>Alt+C</kbd> العميل</span><span><kbd>Alt+X</kbd> خصم</span><span><kbd>F8</kbd> كاش</span><span><kbd>F9</kbd> آجل</span><span><kbd>F10</kbd> فيزا</span>
          <span><kbd>Alt+P</kbd> علّق</span><span><kbd>Alt+L</kbd> آخر فاتورة</span><span><kbd>Ctrl</kbd>+<kbd>Enter</kbd> خلّص</span><span><kbd>F1</kbd> كل الاختصارات</span></div>
      </section>
      <aside class="register" id="reg" aria-label="الحساب"></aside>
    </div>`);
  const q = $('#q', el), resBox = $('#res', el);

  // ------------------------------------------------------------ الوردية
  async function loadShift() {
    try { shift = (await api.rpc('my_open_shift'))[0] || null; } catch (e) { shift = null; }
    drawShift();
  }
  function drawShift() {
    const box = $('#shift', el);
    if (!shift) {
      render(box, h`<span class="ico i-gold">${icon('cash')}</span><div style="flex:1"><b>مفيش وردية مفتوحة باسمك</b><div class="muted" style="font-size:13px">افتح وردية عشان الكاش يدخل درجك ويتقفل عليك آخر اليوم</div></div>
        <button class="btn gold" id="open-shift" data-hot="alt+o">${icon('plus')} افتح وردية <kbd>Alt+O</kbd></button>`);
      $('#open-shift', box).addEventListener('click', openShift);
      return;
    }
    render(box, h`<span class="ico i-good">${icon('cash')}</span>
      <div style="flex:1"><b>${shift.account} · وردية رقم ${shift.id}</b><div class="muted" style="font-size:13px">من ${dateTime(shift.opened_at)} · ${int(shift.sales_count)} فاتورة</div></div>
      <div style="text-align:end"><div class="muted" style="font-size:12px">المفروض في الدرج</div><b style="font-family:var(--f-display);font-size:20px">${money(shift.expected_cash)}</b></div>
      <button class="btn quiet sm" id="close-shift" data-hot="alt+o">اقفل الوردية <kbd>Alt+O</kbd></button>`);
    $('#close-shift', box).addEventListener('click', closeShift);
  }
  async function openShift() {
    let drawers = [];
    try { drawers = await api.select('cash_accounts', { kind: 'eq.drawer', active: 'eq.true', order: 'id' }); } catch (e) {}
    const m = modal({ title: 'فتح وردية', body: h`<div class="stack">
        <div class="field"><label>الدرج</label><select class="input" id="acc">${drawers.map((d) => h`<option value="${d.id}">${d.name}</option>`)}</select></div>
        <div class="field"><label>الفكّة اللي في الدرج دلوقتي</label><input class="input num" id="oc" type="number" min="0" step="0.5" value="0"></div></div>`,
      footer: h`<button class="btn quiet" data-close>إلغاء</button><button class="btn" id="go">افتح</button>` });
    $('#go', m.el).addEventListener('click', async () => {
      try { await api.rpc('open_shift', { p_account: +$('#acc', m.el).value, p_opening_cash: +$('#oc', m.el).value || 0 }); m.close(); toast('الوردية اتفتحت ✓', 'good'); loadShift(); }
      catch (e) { toast(e.message, 'bad'); }
    });
  }
  async function closeShift() {
    await loadShift(); if (!shift) return;
    const m = modal({ title: 'قفل الوردية', body: h`<div class="stack">
        <p style="margin:0">عِدّ الفلوس اللي في الدرج واكتبها. البرنامج هيقارنها باللي المفروض يكون ويسجّل الفرق.</p>
        <div class="field"><label>اللي في الدرج فعلًا</label><input class="input num" id="cc" type="number" min="0" step="0.5" autofocus></div>
        <p class="muted" style="margin:0">المفروض حسب البرنامج: <b>${money(shift.expected_cash)}</b> ج</p></div>`,
      footer: h`<button class="btn quiet" data-close>لسه</button><button class="btn" id="go">اقفل</button>` });
    $('#go', m.el).addEventListener('click', async () => {
      const v = $('#cc', m.el).value; if (v === '') return $('#cc', m.el).focus();
      try {
        const r = await api.rpc('close_shift', { p_shift: shift.id, p_counted: +v });
        m.close();
        const diff = Number(r.diff);
        modal({ title: 'الوردية اتقفلت', body: h`<div style="text-align:center;padding:10px">
          <div class="ico ${diff === 0 ? 'i-good' : diff > 0 ? 'i-gold' : 'i-bad'}" style="margin:0 auto 10px;width:56px;height:56px">${icon(diff === 0 ? 'check' : 'alert')}</div>
          <h2 style="font-family:var(--f-display)">${diff === 0 ? 'الدرج مظبوط بالظبط' : diff > 0 ? 'زيادة ' + money(diff) + ' ج' : 'عجز ' + money(-diff) + ' ج'}</h2>
          <p class="muted">المفروض ${money(r.expected)} · اتعدّ ${money(r.counted)}. ${diff ? 'الفرق اتسجل في الحسابات.' : ''}</p></div>`,
          footer: h`<button class="btn" data-close>تمام</button>` });
        loadShift();
      } catch (e) { toast(e.message, 'bad'); }
    });
  }

  // ------------------------------------------------------------ البحث
  const unitPrice = (it) => Number(it.price_pack) / Number(it.pack_parts || 1);
  async function lookup(text) {
    const my = ++seq;
    let t = text.trim(); mult = 1;
    const m = t.match(/^(\d{1,3})\s*\*\s*(.+)$/); if (m) { mult = +m[1]; t = m[2].trim(); }
    if (t.length < 2 && !/^\d+$/.test(t)) { results = []; drawResults(); return []; }
    let r = [];
    lastQ = text.trim();
    try { r = await api.rpc('pos_lookup', { q: t, max_rows: 10 }); } catch (e) { if (my === seq) toast(e.message, 'bad'); return []; }
    if (my !== seq) return null;
    results = r; sel = 0; drawResults(); return r;
  }
  function drawResults() {
    if (!results.length || !q.value.trim()) { resBox.hidden = true; return; }
    resBox.hidden = false;
    render(resBox, h`${results.map((it, i) => {
      const on = Number(it.onhand_units) > 0;
      return h`<div class="res ${i === sel ? 'on' : ''}" data-i="${i}">
        <div><b>${it.name_ar || it.name_en}</b><span class="en">${it.name_en}</span>
          <div class="row" style="gap:6px;margin-top:3px">${it.is_controlled ? h`<span class="pill p-bad plain">جدول</span>` : ''}${it.needs_rx ? h`<span class="pill p-info plain">روشتة</span>` : ''}${it.nearest_expiry ? expiryPill(it.nearest_expiry) : ''}</div></div>
        <div class="stock">${on ? h`<span class="pill p-good">${qty(it.onhand_units, it.pack_parts, it.pack_name, it.unit_name)}</span>` : h`<span class="pill p-bad">ناقص</span> <button class="btn sm ghost" data-alt="${it.id}">${icon('swap')} بدايل</button>`}</div>
        <div class="price">${money(it.price_pack)}<span class="muted" style="font-size:12px;font-family:var(--f-ui)"> ج/${it.pack_name || 'علبة'}</span></div></div>`;
    })}`);
    const on = resBox.querySelector('.res.on'); if (on) on.scrollIntoView({ block: 'nearest' });
  }
  const onType = debounce(() => lookup(q.value), 110);
  q.addEventListener('input', onType);
  const target = () => (csel >= 0 && csel < cart.length ? csel : cart.length - 1);
  function selLine(i) { csel = Math.max(-1, Math.min(cart.length - 1, i)); draw(); const n = $$('.cart-line', el)[csel]; if (n) n.scrollIntoView({ block: 'nearest' }); }
  q.addEventListener('keydown', async (e) => {
    const c = combo(e), open = !resBox.hidden && results.length;
    if (c === 'ArrowDown' || c === 'ArrowUp') {
      e.preventDefault();
      if (open) { sel = c === 'ArrowDown' ? Math.min(results.length - 1, sel + 1) : Math.max(0, sel - 1); drawResults(); }
      else if (!q.value && cart.length) selLine(csel < 0 ? (c === 'ArrowDown' ? 0 : cart.length - 1) : csel + (c === 'ArrowDown' ? 1 : -1));
    } else if (c === 'Escape') {
      if (q.value) { q.value = ''; results = []; drawResults(); e.preventDefault(); e.stopPropagation(); }
      else if (csel >= 0) { selLine(-1); e.preventDefault(); e.stopPropagation(); }
    } else if (c === 'Alt+KeyB' && open) { e.preventDefault(); showAlts(results[sel].id); }
    else if (c === 'Enter') {
      e.preventDefault();
      if (!q.value.trim()) return;
      // الباركود بيتكتب بسرعة وبعده Enter على طول: ندوّر دلوقتي من غير ما نستنى
      let r = results;
      const isCode = /^(\d{1,3}\s*\*\s*)?\d{4,}$/.test(q.value.trim());
      // الكتابة لسه ماتدوّرش عليها (Enter بسرعة بعد آخر حرف): ندوّر الأول عشان مانضيفش صنف من بحث قديم
      if (isCode || !r.length || q.value.trim() !== lastQ) r = await lookup(q.value) || [];
      const pick = isCode ? (r.find((x) => x.exact) || (r.length === 1 ? r[0] : null)) : r[sel];
      if (pick) add(pick, mult); else { beep(false); toast('مالقيتش الصنف ده', 'bad'); }
    } else if (!q.value && cart.length && (c === 'Equal' || c === 'Shift+Equal' || c === 'NumpadAdd' || c === 'Minus' || c === 'NumpadSubtract')) {
      e.preventDefault(); bump(target(), /Add|Equal/.test(c) ? 1 : -1);
    } else if (!q.value && cart.length && (c === 'Shift+Digit8' || c === 'NumpadMultiply')) {
      e.preventDefault(); const l = cart[target()]; if (l.item.sell_by_unit && Number(l.item.pack_parts) > 1) { l.mode = l.mode === 'pack' ? 'unit' : 'pack'; draw(); } else toast('الصنف ده مابيتباعش بالشريط');
    } else if (!q.value && cart.length && c === 'Delete') { e.preventDefault(); cart.splice(target(), 1); if (csel >= cart.length) csel = cart.length - 1; draw(); }
  });
  resBox.addEventListener('mousedown', (e) => {
    const alt = e.target.closest('[data-alt]');
    if (alt) { e.preventDefault(); showAlts(+alt.dataset.alt); return; }
    const row = e.target.closest('.res'); if (!row) return;
    e.preventDefault(); add(results[+row.dataset.i], mult);
  });
  q.addEventListener('blur', () => setTimeout(() => { resBox.hidden = true; }, 150));
  q.addEventListener('focus', () => drawResults());

  async function showAlts(id) {
    let alts = [];
    try { alts = await api.rpc('item_alternatives', { p_item: id }); } catch (e) { return toast(e.message, 'bad'); }
    const src = results.find((r) => r.id === id);
    const m = modal({ title: 'بدايل ' + (src ? src.name_ar || src.name_en : ''), body: alts.length
      ? h`<p class="muted" style="margin-top:0">نفس المادة الفعالة والشكل، وموجودين في المخزن:</p><div class="list">${alts.map((a, i) => h`<div class="li"><span class="ico i-good">${icon('pill')}</span><div class="grow"><b>${a.name_ar || a.name_en}</b><span class="en">${a.name_en}</span></div>
          <div class="end"><b>${money(a.price_pack)}</b> ج<div class="muted" style="font-size:12px">${qty(a.onhand_units, a.pack_parts)}</div></div><button class="btn sm" data-i="${i}">أضف</button></div>`)}</div>`
      : h`<div class="empty"><b>مفيش بديل في المخزن</b>الصنف ده هيظهر في الطلبيات الذكية</div>` });
    m.el.addEventListener('click', async (e) => {
      const b = e.target.closest('[data-i]'); if (!b) return;
      const a = alts[+b.dataset.i];
      const r = await api.rpc('pos_lookup', { q: String(a.id), max_rows: 1 }).catch(() => []);
      if (r[0]) { add(r[0], 1); m.close(); }
    });
  }

  // ------------------------------------------------------------ الفاتورة
  function add(it, n = 1) {
    if (!it) return;
    const mode = 'pack';
    const ex = cart.find((l) => l.item.id === it.id && l.mode === mode);
    if (ex) ex.qty += n; else cart.push({ item: it, qty: n, mode });
    if (Number(it.onhand_units) <= 0) { beep(false); toast(state.settings && state.settings.allow_negative_stock ? `${it.name_ar || it.name_en}: الرصيد صفر، هيتباع بالسالب لحد ما فاتورة الشرا تتدخل` : `${it.name_ar || it.name_en}: الرصيد صفر، مش هيتباع`, 'bad'); } else beep(true);
    q.value = ''; results = []; mult = 1; csel = -1; drawResults(); draw(); q.focus();
  }
  const lineUnits = (l) => l.qty * (l.mode === 'pack' ? Number(l.item.pack_parts || 1) : 1);
  const lineTotal = (l) => Math.round(lineUnits(l) * unitPrice(l.item) * 100) / 100;
  function bump(i, d) { const l = cart[i]; l.qty = Math.max(0, Math.round((l.qty + d) * 100) / 100); if (!l.qty) { cart.splice(i, 1); if (csel >= cart.length) csel = cart.length - 1; } draw(); }

  function draw() {
    const box = $('#cart', el);
    if (!cart.length) {
      render(box, h`<div class="empty" style="padding:56px 10px"><div class="ico i-crimson" style="margin:0 auto 12px;width:56px;height:56px">${icon('barcode')}</div><b>الفاتورة فاضية</b>امسح أول صنف أو اكتب اسمه فوق</div>`);
    } else {
      render(box, h`${cart.map((l, i) => {
        const it = l.item, over = lineUnits(l) > Number(it.onhand_units);
        const canUnit = it.sell_by_unit && Number(it.pack_parts) > 1;
        return h`<div class="cart-line ${i === csel ? 'kb-sel' : ''}">
          <div class="nm"><b>${it.name_ar || it.name_en}</b><span class="en">${it.name_en}</span>
            <div class="meta">${it.is_controlled ? h`<span class="pill p-bad plain">جدول: محتاج بيانات الروشتة</span>` : ''}${it.needs_rx && !it.is_controlled ? h`<span class="pill p-info plain">روشتة</span>` : ''}
              ${over ? h`<span class="pill p-bad">الموجود ${qty(it.onhand_units, it.pack_parts, it.pack_name, it.unit_name)} بس</span>` : h`<span class="pill p-muted plain">${money(it.price_pack)} ج/${it.pack_name || 'علبة'}</span>`}
              ${it.nearest_expiry ? expiryPill(it.nearest_expiry) : ''}</div></div>
          <div class="qty"><button data-d="1" data-i="${i}" aria-label="زوّد">+</button><input data-q="${i}" value="${l.qty}" inputmode="decimal" aria-label="الكمية"><button data-d="-1" data-i="${i}" aria-label="قلّل">−</button>
            ${canUnit ? h`<button class="unit" data-u="${i}" title="علبة / ${it.unit_name}">${l.mode === 'pack' ? it.pack_name || 'علبة' : it.unit_name}</button>` : h`<span class="unit" style="display:grid;place-items:center">${it.pack_name || 'علبة'}</span>`}</div>
          <div class="tot">${money(lineTotal(l))}</div>
          <button class="x" data-x="${i}" aria-label="شيل">×</button></div>`;
      })}`);
    }
    drawReg();
  }
  $('#cart', el).addEventListener('click', (e) => {
    const t = e.target.closest('button'); if (!t) return;
    if (t.dataset.d) bump(+t.dataset.i, +t.dataset.d);
    else if (t.dataset.x) { cart.splice(+t.dataset.x, 1); draw(); }
    else if (t.dataset.u) { const l = cart[+t.dataset.u]; l.mode = l.mode === 'pack' ? 'unit' : 'pack'; draw(); }
  });
  $('#cart', el).addEventListener('change', (e) => {
    const i = e.target.dataset.q; if (i == null) return;
    const v = parseFloat(e.target.value); if (!(v > 0)) cart.splice(+i, 1); else cart[+i].qty = v; draw();
  });

  // ------------------------------------------------------------ الحساب
  const subtotal = () => cart.reduce((s, l) => s + lineTotal(l), 0);
  function drawReg() {
    const reg = $('#reg', el);
    const disc = Math.min(Number(reg.querySelector('#disc')?.value || 0), subtotal());
    const total = Math.max(0, subtotal() - disc);
    const tendered = reg.querySelector('#tend')?.value || '';
    const paidPart = reg.querySelector('#part')?.value || '';
    const units = cart.reduce((s, l) => s + l.qty, 0);
    const lim = customer ? Number(customer.credit_limit) - Number(customer.balance) : 0;
    const credit = method === 'credit' ? Math.max(0, total - Number(paidPart || 0)) : 0;
    render(reg, h`
      <div class="total"><small>المطلوب</small><b id="tot">${money(total)}</b><small>${int(cart.length)} صنف · ${units} قطعة</small></div>
      <div class="rows">
        <div class="row"><span>الإجمالي</span><span class="num">${money(subtotal())}</span></div>
        <div class="row"><span>خصم</span><input class="input num" id="disc" data-hot="alt+x" type="number" min="0" step="0.5" value="${disc || ''}" placeholder="0" style="width:110px;height:34px;text-align:center"></div>
      </div>
      <div class="field" style="position:relative"><label style="color:var(--on-c-2)">العميل</label>
        ${customer ? h`<div class="cust-box"><div class="row between"><b>${customer.name}</b><button class="btn sm quiet" id="unc" data-hot="alt+c" style="color:#fff;border-color:rgba(255,255,255,.25)">تغيير <kbd style="background:transparent;color:var(--on-c-2)">Alt+C</kbd></button></div>
            <div class="row between" style="font-size:13px;color:var(--on-c-2);margin-top:4px"><span>عليه ${money(customer.balance)}</span><span>الحد ${money(customer.credit_limit)}</span></div>
            <div class="meter"><i class="${Number(customer.balance) / Math.max(1, Number(customer.credit_limit)) > 0.85 ? 'bad' : 'warn'}" style="width:${Math.min(100, (Number(customer.balance) / Math.max(1, Number(customer.credit_limit))) * 100)}%"></i></div>
            <div id="cref"></div></div>`
          : h`<input class="input" id="cq" data-hot="alt+c" placeholder="اسم أو موبايل (Alt+C) — لازم للآجل" autocomplete="off"><div class="results" id="cres" hidden style="color:var(--ink)"></div>`}
      </div>
      <div class="pay">${METHODS.map((m) => h`<button data-m="${m.code}" class="${method === m.code ? 'on' : ''}">${m.label}<small>${m.key}</small></button>`)}</div>
      ${method === 'cash' ? h`<div class="rows"><div class="row"><span>المستلم</span><input class="input num" id="tend" data-hot="alt+r" type="number" min="0" value="${tendered}" placeholder="${moneyR(total)}" style="width:130px;height:38px;text-align:center"></div>
          <div class="chips" style="justify-content:flex-end">${[...new Set([Math.ceil(total / 10) * 10, Math.ceil(total / 50) * 50, Math.ceil(total / 100) * 100, Math.ceil(total / 200) * 200])].filter((v) => v > 0).slice(0, 4).map((v) => h`<button class="chip" data-t="${v}" style="background:rgba(255,255,255,.08);color:#fff;border-color:rgba(255,255,255,.2)">${v}</button>`)}</div>
          ${tendered && Number(tendered) >= total ? h`<div class="row" style="font-size:18px"><span>الباقي للعميل</span><b style="color:var(--gold-300);font-family:var(--f-display);font-size:26px">${money(Number(tendered) - total)}</b></div>` : ''}</div>` : ''}
      ${method === 'credit' ? h`<div class="rows"><div class="row"><span>دفع كاش دلوقتي</span><input class="input num" id="part" type="number" min="0" value="${paidPart}" placeholder="0" style="width:120px;height:38px;text-align:center"></div>
          <div class="row"><span>على الحساب</span><b>${money(credit)}</b></div>
          ${customer && credit > lim ? h`<div class="outbox" style="background:rgba(255,154,171,.15);color:#ffc2cc">هيعدّي الحد بـ ${money(credit - lim)} ج</div>` : ''}
          ${!customer ? h`<div class="outbox" style="background:rgba(227,199,126,.15);color:var(--gold-300)">الآجل محتاج تختار العميل</div>` : ''}</div>` : ''}
      <button class="done" id="pay" ${!cart.length || busy ? 'disabled' : ''}>${busy ? 'بيتسجل…' : h`خلّص الفاتورة <span style="opacity:.6;font-size:13px">Ctrl+Enter</span>`}</button>`);
    if (customer) loadCustomerHints();
  }
  const reg = $('#reg', el);
  reg.addEventListener('input', (e) => {
    if (e.target.id === 'cq') return custSearch(e.target.value);
    if (['disc', 'tend', 'part'].includes(e.target.id)) {
      const id = e.target.id, pos = e.target.selectionStart;
      drawReg(); const n = reg.querySelector('#' + id); if (n) { n.focus(); try { n.setSelectionRange(pos, pos); } catch (er) {} }
    }
  });
  reg.addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.m) { method = b.dataset.m; drawReg(); }
    else if (b.dataset.t) { const t = reg.querySelector('#tend'); t.value = b.dataset.t; drawReg(); }
    else if (b.id === 'pay') pay();
    else if (b.id === 'unc') { customer = null; drawReg(); setTimeout(() => reg.querySelector('#cq')?.focus(), 10); }
    else if (b.dataset.refill) { lookup(b.dataset.refill).then((r) => { if (r && r[0]) add(r[0], 1); }); }
  });

  let custRows = [];
  const custSearch = debounce(async (text) => {
    const box = reg.querySelector('#cres'); if (!box) return;
    const t = text.trim(); if (t.length < 2) { box.hidden = true; return; }
    const digits = t.replace(/\D/g, '');
    try {
      custRows = await api.select('v_customer_pick', { active: 'eq.true', or: digits.length >= 3 ? `(phone.like.*${digits}*)` : `(name.ilike.*${t.replace(/[(),*]/g, ' ')}*)`, limit: 6 });
    } catch (e) { custRows = []; }
    box.hidden = !custRows.length;
    cIdx = 0;
    render(box, h`${custRows.map((c, i) => h`<div class="res ${i === 0 ? 'on' : ''}" data-c="${i}" style="grid-template-columns:1fr auto"><div><b>${c.name}</b><span class="en">${c.phone || ''} ${c.area ? '· ' + c.area : ''}</span></div>
      <div class="stock">${Number(c.balance) > 0 ? h`<span class="pill p-warn">عليه ${money(c.balance)}</span>` : h`<span class="pill p-good">مفيش عليه</span>`}</div></div>`)}`);
  }, 160);
  // العميل بالكيبورد: ↑ ↓ Enter
  reg.addEventListener('keydown', (e) => {
    if (e.target.id === 'cq') {
      const box = reg.querySelector('#cres'); if (!box || box.hidden || !custRows.length) return;
      if (e.code === 'ArrowDown' || e.code === 'ArrowUp') { e.preventDefault(); cIdx = Math.max(0, Math.min(custRows.length - 1, cIdx + (e.code === 'ArrowDown' ? 1 : -1))); $$('#cres .res', reg).forEach((r, i) => r.classList.toggle('on', i === cIdx)); }
      else if (e.code === 'Enter' || e.code === 'NumpadEnter') { e.preventDefault(); customer = custRows[cIdx]; drawReg(); q.focus(); }
      else if (e.code === 'Escape') { box.hidden = true; e.preventDefault(); e.stopPropagation(); q.focus(); }
    } else if ((e.target.id === 'tend' || e.target.id === 'part' || e.target.id === 'disc') && (e.code === 'Enter' || e.code === 'NumpadEnter') && !e.ctrlKey) {
      e.preventDefault(); pay();   // من خانة المستلم/الخصم: Enter = خلّص
    }
  });
  reg.addEventListener('mousedown', (e) => {
    const r = e.target.closest('[data-c]'); if (!r) return;
    e.preventDefault(); customer = custRows[+r.dataset.c]; drawReg(); q.focus();
  });
  async function loadCustomerHints() {
    const box = reg.querySelector('#cref'); if (!box || !customer) return;
    try {
      const due = await api.select('v_refills_due', { customer_id: 'eq.' + customer.id, limit: 4 });
      if (due.length && customer && reg.querySelector('#cref') === box) render(box, h`<div style="margin-top:8px;font-size:12px;color:var(--on-c-2)">ميعاد علبته:</div><div class="chips" style="margin-top:4px">${due.map((d) => h`<button class="chip" data-refill="${d.item_id}" style="background:var(--gold-500);border-color:var(--gold-500);color:#241a06">+ ${d.name_ar || d.name_en}</button>`)}</div>`);
    } catch (e) {}
  }

  // ------------------------------------------------------------ الترحيل
  async function pay() {
    if (!cart.length || busy) return;
    const disc = Number(reg.querySelector('#disc')?.value || 0);
    const total = Math.max(0, subtotal() - disc);
    let rx = null;
    if (cart.some((l) => l.item.is_controlled)) { rx = await askRx(); if (!rx) return; }
    let payments;
    if (method === 'credit') {
      if (!customer) { toast('الآجل محتاج تختار العميل', 'bad'); reg.querySelector('#cq')?.focus(); return; }
      const part = Number(reg.querySelector('#part')?.value || 0);
      payments = part > 0 ? [{ method: 'cash', amount: Math.min(part, total) }] : [];
    } else payments = [{ method, amount: total }];
    const payload = {
      client_uuid: api.uuid(), shift_id: shift ? shift.id : null, customer_id: customer ? customer.id : null, discount: disc || 0,
      lines: cart.map((l) => (l.mode === 'pack' ? { item_id: l.item.id, packs: l.qty } : { item_id: l.item.id, units: l.qty })),
      payments, rx,
    };
    // السعر الفعلي بيتحسب في القاعدة (ممكن تشغيلة بسعر مختلف): نبعت المدفوع = الإجمالي الفعلي لو الدفع كامل
    busy = true; drawReg();
    const snapshot = { cart: cart.slice(), customer, method, tendered: Number(reg.querySelector('#tend')?.value || 0) };
    try {
      // لو الكمية جت من تشغيلتين بسعرين، الإجمالي الفعلي بيختلف شوية عن التقدير: نبعت تاني بالمبلغ اللي القاعدة حسبته
      // (المحاولة الأولى مااتسجلش منها حاجة، فنفس الـ client_uuid آمن)
      const r = await api.rpc('post_sale', { p: payload }).catch(async (e) => {
        if (method === 'credit') throw e;
        const over = /المدفوع \(([\d.]+)\) أكتر من الإجمالي \(([\d.]+)\)/.exec(e.message || '');
        const under = /فاضل ([\d.]+) ومفيش عميل/.exec(e.message || '');
        if (over) payload.payments = [{ method, amount: Number(over[2]) }];
        else if (under) payload.payments = [{ method, amount: Math.round((total + Number(under[1])) * 100) / 100 }];
        else throw e;
        return api.rpc('post_sale', { p: payload });
      });
      if (method !== 'credit' && Number(r.on_credit) > 0) toast(`السعر الفعلي أعلى: اتسجل ${money(r.on_credit)} ج على حساب العميل`, 'bad');
      busy = false;
      reset();
      lastSale = { r, snap: { customer: snapshot.customer ? { name: snapshot.customer.name } : null, method: snapshot.method, tendered: snapshot.tendered } };
      try { localStorage.setItem('asker.lastSale', JSON.stringify(lastSale)); } catch (er) {}
      receipt(r, snapshot);
      loadShift();
    } catch (e) {
      busy = false;
      if (e.status === 0) {
        api.outbox.push(payload); reset(); drawOutbox();
        toast('الشبكة واقعة: الفاتورة اتحفظت هنا وهتتبعت لوحدها أول ما ترجع', 'bad');
      } else { drawReg(); toast(e.message, 'bad'); beep(false); }
    }
  }
  function reset() { cart = []; customer = null; method = 'cash'; csel = -1; draw(); q.focus(); }

  function askRx() {
    return new Promise((resolve) => {
      const m = modal({ title: 'بيانات الروشتة (صنف جدول)', body: h`<form class="stack" id="rxf">
          <p class="muted" style="margin:0">بتتسجل في دفتر الأصناف المراقبة مع الفاتورة.</p>
          <div class="field"><label>اسم المريض</label><input class="input" id="rp" required autofocus></div>
          <div class="field"><label>اسم الدكتور</label><input class="input" id="rd" required></div>
          <div class="field"><label>رقم الروشتة (لو فيه)</label><input class="input" id="rn"></div></form>`,
        footer: h`<button class="btn quiet" data-close>رجوع</button><button class="btn" id="ok">كمّل</button>`, onClose: (v) => resolve(v || null) });
      const ok = () => {
        const p = $('#rp', m.el).value.trim(), d = $('#rd', m.el).value.trim();
        if (!p || !d) { toast('اسم المريض والدكتور لازم', 'bad'); return; }
        m.close({ patient: p, doctor: d, no: $('#rn', m.el).value.trim() || null });
      };
      $('#ok', m.el).addEventListener('click', ok);
      $('#rxf', m.el).addEventListener('submit', (e) => { e.preventDefault(); ok(); });
    });
  }

  let lastSale = null; try { lastSale = JSON.parse(localStorage.getItem('asker.lastSale')); } catch (e) {}
  async function receipt(r, snap) {
    let lines = [], head = null;
    try {
      [lines, head] = await Promise.all([
        api.select('sale_lines', { sale_id: 'eq.' + r.sale_id, select: 'qty_units,unit_price,line_total,items(name_ar,name_en,pack_parts,pack_name,unit_name)', order: 'id' }),
        api.one('sales', { id: 'eq.' + r.sale_id, select: 'no,at,subtotal,discount,total,paid,on_credit' }),
      ]);
    } catch (e) {}
    // نجمع سطور نفس الصنف (لو اتباع من أكتر من تشغيلة)
    const g = new Map();
    for (const l of lines) { const k = l.items.name_en; const x = g.get(k) || { ...l, qty_units: 0, line_total: 0 }; x.qty_units += Number(l.qty_units); x.line_total += Number(l.line_total); g.set(k, x); }
    const change = snap.method === 'cash' && snap.tendered > Number(r.total) ? snap.tendered - Number(r.total) : 0;
    const m = modal({ title: 'الفاتورة اتسجلت ✓', body: h`
      <div class="row" style="gap:16px;align-items:flex-start;flex-wrap:wrap;justify-content:center">
        <div class="receipt" id="rcpt" data-no="${r.no}">
          <div class="rc-head"><b>${(state.settings && state.settings.pharmacy_name) || 'صيدلية عسكر'}</b><div>فاتورة ${r.no}</div><div>${dateTime(head ? head.at : new Date())}</div>${snap.customer ? h`<div>العميل: ${snap.customer.name}</div>` : ''}</div>
          <table>${[...g.values()].map((l) => h`<tr><td>${l.items.name_ar || l.items.name_en}<br><span style="color:#555;font-size:11px">${qty(l.qty_units, l.items.pack_parts, l.items.pack_name, l.items.unit_name)}</span></td><td class="n">${money(l.line_total)}</td></tr>`)}</table>
          ${head && Number(head.discount) ? h`<div class="row between"><span>خصم</span><span>−${money(head.discount)}</span></div>` : ''}
          <div class="rc-tot row between"><span>الإجمالي</span><span>${money(r.total)} ج</span></div>
          ${Number(r.on_credit) ? h`<div class="row between"><span>مدفوع</span><span>${money(r.paid)}</span></div><div class="row between"><span>على الحساب</span><span>${money(r.on_credit)}</span></div>` : ''}
          <div class="rc-foot">ألف سلامة عليك · الدوا المفتوح مابيرجعش</div></div>
        <div style="min-width:220px;text-align:center;align-self:center">
          ${change ? h`<div class="muted">الباقي للعميل</div><div style="font-family:var(--f-display);font-size:48px;color:var(--accent-ink);line-height:1.1">${money(change)}</div>` : h`<div class="ico i-good" style="margin:0 auto 10px;width:64px;height:64px">${icon('check')}</div>`}
          <p class="muted">${r.repeat ? 'الفاتورة دي كانت متسجلة قبل كده (مااتسجلتش مرتين)' : 'المخزون والحسابات اتحدّثوا'}</p></div></div>`,
      footer: h`<button class="btn quiet" id="pr">${icon('printer')} اطبع <kbd>P</kbd></button><button class="btn" data-close autofocus>فاتورة جديدة <kbd style="background:transparent;color:var(--on-c-2);border-color:rgba(255,255,255,.3)">Enter</kbd></button>`,
      wide: true, onClose: () => q.focus() });
    $('#pr', m.el).addEventListener('click', () => window.print());
    m.el.addEventListener('keydown', (e) => { if (e.code === 'Enter' || e.code === 'NumpadEnter') { e.preventDefault(); m.close(); } else if (e.code === 'KeyP' || (e.ctrlKey && e.code === 'KeyP')) { e.preventDefault(); window.print(); } });
  }

  // ------------------------------------------------------------ تعليق الفاتورة (العميل بيدوّر على حاجة) وصندوق الصادر
  function park() {
    if (!cart.length) return toast('مفيش فاتورة تتعلق');
    const l = parked(); l.push({ id: Date.now(), at: new Date().toISOString(), cart, customer }); saveParked(l.slice(-6));
    reset(); drawPark(); toast('الفاتورة اتعلقت: ترجعلها من فوق');
  }
  function drawPark() {
    const l = parked();
    render($('#parkbar', el), h`${l.map((p) => h`<button class="btn quiet sm" data-park="${p.id}">${icon('pause')} معلّقة · ${p.cart.length} صنف · ${moneyR(p.cart.reduce((s, x) => s + lineTotal(x), 0))} ج</button>`)}<button class="btn ghost sm" id="park" data-hot="alt+p">${icon('pause')} علّق <kbd>Alt+P</kbd></button>`);
  }
  $('#parkbar', el).addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.id === 'park') return park();
    const id = +b.dataset.park, l = parked(), p = l.find((x) => x.id === id); if (!p) return;
    if (cart.length) { const cur = { id: Date.now(), at: new Date().toISOString(), cart, customer }; l.push(cur); }
    saveParked(l.filter((x) => x.id !== id)); cart = p.cart; customer = p.customer; draw(); drawPark(); q.focus();
  });
  function drawOutbox() {
    const l = api.outbox.all(), box = $('#outbox', el);
    if (!l.length) { box.innerHTML = ''; return; }
    const errs = l.filter((x) => x.error);
    render(box, h`<div class="outbox row between" style="margin-bottom:14px"><span>${icon('alert')} ${l.length} فاتورة مستنية الشبكة${errs.length ? h` · ${errs.length} القاعدة رفضتها: ${errs[0].error}` : ''}</span>
      <span class="row"><button class="btn sm gold" id="flush">ابعت دلوقتي</button>${errs.length ? h`<button class="btn sm quiet" id="drop">شيل المرفوضة</button>` : ''}</span></div>`);
    $('#flush', box).addEventListener('click', async () => { const r = await api.outbox.flush(); toast(`اتبعت ${r.sent} · فاضل ${r.left}`, r.left ? 'bad' : 'good'); drawOutbox(); loadShift(); });
    const d = $('#drop', box); if (d) d.addEventListener('click', async () => { if (await confirmBox('شيل الفواتير المرفوضة', 'الفواتير اللي القاعدة رفضتها هتتشال من الجهاز ده. متأكد؟', 'شيلها', true)) { api.outbox.save(api.outbox.all().filter((x) => !x.error)); drawOutbox(); } });
  }

  // ------------------------------------------------------------ الكيبورد
  const onKey = (e) => {
    if (document.querySelector('.modal') || document.querySelector('.kb-hints')) return;
    const c = combo(e), M = { F8: 'cash', F9: 'credit', F10: 'card', 'Shift+F8': 'wallet' };
    const stop = () => { e.preventDefault(); e.stopPropagation(); };
    if (c === 'F2') { stop(); csel = -1; draw(); q.focus(); q.select(); }
    else if (c === 'F5') { stop(); loadShift(); drawOutbox(); toast('اتحدّث ✓ (الفاتورة زي ما هي)'); }
    else if (M[c]) { stop(); method = M[c]; drawReg(); const t = reg.querySelector(method === 'cash' ? '#tend' : '#part'); if (!typing(document.activeElement) || document.activeElement === q) q.focus(); }
    else if (c === 'F6' || c === 'Alt+KeyP') { stop(); park(); }
    else if (c === 'Alt+Shift+KeyP') { stop(); const l = parked(); if (!l.length) return toast('مفيش فواتير معلّقة'); const p = l[l.length - 1]; saveParked(l.slice(0, -1)); if (cart.length) { const all = parked(); all.push({ id: Date.now(), at: new Date().toISOString(), cart, customer }); saveParked(all); } cart = p.cart; customer = p.customer; csel = -1; draw(); drawPark(); q.focus(); }
    else if (c === 'Alt+KeyL') { stop(); if (lastSale) receipt(lastSale.r, lastSale.snap); else toast('لسه مفيش فواتير من الجهاز ده'); }
    else if (c === 'Ctrl+Enter' || c === 'Ctrl+NumpadEnter') { stop(); pay(); }
  };
  document.addEventListener('keydown', onKey, true);

  draw(); drawPark(); drawOutbox(); loadShift();
  setTimeout(() => q.focus(), 50);
  return () => document.removeEventListener('keydown', onKey, true);
}
