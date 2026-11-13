// التقارير: 7 مجموعات. كل رقم جاي من دالة في القاعدة (نفس الرقم في الموبايل والبوت)، وكل جدول بينزل Excel.
import { h, raw, render, $, $$, icon, money, moneyR, int, num, pct, qty, dateShort, dateMY, dateTime, ago, skeleton, errorBox, empty, copyText, waLink, modal, toDate } from '../ui.js';
import { barLine, bars } from '../charts.js';

const TABS = [
  ['sales', 'المبيعات والربح', 'chart'], ['stock', 'المخزون', 'box'], ['buy', 'المشتريات والموردين', 'factory'], ['cust', 'العملاء', 'users'],
  ['short', 'النواقص والطلبيات', 'truck'], ['money', 'الفلوس', 'wallet'], ['store', 'المتجر', 'pos'],
];
const PERIODS = [['today', 'النهارده'], ['7', '7 أيام'], ['30', '30 يوم'], ['month', 'الشهر ده'], ['lastmonth', 'الشهر اللي فات'], ['90', '90 يوم'], ['year', 'السنة دي']];
const DOW = ['الأحد', 'الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت'];
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const addDays = (s, n) => { const d = toDate(s); d.setDate(d.getDate() + n); return iso(d); };
const hrLbl = (hr) => (hr === 0 ? '12ص' : hr < 12 ? hr + 'ص' : hr === 12 ? '12م' : hr - 12 + 'م');
const delta = (cur, prev) => {
  if (!Number(prev)) return h`<span class="muted">—</span>`;
  const d = ((Number(cur) - Number(prev)) / Math.abs(Number(prev))) * 100;
  return h`<span class="delta ${d >= 0 ? 'up' : 'down'}">${d >= 0 ? '▲' : '▼'} ${Math.abs(d).toFixed(0)}%</span>`;
};

