// المشتريات: فواتير الشرا (مسودة ← مراجعة ← ترحيل)، واستلام الطلبية، وكله بالكيبورد.
// الترحيل في القاعدة (ph.post_purchase_invoice): تشغيلة لكل سطر بصلاحيتها وسعرها وتكلفتها بعد البونص، والمخزون بيزيد،
// وحساب المورد بيزيد، والسعر الرسمي بيزيد بس (القديم بيفضل بسعره).
import { h, render, $, $$, icon, money, moneyR, int, num, qty, dateShort, toast, debounce, skeleton, errorBox, empty, expiryPill } from '../ui.js';

export const keys = [
  { k: ['Alt+KeyA'], t: 'فاتورة شرا جديدة (من القايمة)' },
  { k: ['Slash'], t: 'خانة الصنف في الفاتورة' },
  { k: ['Enter'], t: 'ضيف الصنف ← الخانة اللي بعدها ← آخر السطر يرجع للصنف' },
  { k: ['Ctrl+KeyS'], t: 'احفظ مسودة' },
  { k: ['Ctrl+Enter'], t: 'رحّل الفاتورة (المخزون والمورد بيتحدّثوا)' },
  { k: ['Delete'], t: 'شيل السطر المختار' },
];

export default async function purchases(ctx) {
  const p0 = ctx.params[0];
  if (p0 === 'new') return editor(ctx, null, ctx.params[1] ? +ctx.params[1] : null);
  if (p0 && /^\d+$/.test(p0)) return invoicePage(ctx, +p0);
  return list(ctx);
}

