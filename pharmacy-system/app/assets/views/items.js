// الأصناف: القايمة بالرصيد والصلاحية، وصفحة الصنف (360°): التشغيلات، الحركة، البيع، الشرا من كل مورد، والبدايل.
import { h, render, $, $$, icon, money, moneyR, int, num, qty, dateShort, dateMY, dateTime, expiryPill, debounce, skeleton, errorBox, empty, inDays } from '../ui.js';
import { bars } from '../charts.js';

const DOC_AR = { sale: 'بيع', sale_return: 'مرتجع بيع', purchase: 'شرا', purchase_return: 'مرتجع شرا', transfer: 'تحويل', count: 'جرد', adjust: 'تسوية', opening: 'رصيد أول', import: 'نقل' };

export default async function items(ctx) {
  if (ctx.params[0]) return itemPage(ctx, +ctx.params[0]);
  const { el, api } = ctx;
  let filter = 'all', text = '', seq = 0;
  render(el, h`
    <div class="head"><div><h1>الأصناف والمخزون</h1><p id="cnt">…</p></div></div>
    <div class="card">
      <div class="row wrap" style="gap:12px;margin-bottom:12px">
        <div class="search" style="flex:1;min-width:240px">${icon('search')}<input class="input" id="s" placeholder="اسم الصنف بالعربي أو الإنجليزي، أو رقمه"></div>
        <div class="chips" id="f">
          <button class="chip on" data-f="all">الكل</button><button class="chip" data-f="out">ناقص</button><button class="chip" data-f="exp">صلاحية قريبة</button>
          <button class="chip" data-f="ctrl">جدول</button><button class="chip" data-f="fridge">تلاجة</button></div>
      </div>
      <div class="tbl-wrap"><table class="tbl"><thead><tr><th>الصنف</th><th>القسم</th><th class="n">الرصيد</th><th class="n">سعر العلبة</th><th>أقرب صلاحية</th></tr></thead><tbody id="rows"></tbody></table></div>
    </div>`);
  const load = async () => {
    const my = ++seq;
    const p = { select: 'id,name_en,name_ar,category,pack_parts,pack_name,unit_name,public_price,onhand_units,nearest_expiry,is_controlled,is_fridge,needs_rx', active: 'eq.true', order: 'name_en', limit: 200 };
    const t = text.trim().replace(/[(),*]/g, ' ');
    if (t) p.or = /^\d+$/.test(t) ? `(id.eq.${t},name_en.ilike.*${t}*)` : `(name_en.ilike.*${t}*,name_ar.ilike.*${t}*)`;
    if (filter === 'out') p.onhand_units = 'lte.0';
    if (filter === 'exp') { const d = new Date(Date.now() + 120 * 864e5).toISOString().slice(0, 10); p.nearest_expiry = 'lte.' + d; p.order = 'nearest_expiry'; }
    if (filter === 'ctrl') p.is_controlled = 'eq.true';
    if (filter === 'fridge') p.is_fridge = 'eq.true';
    render($('#rows', el), h`<tr><td colspan="5">${skeleton(5)}</td></tr>`);
    let rows;
    try { rows = await api.select('v_item_list', p); } catch (e) { return render($('#rows', el), h`<tr><td colspan="5">${errorBox(e)}</td></tr>`); }
    if (my !== seq) return;
    $('#cnt', el).textContent = rows.length >= 200 ? 'أول 200 صنف — دوّر بالاسم عشان تضيّق' : `${int(rows.length)} صنف`;
    render($('#rows', el), rows.length ? h`${rows.map((r) => {
      const on = Number(r.onhand_units) > 0;
      return h`<tr class="click" data-id="${r.id}"><td class="name"><b>${r.name_ar || r.name_en}</b><span class="en">${r.name_en} · #${r.id}</span></td>
        <td>${r.category || '—'} ${r.is_controlled ? h`<span class="pill p-bad plain">جدول</span>` : ''} ${r.is_fridge ? h`<span class="pill p-info plain">تلاجة</span>` : ''}</td>
        <td class="n">${on ? qty(r.onhand_units, r.pack_parts, r.pack_name, r.unit_name) : h`<span class="pill p-bad">ناقص</span>`}</td>
        <td class="n"><b>${money(r.public_price)}</b></td><td>${on ? expiryPill(r.nearest_expiry) : '—'}</td></tr>`;
    })}` : h`<tr><td colspan="5">${empty('مفيش أصناف بالشكل ده')}</td></tr>`);
  };
  $('#s', el).addEventListener('input', debounce((e) => { text = e.target.value; load(); }, 200));
  $('#f', el).addEventListener('click', (e) => { const c = e.target.closest('.chip'); if (!c) return; filter = c.dataset.f; $$('#f .chip', el).forEach((x) => x.classList.toggle('on', x === c)); load(); });
  $('#rows', el).addEventListener('click', (e) => { const r = e.target.closest('tr[data-id]'); if (r) ctx.go('#/items/' + r.dataset.id); });
  load();
  setTimeout(() => $('#s', el).focus(), 30);
}