export default async function reports({ el, api, params, state }) {
  let tab = TABS.some((t) => t[0] === params[0]) ? params[0] : 'sales';
  let period = '30', today = state.dash ? state.dash.day : iso(new Date(Date.now() - 6 * 3600e3));
  try { today = await api.rpc('business_day', {}); } catch (e) {}
  let from, to;
  const setPeriod = (p) => {
    period = p; to = today;
    const t = toDate(today);
    if (p === 'today') from = today;
    else if (p === 'month') from = iso(new Date(t.getFullYear(), t.getMonth(), 1));
    else if (p === 'lastmonth') { from = iso(new Date(t.getFullYear(), t.getMonth() - 1, 1)); to = iso(new Date(t.getFullYear(), t.getMonth(), 0)); }
    else if (p === 'year') from = iso(new Date(t.getFullYear(), 0, 1));
    else from = addDays(today, -(+p - 1));
  };
  setPeriod(period);
  const exports = {};   // جداول للتنزيل
  let cleanups = [];

  render(el, h`
    <div class="head"><div><h1>التقارير</h1><p>كل حاجة الصيدلي بيحلم يعرفها… جاهزة. اضغط على أي جدول ونزّله Excel.</p></div>
      <div class="actions"><button class="btn gold" id="brief">${icon('sun')} ملخص الصبح</button></div></div>
    <div class="chips" id="tabs" style="margin-bottom:10px">${TABS.map(([k, l, ic]) => h`<button class="chip ${k === tab ? 'on' : ''}" data-t="${k}">${l}</button>`)}</div>
    <div class="card" style="padding:12px 16px;margin-bottom:16px"><div class="row wrap" style="gap:10px">
      <div class="chips" id="per">${PERIODS.map(([k, l]) => h`<button class="chip ${k === period ? 'on' : ''}" data-p="${k}">${l}</button>`)}</div>
      <div class="row" style="margin-inline-start:auto;gap:6px"><input type="date" class="input" id="df" style="width:150px;height:36px"><span class="muted">لـ</span><input type="date" class="input" id="dt" style="width:150px;height:36px"></div></div></div>
    <div id="body"></div>`);
  const body = $('#body', el);
  const syncDates = () => { $('#df', el).value = from; $('#dt', el).value = to; };
  syncDates();
  $('#tabs', el).addEventListener('click', (e) => { const c = e.target.closest('[data-t]'); if (!c) return; tab = c.dataset.t; history.replaceState(null, '', '#/reports/' + tab); $$('#tabs .chip', el).forEach((x) => x.classList.toggle('on', x === c)); show(); });
  $('#per', el).addEventListener('click', (e) => { const c = e.target.closest('[data-p]'); if (!c) return; setPeriod(c.dataset.p); $$('#per .chip', el).forEach((x) => x.classList.toggle('on', x === c)); syncDates(); show(); });
  const onDate = () => { const f = $('#df', el).value, t = $('#dt', el).value; if (f && t && f <= t) { from = f; to = t; period = ''; $$('#per .chip', el).forEach((x) => x.classList.remove('on')); show(); } };
  $('#df', el).addEventListener('change', onDate); $('#dt', el).addEventListener('change', onDate);
  $('#brief', el).addEventListener('click', brief);
  body.addEventListener('click', (e) => { const b = e.target.closest('[data-csv]'); if (b) csv(b.dataset.csv); });

  // ------------------------------------------------------------ أدوات
  const card = (title, sub, inner, opts = {}) => h`<div class="card" ${opts.span ? raw(`style="grid-column:1/-1"`) : ''}><header><div><h2>${title}</h2>${sub ? h`<span class="sub">${sub}</span>` : ''}</div>${opts.csv ? h`<button class="btn sm quiet" data-csv="${opts.csv}">${icon('download', 'icon-sm')} Excel</button>` : ''}${opts.end || ''}</header>${inner}</div>`;
  const table = (id, cols, rows, opts = {}) => {
    exports[id] = { cols, rows, name: opts.name || id };
    if (!rows.length) return empty(opts.empty || 'مفيش بيانات في الفترة دي');
    const shown = rows.slice(0, opts.limit || 15);
    return h`<div class="tbl-wrap"><table class="tbl"><thead><tr>${cols.map((c) => h`<th class="${c.n ? 'n' : ''}">${c.t}</th>`)}</tr></thead><tbody>
      ${shown.map((r) => h`<tr ${opts.href ? raw(`class="click" onclick="location.hash='${opts.href(r)}'"`) : ''}>${cols.map((c) => h`<td class="${c.n ? 'n' : ''}">${c.f ? c.f(r) : r[c.k]}</td>`)}</tr>`)}
      </tbody></table></div>${rows.length > shown.length ? h`<p class="muted" style="font-size:13px;margin:10px 0 0">ظاهر ${shown.length} من ${rows.length} — الكل في ملف Excel</p>` : ''}`;
  };
  const kpi = (label, ic, v, unit, foot, hero) => h`<div class="card kpi ${hero ? 'hero' : ''}"><div class="l">${icon(ic)} ${label}</div><div class="v">${v}${unit ? h`<small>${unit}</small>` : ''}</div><div class="f">${foot || ''}</div></div>`;
  const nm = (r) => h`<span class="name"><b>${r.name_ar || r.name_en}</b><span class="en">${r.name_en || ''}</span></span>`;
  const meter = (v, max, cls = '') => h`<div class="meter" style="min-width:90px"><i class="${cls}" style="width:${Math.max(2, Math.min(100, (Number(v) / Math.max(1e-9, Number(max))) * 100))}%"></i></div>`;
  function csv(id) {
    const x = exports[id]; if (!x) return;
    const plain = (v) => String(v ?? '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    const head = x.cols.map((c) => c.t);
    const lines = x.rows.map((r) => x.cols.map((c) => (c.x ? c.x(r) : c.f ? plain(c.f(r)) : r[c.k])));
    const out = [head, ...lines].map((l) => l.map((v) => `"${String(v ?? '').replace(/"/g, '""')}"`).join(',')).join('\r\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + out], { type: 'text/csv;charset=utf-8' }));
    a.download = `asker-${id}-${from}_${to}.csv`;   // اسم إنجليزي: بعض المتصفحات بتشيل الاسم العربي
    document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }
  const P = () => ({ p_from: from, p_to: to });

  async function show() {
    cleanups.forEach((c) => c && c()); cleanups = [];
    render(body, h`<div class="grid g4">${[1, 2, 3, 4].map(() => h`<div class="card kpi">${skeleton(3)}</div>`)}</div><div class="card" style="margin-top:16px">${skeleton(8)}</div>`);
    try { await ({ sales, stock, buy, cust, short, money: moneyTab, store })[tab](); }
    catch (e) { console.error(e); render(body, h`<div class="card">${errorBox(e)}</div>`); }
  }

  // ------------------------------------------------------------ 1) المبيعات والربح
  async function sales() {
    const n = (toDate(to) - toDate(from)) / 864e5 + 1;
    const [sum, daily, prevDaily, monthly, items, heat, staff, shifts] = await Promise.all([
      api.rpc('rep_sales_summary', P()),
      api.select('v_sales_daily', { business_day: `gte.${from}`, and: `(business_day.lte.${to})`, order: 'business_day' }),
      api.select('v_sales_daily', { business_day: `gte.${addDays(from, -n)}`, and: `(business_day.lte.${addDays(from, -1)})`, order: 'business_day' }),
      api.rpc('rep_sales_monthly', { p_months: 24 }),
      api.rpc('rep_item_profit', { ...P(), p_limit: 2000 }),
      api.rpc('rep_heatmap', P()),
      api.rpc('rep_by_staff', P()),
      api.rpc('rep_by_shift', P()),
    ]);
    const c = sum.cur, pv = sum.prev, ly = sum.ly;
    const margin = Number(c.net_sales) ? (Number(c.profit) / Number(c.net_sales)) * 100 : null;
    const avg = Number(c.invoices) ? Number(c.net_sales) / Number(c.invoices) : 0;
    const lowMargin = items.filter((r) => Number(r.sales) > 0).sort((a, b) => a.margin_pct - b.margin_pct);
    const loss = items.filter((r) => Number(r.profit) < 0);
    // الزحمة
    const order = [...Array(24).keys()].map((i) => (i + 6) % 24);
    const cell = {}; let hmax = 0; heat.forEach((r) => { cell[r.dow + ':' + r.hr] = r; hmax = Math.max(hmax, Number(r.avg_sales)); });
    let peak = heat.reduce((a, r) => (Number(r.avg_sales) > Number(a?.avg_sales || 0) ? r : a), null);
    const dayTot = [0, 1, 2, 3, 4, 5, 6].map((d) => heat.filter((r) => r.dow === d).reduce((s, r) => s + Number(r.avg_sales), 0));
    const bestDay = dayTot.indexOf(Math.max(...dayTot));
    const lvl = (v) => (hmax ? Math.ceil((Number(v) / hmax) * 5) : 0);
    render(body, h`
      <section class="grid g4">
        ${kpi('صافي المبيعات', 'cash', moneyR(c.net_sales), 'ج', h`${delta(c.net_sales, pv.net_sales)} عن الفترة اللي قبلها · ${delta(c.net_sales, ly.net_sales)} عن السنة اللي فاتت`, true)}
        ${kpi('الربح الإجمالي', 'sparkle', moneyR(c.profit), 'ج', h`<span class="pill p-good plain">هامش ${pct(margin, 1)}</span> ${delta(c.profit, pv.profit)}`)}
        ${kpi('الفواتير', 'receipt', int(c.invoices), '', h`متوسط الفاتورة ${moneyR(avg)} ج · ${delta(c.invoices, pv.invoices)}`)}
        ${kpi('المرتجع والآجل', 'swap', moneyR(c.returns), 'ج مرتجع', h`آجل ${moneyR(c.on_credit)} ج`)}
      </section>
      <section class="grid g2" style="margin-top:16px">
        ${card('البيع يوم بيوم', 'مقارنة بالفترة اللي قبلها بنفس الطول', h`<div id="ch1" style="height:260px"></div>`, { end: h`<div class="legend"><span><i style="background:var(--s1)"></i>الفترة دي</span><span class="l2"><i style="background:var(--s2)"></i>اللي قبلها</span></div>` })}
        ${card('شهر بشهر', 'كل شهر مقارنة بنفس الشهر السنة اللي فاتت', h`<div id="ch2" style="height:260px"></div>`, { end: h`<div class="legend"><span><i style="background:var(--s1)"></i>السنة دي</span><span class="l2"><i style="background:var(--s2)"></i>السنة اللي فاتت</span></div>` })}
      </section>
      <section class="card" style="margin-top:16px"><header><div><h2>ساعات وأيام الزحمة</h2><span class="sub">متوسط البيع في الساعة لكل يوم في الأسبوع${peak ? h` · الأزحم: <b>${DOW[peak.dow]} ${hrLbl(peak.hr)}</b> · أحسن يوم: <b>${DOW[bestDay]}</b>` : ''}</span></div>
        <div class="legend" style="align-items:center;gap:4px"><span class="muted" style="font-size:12px">هادي</span>${[1, 2, 3, 4, 5].map((l) => h`<i style="display:inline-block;width:16px;height:12px;border-radius:3px;background:color-mix(in srgb, var(--s1) ${l * 19}%, var(--card))"></i>`)}<span class="muted" style="font-size:12px">زحمة</span></div></header>
        <div class="tbl-wrap"><table style="border-collapse:separate;border-spacing:3px;width:100%;font-size:11px"><thead><tr><th></th>${order.map((hr) => h`<th style="font-weight:500;color:var(--muted)">${hr % 2 === 0 ? hrLbl(hr) : ''}</th>`)}</tr></thead><tbody>
        ${[6, 0, 1, 2, 3, 4, 5].map((d) => h`<tr><th style="text-align:start;font-weight:600;padding-inline-end:6px;white-space:nowrap">${DOW[d]}</th>${order.map((hr) => { const r = cell[d + ':' + hr]; const L = r ? lvl(r.avg_sales) : 0;
          return h`<td title="${DOW[d]} ${hrLbl(hr)}: ${r ? money(r.avg_sales) + ' ج · ' + num(r.avg_invoices) + ' فاتورة' : '—'}" style="height:26px;min-width:18px;border-radius:5px;background:${L ? `color-mix(in srgb, var(--s1) ${L * 19}%, var(--card))` : 'var(--line-2)'}"></td>`; })}</tr>`)}
        </tbody></table></div></section>
      <section class="grid g2" style="margin-top:16px">
        ${card('الأكتر ربحًا', 'بعد المرتجع وتكلفة كل تشغيلة', table('top_profit', [
          { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'اتباع', n: 1, f: (r) => qty(r.units, r.pack_parts), x: (r) => r.units },
          { t: 'المبيعات', n: 1, f: (r) => money(r.sales), x: (r) => r.sales }, { t: 'الربح', n: 1, f: (r) => h`<b>${money(r.profit)}</b>`, x: (r) => r.profit }, { t: 'الهامش', n: 1, f: (r) => pct(r.margin_pct, 1), x: (r) => r.margin_pct },
        ], items, { limit: 10, name: 'ربح-الأصناف', href: (r) => '#/items/' + r.item_id }), { csv: 'top_profit' })}
        ${card('أقل هامش', loss.length ? `${loss.length} صنف بيتباع بخسارة!` : 'مفيش صنف بيتباع بخسارة', table('low_margin', [
          { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'المبيعات', n: 1, f: (r) => money(r.sales), x: (r) => r.sales },
          { t: 'الربح', n: 1, f: (r) => h`<b style="color:${Number(r.profit) < 0 ? 'var(--bad)' : 'inherit'}">${money(r.profit)}</b>`, x: (r) => r.profit },
          { t: 'الهامش', n: 1, f: (r) => h`<span class="pill ${Number(r.margin_pct) < 10 ? 'p-bad' : Number(r.margin_pct) < 18 ? 'p-warn' : 'p-muted'} plain">${pct(r.margin_pct, 1)}</span>`, x: (r) => r.margin_pct },
        ], lowMargin, { limit: 10, name: 'أقل-هامش', href: (r) => '#/items/' + r.item_id }), { csv: 'low_margin' })}
      </section>
      <section class="grid g2" style="margin-top:16px">
        ${card('كل موظف', '', table('staff', [
          { t: 'الموظف', k: 'name' }, { t: 'الفواتير', n: 1, f: (r) => int(r.invoices), x: (r) => r.invoices }, { t: 'المبيعات', n: 1, f: (r) => h`<b>${money(r.sales)}</b>`, x: (r) => r.sales },
          { t: 'متوسط الفاتورة', n: 1, f: (r) => money(r.avg_basket), x: (r) => r.avg_basket }, { t: 'خصم إداه', n: 1, f: (r) => money(r.discount), x: (r) => r.discount }, { t: 'مرتجعات', n: 1, f: (r) => int(r.returns_count), x: (r) => r.returns_count },
        ], staff, { name: 'الموظفين' }), { csv: 'staff' })}
        ${card('كل وردية', 'المفروض في الدرج واللي اتعدّ', table('shifts', [
          { t: 'الوردية', f: (r) => h`<b>${r.opened_by || '—'}</b><div class="muted" style="font-size:12px">${r.account} · ${dateTime(r.opened_at)}</div>`, x: (r) => `${r.opened_by} ${r.opened_at}` },
          { t: 'الفواتير', n: 1, f: (r) => int(r.invoices), x: (r) => r.invoices }, { t: 'البيع', n: 1, f: (r) => money(r.sales), x: (r) => r.sales },
          { t: 'المفروض', n: 1, f: (r) => money(r.expected), x: (r) => r.expected },
          { t: 'الفرق', n: 1, f: (r) => (r.status === 'open' ? h`<span class="pill p-good">مفتوحة</span>` : Number(r.diff) === 0 ? h`<span class="pill p-good plain">مظبوط</span>` : h`<span class="pill ${Number(r.diff) < 0 ? 'p-bad' : 'p-warn'} plain">${money(r.diff)}</span>`), x: (r) => r.diff },
        ], shifts, { name: 'الورديات', empty: 'مفيش ورديات في الفترة دي' }), { csv: 'shifts' })}
      </section>`);
    // الرسوم
    const pvMap = prevDaily.map((r) => Number(r.net_sales));
    cleanups.push(barLine($('#ch1', body), { labels: daily.map((r) => dateShort(r.business_day)), bars: daily.map((r) => Number(r.net_sales)), line: daily.map((_, i) => (pvMap[i] == null ? null : pvMap[i])), barName: 'الفترة دي', lineName: 'اللي قبلها', label: (i) => dateShort(daily[i].business_day) }));
    const mm = Object.fromEntries(monthly.map((r) => [r.month.slice(0, 7), Number(r.net_sales)]));
    const last12 = []; const t = toDate(today);
    for (let i = 11; i >= 0; i--) { const d = new Date(t.getFullYear(), t.getMonth() - i, 1); last12.push(d); }
    const key = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    cleanups.push(barLine($('#ch2', body), { labels: last12.map((d) => new Intl.DateTimeFormat('ar-EG-u-nu-latn', { month: 'short' }).format(d)),
      bars: last12.map((d) => mm[key(d)] || 0), line: last12.map((d) => { const k = key(new Date(d.getFullYear() - 1, d.getMonth(), 1)); return mm[k] == null ? null : mm[k]; }),
      barName: 'السنة دي', lineName: 'السنة اللي فاتت', label: (i) => dateMY(last12[i]) }));
  }

  // ------------------------------------------------------------ 2) المخزون
  async function stock() {
    const [val, dead, run, months, risk] = await Promise.all([
      api.rpc('rep_stock_value'), api.rpc('rep_dead_stock', { p_days: 90 }), api.rpc('rep_runout', { p_days: 14 }), api.rpc('rep_expiry_months', { p_months: 12 }),
      api.select('v_expiry_risk', { select: 'at_risk_value' }),
    ]);
    const cost = val.reduce((s, r) => s + Number(r.cost_value), 0), sale = val.reduce((s, r) => s + Number(r.sale_value), 0);
    const deadV = dead.reduce((s, r) => s + Number(r.cost_value || 0), 0);
    const riskV = risk.reduce((s, r) => s + Number(r.at_risk_value), 0);
    const expired = months.find((m) => m.month == null);
    const fut = months.filter((m) => m.month != null);
    render(body, h`
      <section class="grid g4">
        ${kpi('قيمة المخزون (تكلفة)', 'box', moneyR(cost), 'ج', h`بسعر البيع ${moneyR(sale)} ج · ربح محتمل ${moneyR(sale - cost)}`, true)}
        ${kpi('فلوس نايمة (راكد)', 'pause', moneyR(deadV), 'ج', `${dead.length} صنف مااتباعش من 3 شهور`)}
        ${kpi('هيخلص من الرف', 'clock', int(run.length), 'صنف', 'خلال أسبوعين بسرعة البيع الحالية')}
        ${kpi('صلاحية في خطر', 'hourglass', moneyR(riskV), 'ج', expired ? h`<span class="pill p-bad">${moneyR(expired.cost_value)} ج خلصت فعلًا</span>` : 'مفيش حاجة خلصت')}
      </section>
      <section class="grid g2" style="margin-top:16px">
        ${card('الراكد: فلوس نايمة على الرف', 'عليه رصيد ومااتباعش من 90 يوم أو أكتر — فكّر ترجّعه أو تعمل عليه عرض', table('dead', [
          { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'الرصيد', n: 1, f: (r) => qty(r.onhand_units, r.pack_parts), x: (r) => r.onhand_units },
          { t: 'القيمة', n: 1, f: (r) => h`<b>${money(r.cost_value)}</b>`, x: (r) => r.cost_value },
          { t: 'آخر بيع', f: (r) => (r.last_sold ? `من ${r.days_since} يوم` : h`<span class="pill p-bad plain">مااتباعش خالص</span>`), x: (r) => r.last_sold || '' },
        ], dead, { name: 'الراكد', empty: 'مفيش راكد. كل اللي في المخزن بيتحرك', href: (r) => '#/items/' + r.item_id }), { csv: 'dead' })}
        ${card('هيخلص من الرف خلال أيام', 'بسرعة بيع آخر 30 يوم', table('runout', [
          { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'الرصيد', n: 1, f: (r) => qty(r.onhand_units, r.pack_parts), x: (r) => r.onhand_units },
          { t: 'بيع اليوم', n: 1, f: (r) => num(r.daily_rate), x: (r) => r.daily_rate },
          { t: 'يكفّي', n: 1, f: (r) => h`<span class="pill ${Number(r.days_left) <= 3 ? 'p-bad' : Number(r.days_left) <= 7 ? 'p-warn' : 'p-muted'}">${num(r.days_left)} يوم</span>`, x: (r) => r.days_left },
          { t: '', f: (r) => (r.ordered_today ? h`<span class="pill p-good plain">اتطلب</span>` : ''), x: (r) => (r.ordered_today ? 'اتطلب' : '') },
        ], run, { name: 'هيخلص', href: (r) => '#/items/' + r.item_id }), { csv: 'runout' })}
      </section>
      <section class="grid g-wide" style="margin-top:16px">
        ${card('قيمة اللي بيخلص كل شهر', 'بالتكلفة، للـ 12 شهر الجايين', h`<div id="ch3" style="height:260px"></div>`)}
        ${card('المخزون في كل مكان', '', table('locs', [
          { t: 'المكان', f: (r) => h`<b>${r.location}</b>${r.counts_as_stock ? '' : h` <span class="pill p-info plain">انتظار</span>`}`, x: (r) => r.location },
          { t: 'أصناف', n: 1, f: (r) => int(r.items), x: (r) => r.items }, { t: 'بالتكلفة', n: 1, f: (r) => money(r.cost_value), x: (r) => r.cost_value }, { t: 'بسعر البيع', n: 1, f: (r) => money(r.sale_value), x: (r) => r.sale_value },
        ], val, { name: 'قيمة-المخزون' }), { csv: 'locs' })}
      </section>`);
    cleanups.push(bars($('#ch3', body), { labels: fut.map((m) => new Intl.DateTimeFormat('ar-EG-u-nu-latn', { month: 'short' }).format(toDate(m.month))), values: fut.map((m) => Number(m.cost_value)), name: 'بيخلص', label: (i) => dateMY(fut[i].month) }));
  }

  // ------------------------------------------------------------ 3) المشتريات والموردين
  async function buy() {
    const [cmp, sup, prices] = await Promise.all([api.rpc('rep_discount_compare', { p_days: 180 }), api.rpc('rep_supplier_month', P()), api.rpc('rep_price_changes', { p_from: addDays(today, -90), p_to: today })]);
    const missed = cmp.reduce((s, r) => s + Number(r.missed_value || 0), 0);
    const tot = sup.reduce((s, r) => s + Number(r.total), 0);
    const best = sup.filter((r) => r.real_discount_pct != null).sort((a, b) => b.real_discount_pct - a.real_discount_pct)[0];
    render(body, h`
      <section class="grid g3">
        ${kpi('مشتريات الفترة', 'receipt', moneyR(tot), 'ج', `${int(sup.reduce((s, r) => s + Number(r.invoices), 0))} فاتورة من ${sup.filter((r) => Number(r.invoices)).length} مورد`, true)}
        ${kpi('أعلى خصم فعلي', 'sparkle', best ? num(best.real_discount_pct) : '—', '%', best ? best.name : '')}
        ${kpi('كان ممكن توفّر', 'wallet', moneyR(missed), 'ج', 'لو آخر شرا لكل صنف كان من أحسن مورد ليه')}
      </section>
      <section class="card" style="margin-top:16px"><header><div><h2>مقارنة خصومات الموردين على نفس الصنف</h2><span class="sub">آخر شرا من كل مورد في 6 شهور (الخصم الفعلي بعد البونص)</span></div><button class="btn sm quiet" data-csv="cmp">${icon('download', 'icon-sm')} Excel</button></header>
        ${table('cmp', [
          { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'موردين', n: 1, f: (r) => int(r.suppliers), x: (r) => r.suppliers },
          { t: 'الأحسن', f: (r) => h`<b>${r.best_supplier}</b> <span class="pill p-good plain">${num(r.best_pct)}%</span>`, x: (r) => `${r.best_supplier} ${r.best_pct}%` },
          { t: 'الأوحش', f: (r) => h`${r.worst_supplier} <span class="pill p-muted plain">${num(r.worst_pct)}%</span>`, x: (r) => `${r.worst_supplier} ${r.worst_pct}%` },
          { t: 'الفرق', n: 1, f: (r) => h`<b>${num(r.spread)}%</b>`, x: (r) => r.spread },
          { t: 'آخر مرة من', f: (r) => h`${r.last_supplier} ${r.last_supplier === r.best_supplier ? h`<span class="pill p-good plain">✓</span>` : ''}`, x: (r) => r.last_supplier },
          { t: 'ضاع', n: 1, f: (r) => (Number(r.missed_value) ? h`<b style="color:var(--bad)">${money(r.missed_value)}</b>` : '—'), x: (r) => r.missed_value },
        ], cmp, { limit: 20, name: 'مقارنة-الخصومات', href: (r) => '#/items/' + r.item_id })}</section>
      <section class="grid g2" style="margin-top:16px">
        ${card('فواتير كل مورد في الفترة', '', table('supm', [
          { t: 'المورد', f: (r) => h`<b>${r.name}</b>`, x: (r) => r.name }, { t: 'فواتير', n: 1, f: (r) => int(r.invoices), x: (r) => r.invoices },
          { t: 'الإجمالي', n: 1, f: (r) => h`<b>${money(r.total)}</b>`, x: (r) => r.total }, { t: 'الخصم الفعلي', n: 1, f: (r) => (r.real_discount_pct == null ? '—' : num(r.real_discount_pct) + '%'), x: (r) => r.real_discount_pct },
          { t: 'بونص', n: 1, f: (r) => num(r.bonus_packs), x: (r) => r.bonus_packs }, { t: 'اتدفع', n: 1, f: (r) => money(r.paid), x: (r) => r.paid }, { t: 'علينا', n: 1, f: (r) => money(r.balance), x: (r) => r.balance },
        ], sup, { name: 'فواتير-الموردين', href: (r) => '#/suppliers/' + r.supplier_id }), { csv: 'supm' })}
        ${card('أصناف سعرها اتغير', 'آخر 90 يوم، وأثره على اللي في المخزن', table('prices', [
          { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'من', n: 1, f: (r) => money(r.old_price), x: (r) => r.old_price }, { t: 'لـ', n: 1, f: (r) => h`<b>${money(r.new_price)}</b>`, x: (r) => r.new_price },
          { t: 'التغيير', n: 1, f: (r) => h`<span class="delta ${Number(r.change_pct) >= 0 ? 'up' : 'down'}">${Number(r.change_pct) >= 0 ? '▲' : '▼'} ${Math.abs(r.change_pct)}%</span>`, x: (r) => r.change_pct },
          { t: 'إمتى', f: (r) => dateShort(r.changed_at), x: (r) => r.changed_at }, { t: 'أثره على المخزون', n: 1, f: (r) => money(r.stock_effect), x: (r) => r.stock_effect },
        ], prices, { name: 'تغيير-الأسعار', empty: 'مفيش أسعار اتغيرت', href: (r) => '#/items/' + r.item_id }), { csv: 'prices' })}
      </section>`);
  }

  // ------------------------------------------------------------ 4) العملاء
  async function cust() {
    const [aging, top, lapsed, refills] = await Promise.all([api.rpc('rep_dues_aging'), api.rpc('rep_top_customers', { ...P(), p_limit: 100 }), api.rpc('rep_lapsed_customers', { p_quiet: 45 }), api.select('v_refills_due', { order: 'days_late.desc' })]);
    const b = ['b_0_30', 'b_31_60', 'b_61_90', 'b_90p'].map((k) => aging.reduce((s, r) => s + Number(r[k]), 0));
    const tot = b.reduce((s, v) => s + v, 0);
    const miss = (r) => `أهلًا ${r.name.split(' ').slice(0, 2).join(' ')}، معاك صيدلية عسكر 🌿 وحشتنا! لو محتاج أي حاجة إحنا موجودين، والتوصيل للبيت ببلاش.`;
    render(body, h`
      <section class="grid g4">
        ${kpi('على العملاء', 'wallet', moneyR(tot), 'ج', `${aging.length} عميل · ${aging.filter((r) => r.over_limit).length} عدّوا الحد`, true)}
        ${kpi('أقل من شهر', 'clock', moneyR(b[0]), 'ج', h`${meter(b[0], tot)}`)}
        ${kpi('من شهر لـ 3', 'alert', moneyR(b[1] + b[2]), 'ج', h`${meter(b[1] + b[2], tot, 'warn')}`)}
        ${kpi('أكتر من 3 شهور', 'alert', moneyR(b[3]), 'ج', h`${meter(b[3], tot, 'bad')}`)}
      </section>
      <section class="card" style="margin-top:16px"><header><div><h2>المديونيات وبقالها قد إيه</h2><span class="sub">الأقدم بيتسدد الأول</span></div><button class="btn sm quiet" data-csv="aging">${icon('download', 'icon-sm')} Excel</button></header>
        ${table('aging', [
          { t: 'العميل', f: (r) => h`<b>${r.name}</b><div class="muted ltr" style="font-size:12px;text-align:right">${r.phone || ''}</div>`, x: (r) => r.name },
          { t: 'عليه', n: 1, f: (r) => h`<b>${money(r.balance)}</b>`, x: (r) => r.balance },
          { t: 'أقدم دين', f: (r) => (r.age_days == null ? '—' : h`<span class="pill ${r.age_days > 90 ? 'p-bad' : r.age_days > 30 ? 'p-warn' : 'p-good'}">${r.age_days} يوم</span>`), x: (r) => r.age_days },
          { t: '< شهر', n: 1, f: (r) => money(r.b_0_30), x: (r) => r.b_0_30 }, { t: '1–2 شهر', n: 1, f: (r) => money(r.b_31_60), x: (r) => r.b_31_60 },
          { t: '2–3 شهور', n: 1, f: (r) => money(r.b_61_90), x: (r) => r.b_61_90 }, { t: '> 3 شهور', n: 1, f: (r) => money(r.b_90p), x: (r) => r.b_90p },
          { t: 'آخر دفعة', f: (r) => (r.last_payment ? ago(r.last_payment) : '—'), x: (r) => r.last_payment || '' },
        ], aging, { limit: 20, name: 'مديونيات-العملاء', href: (r) => '#/customers/' + r.customer_id })}</section>
      <section class="grid g2" style="margin-top:16px">
        ${card('أحسن العملاء في الفترة', '', table('topc', [
          { t: 'العميل', f: (r) => h`<b>${r.name}</b>`, x: (r) => r.name }, { t: 'زيارات', n: 1, f: (r) => int(r.visits), x: (r) => r.visits },
          { t: 'اشترى بـ', n: 1, f: (r) => h`<b>${money(r.sales)}</b>`, x: (r) => r.sales }, { t: 'ربح', n: 1, f: (r) => money(r.profit), x: (r) => r.profit }, { t: 'آخر مرة', f: (r) => dateShort(r.last_visit), x: (r) => r.last_visit },
        ], top, { limit: 12, name: 'أحسن-العملاء', href: (r) => '#/customers/' + r.customer_id }), { csv: 'topc' })}
        ${card('عملاء بطّلوا ييجوا', 'كانوا بييجوا بانتظام، ومن 45 يوم مفيش — ابعتلهم «وحشتنا»', lapsed.length ? h`<div class="list">${lapsed.slice(0, 12).map((r) => h`<div class="li"><span class="ico i-gold">${icon('user')}</span>
            <div class="grow"><a href="#/customers/${r.customer_id}" style="color:inherit;text-decoration:none"><b>${r.name}</b></a><span class="muted" style="font-size:13px">${int(r.visits)} زيارة · ${moneyR(r.spent)} ج · كان بييجي كل ${num(r.avg_gap_days)} يوم</span></div>
            <span class="pill p-warn">غايب ${r.days_away} يوم</span><a class="btn sm ghost" target="_blank" rel="noopener" href="${waLink(r.phone, miss(r))}">${icon('whatsapp')}</a></div>`)}</div>` : empty('كل العملاء المنتظمين لسه بييجوا'))}
      </section>
      ${card('عملاء الأمراض المزمنة: ميعاد علبتهم قرّب', h`<a href="#/customers">افتح شاشة العملاء عشان تفكّرهم ←</a>`, table('refills', [
        { t: 'العميل', k: 'customer' }, { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'كل', n: 1, f: (r) => r.every_days + ' يوم', x: (r) => r.every_days },
        { t: 'الميعاد', f: (r) => h`<span class="pill ${r.days_late > 0 ? 'p-bad' : 'p-warn'}">${r.days_late > 0 ? 'متأخر ' + r.days_late + ' يوم' : dateShort(r.due_on)}</span>`, x: (r) => r.due_on },
      ], refills, { name: 'مواعيد-الصرف', empty: 'مفيش مواعيد قريبة' }), { csv: 'refills' })}`);
    body.lastElementChild.style.marginTop = '16px';
  }

  // ------------------------------------------------------------ 5) النواقص والطلبيات
  async function short() {
    const [adv, fill, late] = await Promise.all([api.select('v_order_advice', { order: 'sold_30d_units.desc' }), api.rpc('rep_order_fill', P()), api.rpc('rep_late_orders', { p_hours: 24 })]);
    const lines = fill.reduce((s, r) => s + Number(r.lines), 0), got = fill.reduce((s, r) => s + Number(r.lines_received), 0);
    const real = adv.filter((r) => Number(r.sold_30d_units) > 0);
    render(body, h`
      <section class="grid g3">
        ${kpi('ناقص بجد', 'truck', int(real.length), 'صنف', `بيتباع ورصيده تحت الحد · ${adv.filter((r) => r.ordered_today_from).length} اتطلب النهارده`, true)}
        ${kpi('نسبة وصول الطلبية', 'check', lines ? pct((got / lines) * 100) : '—', '', `${int(got)} من ${int(lines)} صنف اتطلب وصل في يومين`)}
        ${kpi('طلبيات متأخرة', 'alert', int(late.length), 'صنف', 'اتطلب من أكتر من 24 ساعة وماوصلش')}
      </section>
      <section class="card" style="margin-top:16px"><header><div><h2>الناقص بجد</h2><span class="sub">بيتباع في آخر 30 يوم ورصيده تحت الحد الأدنى — مترتب بسرعة البيع</span></div><div class="row"><a class="btn sm" href="#/orders">${icon('truck')} جهّز الطلبيات</a><button class="btn sm quiet" data-csv="short">${icon('download', 'icon-sm')} Excel</button></div></header>
        ${table('short', [
          { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'عندنا', n: 1, f: (r) => (Number(r.onhand_units) > 0 ? qty(r.onhand_units, r.pack_parts) : h`<span class="pill p-bad">صفر</span>`), x: (r) => r.onhand_units },
          { t: 'اتباع 30 يوم', n: 1, f: (r) => qty(r.sold_30d_units, r.pack_parts), x: (r) => r.sold_30d_units }, { t: 'نطلب', n: 1, f: (r) => h`<b>${num(r.order_packs)}</b>`, x: (r) => r.order_packs },
          { t: 'أحسن مورد', f: (r) => (r.best_supplier ? h`${r.best_supplier} <span class="pill p-good plain">${num(r.best_pct)}%</span>` : '—'), x: (r) => r.best_supplier || '' },
          { t: '', f: (r) => (r.ordered_today_from ? h`<span class="pill p-good plain">اتطلب</span>` : ''), x: (r) => r.ordered_today_from || '' },
        ], real, { limit: 20, name: 'النواقص', href: (r) => '#/items/' + r.item_id })}</section>
      <section class="grid g2" style="margin-top:16px">
        ${card('نسبة وصول الطلبية الليلية لكل مورد', 'الصنف وصل لو جه في فاتورة من نفس المورد خلال يومين', table('fill', [
          { t: 'المورد', f: (r) => h`<b>${r.name}</b>`, x: (r) => r.name }, { t: 'طلبيات', n: 1, f: (r) => int(r.orders), x: (r) => r.orders },
          { t: 'وصل', f: (r) => h`<div class="row" style="gap:8px">${meter(r.fill_pct, 100, Number(r.fill_pct) < 70 ? 'bad' : Number(r.fill_pct) < 85 ? 'warn' : '')}<b>${pct(r.fill_pct)}</b></div>`, x: (r) => r.fill_pct },
          { t: 'أصناف', n: 1, f: (r) => `${int(r.lines_received)}/${int(r.lines)}`, x: (r) => r.lines }, { t: 'بياخد', n: 1, f: (r) => (r.avg_days == null ? '—' : num(r.avg_days) + ' يوم'), x: (r) => r.avg_days },
        ], fill, { name: 'وصول-الطلبيات', empty: 'مفيش طلبيات في الفترة دي' }), { csv: 'fill' })}
        ${card('الطلبيات المتأخرة', 'آخر أسبوع', table('late', [
          { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'المورد', k: 'supplier' }, { t: 'الكمية', n: 1, f: (r) => num(r.packs), x: (r) => r.packs },
          { t: 'مستني', n: 1, f: (r) => h`<span class="pill ${r.hours_waiting > 48 ? 'p-bad' : 'p-warn'}">${r.hours_waiting > 48 ? Math.round(r.hours_waiting / 24) + ' يوم' : r.hours_waiting + ' ساعة'}</span>`, x: (r) => r.hours_waiting },
        ], late, { name: 'طلبيات-متأخرة', empty: 'كل اللي اتطلب وصل' }), { csv: 'late' })}
      </section>`);
  }

  // ------------------------------------------------------------ 6) الفلوس
  async function moneyTab() {
    const [cash, exp, pnl, sum] = await Promise.all([api.rpc('rep_cash_flow', P()), api.rpc('rep_expenses', P()), api.rpc('rep_pnl_monthly', { p_months: 12 }), api.rpc('rep_sales_summary', P())]);
    const ex = exp.reduce((s, r) => s + Number(r.total), 0), gp = Number(sum.cur.profit), net = gp - ex;
    const TYPE_AR = { sale: 'بيع', sale_return: 'مرتجع', payment: 'دفعات', expense: 'مصروفات', purchase: 'شرا', shift: 'فرق ورديات' };
    render(body, h`
      <section class="grid g4">
        ${kpi('صافي الربح', 'sparkle', moneyR(net), 'ج', `الربح الإجمالي − المصروفات · هامش ${pct(Number(sum.cur.net_sales) ? (net / Number(sum.cur.net_sales)) * 100 : null, 1)}`, true)}
        ${kpi('الربح الإجمالي', 'chart', moneyR(gp), 'ج', `من مبيعات ${moneyR(sum.cur.net_sales)} ج`)}
        ${kpi('المصروفات', 'receipt', moneyR(ex), 'ج', exp[0] ? `أكبرها ${exp[0].category} (${pct(exp[0].share_pct)})` : 'مفيش مصروفات')}
        ${kpi('في الخزن دلوقتي', 'wallet', moneyR(cash.reduce((s, r) => s + Number(r.closing), 0)), 'ج', `${cash.length} خزنة`)}
      </section>
      ${card('صافي الربح شهر بشهر', 'الربح الإجمالي (أعمدة) والمصروفات (خط) — الفرق بينهم هو صافي الربح', h`<div id="ch4" style="height:270px"></div>`, { end: h`<div class="legend"><span><i style="background:var(--s1)"></i>الربح الإجمالي</span><span class="l2"><i style="background:var(--s2)"></i>المصروفات</span></div>` })}
      <section class="grid g2" style="margin-top:16px">
        ${card('حركة الخزن', 'أولها، الداخل، الخارج، وآخرها', table('cash', [
          { t: 'الخزنة', f: (r) => h`<b>${r.account}</b>`, x: (r) => r.account }, { t: 'أولها', n: 1, f: (r) => money(r.opening), x: (r) => r.opening },
          { t: 'داخل', n: 1, f: (r) => h`<span style="color:var(--good)">+${money(r.inflow)}</span>`, x: (r) => r.inflow }, { t: 'خارج', n: 1, f: (r) => h`<span style="color:var(--bad)">−${money(r.outflow)}</span>`, x: (r) => r.outflow },
          { t: 'آخرها', n: 1, f: (r) => h`<b>${money(r.closing)}</b>`, x: (r) => r.closing },
          { t: 'التفاصيل', f: (r) => h`<span class="muted" style="font-size:12px">${Object.entries(r.by_type || {}).map(([k, v]) => `${TYPE_AR[k] || k} ${money(v)}`).join(' · ')}</span>`, x: (r) => JSON.stringify(r.by_type) },
        ], cash, { name: 'حركة-الخزن' }), { csv: 'cash' })}
        ${card('المصروفات حسب النوع', '', exp.length ? h`<div class="list">${exp.map((r) => h`<div class="li"><div class="grow"><b>${r.category}</b>${meter(r.total, exp[0].total, 'warn')}</div><div class="end"><b>${money(r.total)}</b><div class="muted" style="font-size:12px">${int(r.entries)} مرة · ${pct(r.share_pct)}</div></div></div>`)}</div>` : empty('مفيش مصروفات في الفترة دي'))}
      </section>
      ${card('الأرباح والخسائر شهر بشهر', '', table('pnl', [
        { t: 'الشهر', f: (r) => dateMY(r.month), x: (r) => r.month }, { t: 'المبيعات', n: 1, f: (r) => money(r.net_sales), x: (r) => r.net_sales }, { t: 'التكلفة', n: 1, f: (r) => money(r.cost), x: (r) => r.cost },
        { t: 'الربح الإجمالي', n: 1, f: (r) => money(r.gross_profit), x: (r) => r.gross_profit }, { t: 'المصروفات', n: 1, f: (r) => money(r.expenses), x: (r) => r.expenses },
        { t: 'صافي الربح', n: 1, f: (r) => h`<b style="color:${Number(r.net_profit) < 0 ? 'var(--bad)' : 'inherit'}">${money(r.net_profit)}</b>`, x: (r) => r.net_profit }, { t: 'الهامش', n: 1, f: (r) => pct(r.net_margin_pct, 1), x: (r) => r.net_margin_pct },
      ], pnl.slice().reverse(), { limit: 12, name: 'الأرباح-والخسائر' }), { csv: 'pnl' })}`);
    $$('#body > .card', el).forEach((c) => { c.style.marginTop = '16px'; });
    cleanups.push(barLine($('#ch4', body), { labels: pnl.map((r) => new Intl.DateTimeFormat('ar-EG-u-nu-latn', { month: 'short' }).format(toDate(r.month))), bars: pnl.map((r) => Math.max(0, Number(r.gross_profit))), line: pnl.map((r) => Number(r.expenses)), barName: 'الربح الإجمالي', lineName: 'المصروفات', label: (i) => `${dateMY(pnl[i].month)} · صافي ${money(pnl[i].net_profit)}` }));
  }

  // ------------------------------------------------------------ 7) المتجر
  async function store() {
    const [orders, noimg] = await Promise.all([api.rpc('rep_store_orders', P()), api.rpc('rep_store_no_image', { p_limit: 300 })]);
    const ok = orders.filter((o) => o.status !== 'cancelled');
    const rev = ok.reduce((s, o) => s + Number(o.total), 0);
    const ST = { new: ['جديد', 'p-info'], confirmed: ['اتأكد', 'p-gold'], out: ['مع الدليفري', 'p-warn'], delivered: ['اتسلّم', 'p-good'], cancelled: ['اتلغى', 'p-muted'] };
    render(body, h`
      <section class="grid g4">
        ${kpi('طلبات المتجر', 'pos', int(orders.length), 'طلب', `${orders.filter((o) => o.status === 'new').length} جديد مستني`, true)}
        ${kpi('اتسلّم', 'check', int(orders.filter((o) => o.status === 'delivered').length), '', `${orders.filter((o) => o.status === 'cancelled').length} اتلغى`)}
        ${kpi('قيمة الطلبات', 'cash', moneyR(rev), 'ج', `متوسط الطلب ${moneyR(ok.length ? rev / ok.length : 0)} ج`)}
        ${kpi('أصناف من غير صورة', 'alert', int(noimg.length), 'صنف', 'متاحة في المتجر ومحتاجة تتصور')}
      </section>
      <section class="grid g2" style="margin-top:16px">
        ${card('طلبات المتجر', '', table('orders', [
          { t: 'الطلب', f: (r) => h`<b>${r.name}</b><div class="muted" style="font-size:12px">${dateTime(r.created_at)} · ${r.items_count} صنف</div>`, x: (r) => `${r.name} ${r.created_at}` },
          { t: 'الإجمالي', n: 1, f: (r) => h`<b>${money(r.total)}</b>`, x: (r) => r.total }, { t: 'الحالة', f: (r) => h`<span class="pill ${(ST[r.status] || ['', 'p-muted'])[1]}">${(ST[r.status] || [r.status])[0]}</span>`, x: (r) => r.status },
        ], orders, { limit: 15, name: 'طلبات-المتجر', empty: 'مفيش طلبات في الفترة دي' }), { csv: 'orders' })}
        ${card('أصناف لسه ملهاش صورة', 'الأكتر بيعًا الأول — دي اللي تستاهل تتصوّر الأول', table('noimg', [
          { t: 'الصنف', f: nm, x: (r) => r.name_en }, { t: 'الرصيد', n: 1, f: (r) => qty(r.onhand_units, r.pack_parts), x: (r) => r.onhand_units }, { t: 'اتباع 30 يوم', n: 1, f: (r) => qty(r.sold_30d_units, r.pack_parts), x: (r) => r.sold_30d_units },
        ], noimg, { limit: 15, name: 'من-غير-صورة', empty: 'كل الأصناف ليها صور', href: (r) => '#/items/' + r.item_id }), { csv: 'noimg' })}
      </section>`);
  }

  // ------------------------------------------------------------ ملخص الصبح
  async function brief() {
    let text;
    try { text = await api.rpc('morning_brief_text'); } catch (e) { return import('../ui.js').then((u) => u.toast(e.message, 'bad')); }
    const m = modal({ title: 'ملخص الصبح', body: h`<p class="muted" style="margin-top:0">نفس الملخص اللي يوزر البوت يقدر يقراه. تبعته لنفسك أو للمدير بإيدك.</p>
      <pre style="white-space:pre-wrap;font-family:var(--f-ui);background:var(--card-2);border:1px solid var(--line);border-radius:14px;padding:16px;margin:0;line-height:1.9">${text}</pre>`,
      footer: h`<button class="btn quiet" id="cp">${icon('copy')} انسخ</button><a class="btn" target="_blank" rel="noopener" href="${waLink('', text)}">${icon('whatsapp')} افتح واتساب</a>` });
    $('#cp', m.el).addEventListener('click', () => copyText(text));
  }

  await show();
  return () => cleanups.forEach((c) => c && c());
}