// ---------------------------------------------------------------- القايمة
async function list({ el, api, go }) {
  let filter = 'all', text = '';
  render(el, h`
    <div class="head"><div><h1>المشتريات</h1><p>فواتير الشرا: المسودة بتتراجع، والترحيل بيزوّد المخزون وحساب المورد.</p></div>
      <div class="actions"><a class="btn" href="#/purchases/new" data-hot="alt+a">${icon('plus')} فاتورة شرا جديدة <kbd style="background:transparent;color:var(--on-c-2)">Alt+A</kbd></a></div></div>
    <section class="card" id="wait"></section>
    <section class="card" style="margin-top:16px">
      <div class="row wrap" style="gap:12px;margin-bottom:12px">
        <div class="search" style="flex:1;min-width:220px">${icon('search')}<input class="input" id="s" data-search placeholder="المورد أو رقم الفاتورة ( / )"></div>
        <div class="chips" id="f" data-tabs><button class="chip on" data-f="all">الكل</button><button class="chip" data-f="draft">مسودات</button><button class="chip" data-f="posted">مترحّلة</button></div></div>
      <div class="tbl-wrap"><table class="tbl"><thead><tr><th>الفاتورة</th><th>المورد</th><th>التاريخ</th><th class="n">أصناف</th><th class="n">الإجمالي</th><th class="n">الخصم الفعلي</th><th>الحالة</th></tr></thead><tbody id="rows"></tbody></table></div>
    </section>`);
  // طلبيات اتبعتت ولسه مااتستلمتش
  try {
    const ords = await api.select('purchase_orders', { status: 'eq.sent', select: 'id,no,sent_at,suppliers(name),purchase_order_lines(item_id)', order: 'sent_at.desc', limit: 8 });
    render($('#wait', el), h`<header><div><h2>طلبيات مستنية الاستلام</h2><span class="sub">لما الطلبية توصل: «استلمها» بتعمل فاتورة شرا بأصنافها وكمياتها</span></div></header>
      ${ords.length ? h`<div class="list">${ords.map((o) => h`<div class="li" data-row><span class="ico i-gold">${icon('truck')}</span>
        <div class="grow"><b>${o.suppliers ? o.suppliers.name : ''}</b><span class="muted" style="font-size:13px">${o.no} · ${o.purchase_order_lines.length} صنف · ${dateShort(o.sent_at)}</span></div>
        <a class="btn sm" data-key="r" title="استلم الطلبية دي" href="#/purchases/new/${o.id}">${icon('check')} استلمها <kbd style="background:transparent;color:var(--on-c-2)">R</kbd></a></div>`)}</div>` : empty('مفيش طلبيات مستنية')}`);
  } catch (e) { $('#wait', el).hidden = true; }
  const load = async () => {
    const p = { order: 'invoice_date.desc,created_at.desc', limit: 60 };
    if (filter !== 'all') p.status = 'eq.' + filter;
    const t = text.trim().replace(/[(),*]/g, ' ');
    if (t) p.or = `(supplier.ilike.*${t}*,no.ilike.*${t}*,supplier_doc_no.ilike.*${t}*,legacy_no.ilike.*${t}*)`;
    render($('#rows', el), h`<tr><td colspan="7">${skeleton(5)}</td></tr>`);
    let rows; try { rows = await api.select('v_purchase_invoices', p); } catch (e) { return render($('#rows', el), h`<tr><td colspan="7">${errorBox(e)}</td></tr>`); }
    render($('#rows', el), rows.length ? h`${rows.map((r) => h`<tr class="click" data-row data-id="${r.id}">
      <td><b class="ltr">${r.no || r.legacy_no || 'مسودة'}</b>${r.supplier_doc_no ? h`<div class="muted" style="font-size:12px">رقمهم ${r.supplier_doc_no}</div>` : ''}</td>
      <td>${r.supplier}</td><td>${dateShort(r.invoice_date)}</td><td class="n">${int(r.lines)}</td><td class="n"><b>${money(r.total)}</b></td>
      <td class="n">${r.real_discount_pct == null ? '—' : num(r.real_discount_pct) + '%'}</td>
      <td>${r.status === 'draft' ? h`<span class="pill p-warn">مسودة</span>` : h`<span class="pill p-good plain">مترحّلة</span>`}</td></tr>`)}` : h`<tr><td colspan="7">${empty('مفيش فواتير', 'Alt+A فاتورة جديدة')}</td></tr>`);
  };
  $('#rows', el).addEventListener('click', (e) => { const r = e.target.closest('tr[data-id]'); if (r) go('#/purchases/' + r.dataset.id); });
  $('#s', el).addEventListener('input', debounce((e) => { text = e.target.value; load(); }, 200));
  $('#f', el).addEventListener('click', (e) => { const c = e.target.closest('.chip'); if (!c) return; filter = c.dataset.f; $$('#f .chip', el).forEach((x) => x.classList.toggle('on', x === c)); load(); });
  load();
}