async function itemPage({ el, api, go, can }, id) {
  render(el, h`<div class="card">${skeleton(8)}</div>`);
  let it, stock, card, buys, offers, alts, s30;
  try {
    [it, stock, card, buys, offers, alts, s30] = await Promise.all([
      api.one('v_item_list', { id: 'eq.' + id }),
      api.select('v_stock', { item_id: 'eq.' + id, qty_units: 'gt.0', order: 'expiry.asc.nullslast' }),
      api.select('v_item_card', { item_id: 'eq.' + id, order: 'at.desc', limit: 600 }),
      can(['owner', 'manager', 'pharmacist']) ? api.select('v_item_buys', { item_id: 'eq.' + id, order: 'discount_pct.desc' }).catch(() => []) : [],
      can(['owner', 'manager', 'pharmacist']) ? api.select('supplier_offers', { item_id: 'eq.' + id, select: 'offered_at,discount_pct,price,source,suppliers(name)', order: 'offered_at.desc', limit: 6 }).catch(() => []) : [],
      api.rpc('item_alternatives', { p_item: id }).catch(() => []),
      api.one('v_sales_30d', { item_id: 'eq.' + id }).catch(() => null),
    ]);
  } catch (e) { return render(el, errorBox(e)); }
  if (!it) return render(el, h`<div class="card">${empty('الصنف ده مش موجود')}</div>`);
  const daily = Number(s30 ? s30.units : 0) / 30;
  const cover = daily > 0 ? Number(it.onhand_units) / daily : null;
  const lastBuy = buys.slice().sort((a, b) => (a.invoice_date < b.invoice_date ? 1 : -1))[0];
  const best = buys[0];
  render(el, h`
    <div class="head"><div>
      <a href="#/items" class="muted" style="text-decoration:none;font-size:14px">${icon('back', 'icon-sm')} الأصناف</a>
      <h1 style="margin-top:4px">${it.name_ar || it.name_en}</h1>
      <p class="ltr" style="text-align:right">${it.name_en} · #${it.id}</p>
      <div class="row wrap" style="gap:6px;margin-top:8px">${it.category ? h`<span class="pill p-muted plain">${it.category}</span>` : ''}${it.is_controlled ? h`<span class="pill p-bad plain">جدول</span>` : ''}${it.needs_rx ? h`<span class="pill p-info plain">روشتة</span>` : ''}${it.is_fridge ? h`<span class="pill p-info plain">${icon('fridge', 'icon-sm')} تلاجة</span>` : ''}
        <span class="pill p-gold plain">${it.pack_name || 'علبة'} = ${it.pack_parts} ${it.unit_name}</span></div></div>
      <div class="actions"><a class="btn" href="#/pos">${icon('pos')} بيع</a></div></div>
    <section class="grid g4">
      <div class="card kpi hero"><div class="l">${icon('box')} الرصيد</div><div class="v">${qty(it.onhand_units, it.pack_parts, it.pack_name, it.unit_name)}</div><div class="f">${stock.length} تشغيلة · ${it.nearest_expiry ? 'أقرب صلاحية ' + dateMY(it.nearest_expiry) : ''}</div></div>
      <div class="card kpi"><div class="l">${icon('chart')} بيع آخر 30 يوم</div><div class="v">${qty(s30 ? s30.units : 0, it.pack_parts, it.pack_name, it.unit_name)}</div><div class="f">≈ ${num((daily * 30 / it.pack_parts) / 4.3)} ${it.pack_name || 'علبة'} في الأسبوع</div></div>
      <div class="card kpi"><div class="l">${icon('clock')} يكفّي</div><div class="v">${cover == null ? '—' : int(cover)}<small>${cover == null ? 'مفيش بيع' : 'يوم'}</small></div>
        <div class="f">${cover != null && cover < 7 ? h`<span class="pill p-bad">اطلبه</span>` : cover != null && cover > 180 ? h`<span class="pill p-warn">زيادة عن الحاجة</span>` : h`<span class="pill p-good">مظبوط</span>`}</div></div>
      <div class="card kpi"><div class="l">${icon('cash')} سعر العلبة</div><div class="v">${money(it.public_price)}<small>ج</small></div>
        <div class="f">${best ? h`أحسن خصم ${num(best.discount_pct)}% من ${best.supplier}` : 'مفيش شرا متسجل'}</div></div>
    </section>
    <section class="grid g-wide" style="margin-top:16px">
      <div class="card"><header><div><h2>البيع أسبوع بأسبوع</h2><span class="sub">آخر 12 أسبوع (بالعلبة)</span></div></header><div id="wk" style="height:230px"></div></div>
      <div class="card"><header><h2>التشغيلات</h2><span class="sub">الأقرب صلاحية بيتباع الأول</span></header>
        <div class="list">${stock.length ? stock.map((b) => h`<div class="li"><span class="ico ${b.counts_as_stock ? 'i-good' : 'i-info'}">${icon('box')}</span>
          <div class="grow"><b>${qty(b.qty_units, it.pack_parts, it.pack_name, it.unit_name)}</b><span class="muted" style="font-size:13px">${b.location} · بسعر ${money(b.public_price || it.public_price)}</span></div>${expiryPill(b.expiry)}</div>`) : empty('مفيش رصيد')}</div></div>
    </section>
    <section class="grid g2" style="margin-top:16px">
      <div class="card"><header><h2>اتشرى من مين وبكام خصم</h2><span class="sub">آخر شرا من كل مورد (الخصم الفعلي بعد البونص)</span></header>
        ${buys.length ? h`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>المورد</th><th class="n">الخصم</th><th class="n">الكمية</th><th>آخر مرة</th></tr></thead><tbody>
          ${buys.map((b, i) => h`<tr><td><b>${b.supplier}</b> ${i === 0 && buys.length > 1 ? h`<span class="pill p-good plain">الأحسن</span>` : ''}</td><td class="n"><b>${num(b.discount_pct)}%</b></td><td class="n">${num(b.packs)}${Number(b.bonus_packs) ? h` + ${num(b.bonus_packs)} بونص` : ''}</td><td>${dateShort(b.invoice_date)}</td></tr>`)}
          </tbody></table></div>` : empty('مفيش شرا متسجل')}
        ${offers.length ? h`<h3 style="font-size:14px;margin:16px 0 6px">عروض الموردين الأخيرة</h3><div class="chips">${offers.map((o) => h`<span class="pill p-gold plain">${o.suppliers ? o.suppliers.name : ''} ${o.discount_pct != null ? num(o.discount_pct) + '%' : money(o.price)} · ${dateShort(o.offered_at)}</span>`)}</div>` : ''}</div>
      <div class="card"><header><h2>البدايل الموجودة</h2><span class="sub">نفس المادة الفعالة والشكل</span></header>
        <div class="list">${alts.length ? alts.map((a) => h`<a class="li" href="#/items/${a.id}" style="text-decoration:none;color:inherit"><span class="ico i-crimson">${icon('swap')}</span><div class="grow"><b>${a.name_ar || a.name_en}</b><span class="en">${a.name_en}</span></div><div class="end"><b>${money(a.price_pack)}</b> ج<div class="muted" style="font-size:12px">${qty(a.onhand_units, a.pack_parts)}</div></div></a>`) : empty('مفيش بديل عليه رصيد')}</div></div>
    </section>
    <section class="card" style="margin-top:16px"><header><h2>كارت الصنف</h2><span class="sub">كل حركة، والرصيد بعدها</span></header>
      <div class="tbl-wrap"><table class="tbl"><thead><tr><th>الوقت</th><th>الحركة</th><th class="n">الكمية</th><th class="n">الرصيد بعدها</th></tr></thead><tbody>
      ${card.slice(0, 40).map((m) => h`<tr><td>${dateTime(m.at)}</td><td><span class="pill ${Number(m.qty_units) < 0 ? 'p-muted' : 'p-good'} plain">${DOC_AR[m.doc_type] || m.doc_type}</span></td>
        <td class="n" style="color:${Number(m.qty_units) < 0 ? 'var(--bad)' : 'var(--good)'}">${Number(m.qty_units) > 0 ? '+' : ''}${qty(m.qty_units, it.pack_parts, it.pack_name, it.unit_name)}</td><td class="n">${qty(m.balance_after, it.pack_parts, it.pack_name, it.unit_name)}</td></tr>`)}
      </tbody></table></div></section>`);
  // البيع بالأسبوع من كارت الصنف
  const weeks = Array(12).fill(0), now = Date.now();
  for (const m of card) {
    if (m.doc_type !== 'sale' && m.doc_type !== 'sale_return') continue;
    const w = Math.floor((now - new Date(m.business_day + 'T12:00:00').getTime()) / (7 * 864e5));
    if (w >= 0 && w < 12) weeks[w] += -Number(m.qty_units) / Number(it.pack_parts || 1);
  }
  // من الأقدم (يمين) للأحدث (شمال)
  const labels = weeks.map((_, i) => (i === 0 ? 'الأسبوع ده' : i === 1 ? 'اللي فات' : 'من ' + i + ' أسابيع')).reverse();
  const values = weeks.map((v) => Math.max(0, Math.round(v * 10) / 10)).reverse();
  return bars($('#wk', el), { labels, values, name: 'البيع', label: (i) => labels[i], fmt: (v) => num(v) + ' ' + (it.pack_name || 'علبة') });
}