// ---------------------------------------------------------------- الفاتورة المترحّلة
async function invoicePage(ctx, id) {
  const { el, api } = ctx;
  render(el, h`<div class="card">${skeleton(8)}</div>`);
  let inv, lines;
  try {
    [inv, lines] = await Promise.all([
      api.one('v_purchase_invoices', { id: 'eq.' + id }),
      api.select('purchase_invoice_lines', { invoice_id: 'eq.' + id, select: 'id,item_id,packs,bonus_packs,public_price,cost_total,expiry,real_discount,items(name_ar,name_en,pack_parts)', order: 'id' }),
    ]);
  } catch (e) { return render(el, errorBox(e)); }
  if (!inv) return render(el, h`<div class="card">${empty('الفاتورة دي مش موجودة')}</div>`);
  if (inv.status === 'draft') return editor(ctx, id, null);
  render(el, h`
    <div class="head"><div><a href="#/purchases" data-back class="muted" style="text-decoration:none;font-size:14px">${icon('back', 'icon-sm')} المشتريات</a>
      <h1 style="margin-top:4px" class="ltr">${inv.no || inv.legacy_no}</h1><p>${inv.supplier}${inv.supplier_doc_no ? ' · رقمهم ' + inv.supplier_doc_no : ''} · ${dateShort(inv.invoice_date)}</p></div>
      <div class="actions"><a class="btn quiet" href="#/suppliers/${inv.supplier_id}" data-hot="alt+v">${icon('factory')} كشف حساب المورد <kbd>Alt+V</kbd></a></div></div>
    <section class="grid g4">
      <div class="card kpi hero"><div class="l">${icon('receipt')} الإجمالي</div><div class="v">${money(inv.total)}<small>ج</small></div><div class="f">${inv.paid_amount > 0 ? 'اتدفع ' + money(inv.paid_amount) : 'على الحساب'}</div></div>
      <div class="card kpi"><div class="l">${icon('sparkle')} الخصم الفعلي</div><div class="v">${inv.real_discount_pct == null ? '—' : num(inv.real_discount_pct)}<small>%</small></div><div class="f">بعد البونص</div></div>
      <div class="card kpi"><div class="l">${icon('box')} الأصناف</div><div class="v">${int(inv.lines)}</div><div class="f">${num(inv.packs)} علبة + ${num(inv.bonus)} بونص</div></div>
      <div class="card kpi"><div class="l">${icon('check')} الحالة</div><div class="v" style="font-size:22px">مترحّلة</div><div class="f">${inv.posted_at ? dateShort(inv.posted_at) : ''}</div></div></section>
    <section class="card" style="margin-top:16px"><div class="tbl-wrap"><table class="tbl"><thead><tr><th>الصنف</th><th class="n">الكمية</th><th class="n">بونص</th><th class="n">سعر الجمهور</th><th class="n">التكلفة</th><th class="n">الخصم الفعلي</th><th>الصلاحية</th></tr></thead><tbody>
      ${lines.map((l) => h`<tr data-row><td class="name"><a href="#/items/${l.item_id}" style="color:inherit"><b>${l.items.name_ar || l.items.name_en}</b></a><span class="en">${l.items.name_en}</span></td>
        <td class="n">${num(l.packs)}</td><td class="n">${num(l.bonus_packs)}</td><td class="n">${money(l.public_price)}</td><td class="n"><b>${money(l.cost_total)}</b></td>
        <td class="n">${num(Number(l.real_discount) * 100)}%</td><td>${expiryPill(l.expiry)}</td></tr>`)}</tbody></table></div></section>`);
}

// ---------------------------------------------------------------- إدخال فاتورة (مسودة جديدة أو موجودة، أو من طلبية)
async function editor({ el, api, go }, id, orderId) {
  render(el, h`<div class="card">${skeleton(8)}</div>`);
  let sups = [], accs = [], locs = [], inv = null, rows = [], order = null;
  try {
    [sups, accs, locs] = await Promise.all([
      api.select('suppliers', { active: 'eq.true', select: 'id,name', order: 'name' }),
      api.select('cash_accounts', { active: 'eq.true', select: 'id,name,kind', order: 'id' }).catch(() => []),
      api.select('locations', { select: 'id,name,is_default_sale', order: 'id' }),
    ]);
    if (id) {
      inv = await api.one('purchase_invoices', { id: 'eq.' + id });
      const ls = await api.select('purchase_invoice_lines', { invoice_id: 'eq.' + id, select: 'item_id,packs,bonus_packs,public_price,cost_total,expiry,items(id,name_ar,name_en,pack_parts,public_price)', order: 'id' });
      rows = ls.map((l) => ({ item: l.items, packs: +l.packs, bonus: +l.bonus_packs, price: +l.public_price, cost: +l.cost_total, disc: discOf(+l.public_price, +l.packs, +l.cost_total), exp: l.expiry ? l.expiry.slice(5, 7) + '/' + l.expiry.slice(2, 4) : '' }));
    } else if (orderId) {
      order = await api.one('purchase_orders', { id: 'eq.' + orderId, select: 'id,no,supplier_id,purchase_order_lines(item_id,packs,expected_pct,items(id,name_ar,name_en,pack_parts,public_price))' });
      rows = (order ? order.purchase_order_lines : []).map((l) => {
        const price = +l.items.public_price || 0, disc = l.expected_pct != null ? +l.expected_pct : 0;
        return { item: l.items, packs: +l.packs, bonus: 0, price, disc, cost: costOf(price, +l.packs, disc), exp: '' };
      });
    }
  } catch (e) { return render(el, errorBox(e)); }
  const defLoc = (locs.find((l) => l.is_default_sale) || locs[0] || {}).id;
  const head = {
    supplier_id: inv ? inv.supplier_id : order ? order.supplier_id : '',
    supplier_doc_no: inv ? inv.supplier_doc_no || '' : '',
    invoice_date: inv ? inv.invoice_date : new Date(Date.now() - new Date().getTimezoneOffset() * 6e4).toISOString().slice(0, 10),
    location_id: inv ? inv.location_id : defLoc,
    paid_amount: inv ? +inv.paid_amount : 0,
    paid_account_id: inv ? inv.paid_account_id : (accs.find((a) => a.kind === 'safe') || accs[0] || {}).id,
  };
  let busy = false, results = [], rsel = 0;

  render(el, h`
    <div class="head"><div><a href="#/purchases" data-back class="muted" style="text-decoration:none;font-size:14px">${icon('back', 'icon-sm')} المشتريات</a>
      <h1 style="margin-top:4px">${id ? 'مسودة فاتورة شرا' : order ? 'استلام ' + order.no : 'فاتورة شرا جديدة'}</h1>
      <p>المورد (↓) ← رقم فاتورتهم ← <kbd>Enter</kbd> ← الصنف ← <kbd>Enter</kbd> الكمية ← <kbd>Enter</kbd>… ← <kbd>Ctrl</kbd>+<kbd>Enter</kbd> رحّل. المسودة: <kbd>Ctrl</kbd>+<kbd>S</kbd>.</p></div>
      <div class="actions"><button class="btn quiet" id="save">${icon('check')} احفظ مسودة <kbd>Ctrl+S</kbd></button><button class="btn ok" id="post">${icon('box')} رحّل <kbd style="background:transparent;color:#fff">Ctrl+Enter</kbd></button></div></div>
    <section class="card"><div class="grid g4">
      <div class="field"><label for="sup">المورد</label><select class="input" id="sup" ${head.supplier_id ? '' : 'autofocus'}><option value="">— اختار —</option>${sups.map((s) => h`<option value="${s.id}" ${String(s.id) === String(head.supplier_id) ? 'selected' : ''}>${s.name}</option>`)}</select></div>
      <div class="field"><label for="doc">رقم فاتورة المورد</label><input class="input" id="doc" value="${head.supplier_doc_no}"></div>
      <div class="field"><label for="dt">التاريخ</label><input class="input" id="dt" type="date" value="${head.invoice_date}"></div>
      <div class="field"><label for="loc">المخزن</label><select class="input" id="loc">${locs.map((l) => h`<option value="${l.id}" ${l.id === head.location_id ? 'selected' : ''}>${l.name}</option>`)}</select></div>
      <div class="field"><label for="paid">اتدفع دلوقتي (اختياري)</label><input class="input num" id="paid" type="number" min="0" step="0.5" value="${head.paid_amount || ''}" placeholder="0 = على الحساب"></div>
      <div class="field"><label for="acc">اتدفع من</label><select class="input" id="acc">${accs.map((a) => h`<option value="${a.id}" ${a.id === head.paid_account_id ? 'selected' : ''}>${a.name}</option>`)}</select></div>
    </div></section>
    <section class="card" style="margin-top:16px">
      <div class="pos-search" style="margin-bottom:10px">${icon('barcode')}<input class="input" id="q" data-search placeholder="باركود أو اسم الصنف ← Enter ( / )" autocomplete="off" ${head.supplier_id ? 'autofocus' : ''}><div class="results" id="res" hidden></div></div>
      <div class="tbl-wrap"><table class="tbl" id="lines"><thead><tr><th>الصنف</th><th class="n">الكمية</th><th class="n">بونص</th><th class="n">سعر الجمهور</th><th class="n">الخصم %</th><th class="n">التكلفة</th><th>الصلاحية (شهر/سنة)</th><th></th></tr></thead><tbody id="lb"></tbody></table></div>
      <div class="row wrap" id="tot" style="gap:18px;margin-top:12px;justify-content:flex-end"></div>
    </section>`);
  const q = $('#q', el), res = $('#res', el), lb = $('#lb', el);

  function discOf(price, packs, cost) { const pub = price * packs; return pub ? Math.round((1 - cost / pub) * 10000) / 100 : 0; }
  function costOf(price, packs, disc) { return Math.round(price * packs * (1 - (disc || 0) / 100) * 100) / 100; }
  // «12/28» أو «12/2028» ← آخر يوم في الشهر
  function expiryDate(s) {
    const m = /^\s*(\d{1,2})\s*[\/\-.]\s*(\d{2}|\d{4})\s*$/.exec(s || ''); if (!m) return null;
    const mo = +m[1], y = m[2].length === 2 ? 2000 + +m[2] : +m[2]; if (mo < 1 || mo > 12) return null;
    const d = new Date(Date.UTC(y, mo, 0)); return d.toISOString().slice(0, 10);
  }
  function drawLines(focus) {
    render(lb, rows.length ? h`${rows.map((r, i) => h`<tr data-row data-i="${i}">
      <td class="name"><b>${r.item.name_ar || r.item.name_en}</b><span class="en">${r.item.name_en}</span></td>
      <td class="n"><input class="input num" data-f="packs" type="number" min="0" step="1" value="${r.packs}" style="width:70px;height:34px;text-align:center"></td>
      <td class="n"><input class="input num" data-f="bonus" type="number" min="0" step="1" value="${r.bonus}" style="width:64px;height:34px;text-align:center"></td>
      <td class="n"><input class="input num" data-f="price" type="number" min="0" step="0.5" value="${r.price}" style="width:86px;height:34px;text-align:center"></td>
      <td class="n"><input class="input num" data-f="disc" type="number" step="0.1" value="${r.disc}" style="width:70px;height:34px;text-align:center"></td>
      <td class="n"><input class="input num" data-f="cost" type="number" min="0" step="0.01" value="${r.cost}" style="width:100px;height:34px;text-align:center"></td>
      <td><input class="input ltr" data-f="exp" value="${r.exp}" placeholder="12/28" style="width:90px;height:34px;text-align:center"></td>
      <td><button class="btn sm quiet" data-key="Delete" data-del="${i}" title="شيل السطر">×</button></td></tr>`)}`
      : h`<tr><td colspan="8">${empty('الفاتورة فاضية', 'اكتب اسم الصنف أو امسح الباركود فوق ← Enter')}</td></tr>`);
    drawTot();
    if (focus != null) { const inp = lb.querySelector(`tr[data-i="${focus}"] input[data-f="packs"]`); if (inp) { inp.focus(); inp.select(); } }
  }
  function drawTot() {
    const cost = rows.reduce((s, r) => s + (+r.cost || 0), 0), pub = rows.reduce((s, r) => s + r.price * (r.packs + r.bonus), 0);
    const noExp = rows.filter((r) => !expiryDate(r.exp)).length;
    render($('#tot', el), h`<span class="muted">${int(rows.length)} صنف</span><span class="muted">بونص ${num(rows.reduce((s, r) => s + r.bonus, 0))}</span>
      <span>الخصم الفعلي <b>${pub ? num(Math.round((1 - cost / pub) * 10000) / 100) : 0}%</b></span>${noExp ? h`<span class="pill p-warn">${noExp} من غير صلاحية</span>` : ''}
      <span style="font-family:var(--f-display);font-size:22px">الإجمالي <b>${money(cost)}</b> ج</span>`);
  }
  lb.addEventListener('input', (e) => {
    const f = e.target.dataset.f; if (!f) return;
    const i = +e.target.closest('tr').dataset.i, r = rows[i], v = e.target.value;
    if (f === 'exp') { r.exp = v; drawTot(); return; }
    r[f] = +v || 0;
    if (f === 'cost') r.disc = discOf(r.price, r.packs, r.cost);
    else if (f !== 'bonus') { r.cost = costOf(r.price, r.packs, r.disc); const c = e.target.closest('tr').querySelector('[data-f="cost"]'); if (c) c.value = r.cost; }
    if (f === 'cost') { const d = e.target.closest('tr').querySelector('[data-f="disc"]'); if (d) d.value = r.disc; }
    drawTot();
  });
  // Enter جوه السطر: الخانة اللي بعدها، وآخر خانة ← خانة الصنف
  lb.addEventListener('keydown', (e) => {
    if (e.code !== 'Enter' && e.code !== 'NumpadEnter') return;
    if (e.ctrlKey) return;
    const inp = e.target.closest('input'); if (!inp) return;
    e.preventDefault();
    const all = [...e.target.closest('tr').querySelectorAll('input')], k = all.indexOf(inp);
    if (k < all.length - 1) { all[k + 1].focus(); all[k + 1].select && all[k + 1].select(); } else { q.focus(); }
  });
  lb.addEventListener('click', (e) => { const b = e.target.closest('[data-del]'); if (b) { rows.splice(+b.dataset.del, 1); drawLines(); q.focus(); } });

  // البحث عن الصنف (زي الكاشير)
  async function lookup(t) {
    t = t.trim(); if (t.length < 2 && !/^\d+$/.test(t)) { results = []; drawRes(); return []; }
    try { results = await api.rpc('pos_lookup', { q: t, max_rows: 8 }); } catch (e) { results = []; }
    rsel = 0; drawRes(); return results;
  }
  function drawRes() {
    if (!results.length || !q.value.trim()) { res.hidden = true; return; }
    res.hidden = false;
    render(res, h`${results.map((it, i) => h`<div class="res ${i === rsel ? 'on' : ''}" data-i="${i}"><div><b>${it.name_ar || it.name_en}</b><span class="en">${it.name_en}</span></div>
      <div class="stock">${Number(it.onhand_units) > 0 ? h`<span class="pill p-muted">عندنا ${qty(it.onhand_units, it.pack_parts)}</span>` : h`<span class="pill p-bad">صفر</span>`}</div><div class="price">${money(it.price_pack)}</div></div>`)}`);
  }
  async function addItem(it) {
    if (!it) return;
    const sid = +$('#sup', el).value || null;
    let disc = 0;
    if (sid) { try { const b = await api.one('v_item_buys', { item_id: 'eq.' + it.id, supplier_id: 'eq.' + sid }); if (b) disc = +b.discount_pct; } catch (e) {} }
    const price = +it.price_pack || 0;
    rows.push({ item: { id: it.id, name_ar: it.name_ar, name_en: it.name_en, pack_parts: it.pack_parts }, packs: 1, bonus: 0, price, disc, cost: costOf(price, 1, disc), exp: '' });
    q.value = ''; results = []; drawRes(); drawLines(rows.length - 1);
  }
  q.addEventListener('input', debounce(() => lookup(q.value), 120));
  q.addEventListener('keydown', async (e) => {
    if (e.code === 'ArrowDown' && !res.hidden) { e.preventDefault(); e.stopPropagation(); rsel = Math.min(results.length - 1, rsel + 1); drawRes(); }
    else if (e.code === 'ArrowUp' && !res.hidden) { e.preventDefault(); rsel = Math.max(0, rsel - 1); drawRes(); }
    else if ((e.code === 'Enter' || e.code === 'NumpadEnter') && !e.ctrlKey) {
      e.preventDefault(); if (!q.value.trim()) return;
      const isCode = /^\d{4,}$/.test(q.value.trim());
      let r = results; if (isCode || !r.length) r = await lookup(q.value);
      const pick = isCode ? (r.find((x) => x.exact) || (r.length === 1 ? r[0] : null)) : r[rsel];
      if (pick) addItem(pick); else toast('مالقيتش الصنف ده', 'bad');
    } else if (e.code === 'Escape' && q.value) { e.preventDefault(); e.stopPropagation(); q.value = ''; results = []; drawRes(); }
  });
  res.addEventListener('mousedown', (e) => { const r = e.target.closest('.res'); if (r) { e.preventDefault(); addItem(results[+r.dataset.i]); } });
  q.addEventListener('blur', () => setTimeout(() => { res.hidden = true; }, 150));
  $('#sup', el).addEventListener('change', () => { if ($('#sup', el).value) setTimeout(() => $('#doc', el).focus(), 0); });
  // Enter في بيانات الفاتورة ← خانة الصنف على طول
  ['#doc', '#dt', '#loc', '#paid', '#acc'].forEach((s) => $(s, el).addEventListener('keydown', (e) => {
    if ((e.code === 'Enter' || e.code === 'NumpadEnter') && !e.ctrlKey) { e.preventDefault(); q.focus(); }
  }));

  // الحفظ والترحيل
  async function save() {
    const sid = +$('#sup', el).value;
    if (!sid) { toast('اختار المورد الأول', 'bad'); $('#sup', el).focus(); return null; }
    if (!rows.length) { toast('الفاتورة فاضية', 'bad'); q.focus(); return null; }
    const bad = rows.findIndex((r) => !(r.packs > 0) || !(r.price > 0) || !(r.cost >= 0));
    if (bad >= 0) { toast(`السطر ${bad + 1}: الكمية والسعر لازم أكبر من صفر`, 'bad'); drawLines(bad); return null; }
    const wrongExp = rows.findIndex((r) => r.exp && !expiryDate(r.exp));
    if (wrongExp >= 0) { toast(`السطر ${wrongExp + 1}: الصلاحية تتكتب كده 12/28`, 'bad'); return null; }
    const paid = +$('#paid', el).value || 0;
    const hdr = { supplier_id: sid, supplier_doc_no: $('#doc', el).value.trim() || null, invoice_date: $('#dt', el).value, location_id: +$('#loc', el).value,
      paid_amount: paid, paid_account_id: paid > 0 ? +$('#acc', el).value : null, order_id: order ? order.id : inv ? inv.order_id : null };
    if (!id) { const [r] = await api.insert('purchase_invoices', hdr); id = r.id; history.replaceState(null, '', '#/purchases/' + id); }
    else { await api.update('purchase_invoices', { id: 'eq.' + id }, hdr); await api.remove('purchase_invoice_lines', { invoice_id: 'eq.' + id }); }
    await api.insert('purchase_invoice_lines', rows.map((r) => ({ invoice_id: id, item_id: r.item.id, packs: r.packs, bonus_packs: r.bonus, public_price: r.price, cost_total: r.cost, expiry: expiryDate(r.exp) })));
    return id;
  }
  async function doSave() { if (busy) return; busy = true; try { if (await save()) toast('المسودة اتحفظت ✓', 'good'); } catch (e) { toast(e.message, 'bad'); } busy = false; }
  async function doPost() {
    if (busy) return; busy = true;
    try {
      const pid = await save();
      if (pid) { const no = await api.rpc('post_purchase_invoice', { p_id: pid }); toast(`اترحّلت ${no} ✓ المخزون وحساب المورد اتحدّثوا`, 'good'); go('#/purchases/' + pid); }
    } catch (e) { toast(e.message, 'bad'); }
    busy = false;
  }
  $('#save', el).addEventListener('click', doSave);
  $('#post', el).addEventListener('click', doPost);
  const onKey = (e) => {
    if (document.querySelector('.modal')) return;
    if (e.ctrlKey && e.code === 'KeyS') { e.preventDefault(); e.stopPropagation(); doSave(); }
    else if (e.ctrlKey && (e.code === 'Enter' || e.code === 'NumpadEnter')) { e.preventDefault(); e.stopPropagation(); doPost(); }
  };
  document.addEventListener('keydown', onKey, true);
  drawLines();
  setTimeout(() => (head.supplier_id ? q : $('#sup', el)).focus(), 50);
  return () => document.removeEventListener('keydown', onKey, true);
}
