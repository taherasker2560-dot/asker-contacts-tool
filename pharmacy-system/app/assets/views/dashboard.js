// لوحة النهارده: أول ما الدكتور يفتح. الأرقام المهمة، اللي محتاج منه، والبيع ماشي إزاي مقارنة بالأسبوع اللي فات.
import { h, render, icon, money, moneyR, int, pct, qty, time, ago, skeleton, errorBox, $, inDays } from '../ui.js';
import { barLine, spark } from '../charts.js';

// فحص السلامة بيقرا الدفاتر كلها (تقيل على سنين داتا): مرة كل ربع ساعة، والباقي من النسخة المحفوظة
async function cachedHealth(api) {
  try { const c = JSON.parse(sessionStorage.getItem('asker.health') || 'null'); if (c && Date.now() - c.at < 15 * 60e3) return c.rows; } catch (e) {}
  const rows = await api.rpc('health_check').catch(() => null);
  if (rows) try { sessionStorage.setItem('asker.health', JSON.stringify({ at: Date.now(), rows })); } catch (e) {}
  return rows;
}
const hello = () => { const hr = new Date().getHours(); return hr < 12 ? 'صباح الخير' : hr < 18 ? 'نهارك سعيد' : 'مساء الخير'; };

export default async function dashboard({ el, api, state, can }) {
  const first = (state.user.name || '').split(' ').slice(0, 2).join(' ');
  render(el, h`
    <div class="head"><div><h1>${hello()} يا ${first}</h1><p id="sub">بجهّز أرقام النهارده…</p></div>
      <div class="actions"><a class="btn" href="#/pos">${icon('pos')} بيع جديد <kbd style="background:transparent;color:var(--on-c-2);border-color:rgba(255,255,255,.3)">F2</kbd></a>
      <button class="btn quiet" id="rf" title="F5">${icon('refresh')} تحديث <kbd>F5</kbd></button></div></div>
    <section class="grid g4" id="kpis">${[1, 2, 3, 4].map(() => h`<div class="card kpi">${skeleton(3)}</div>`)}</section>
    <section class="card" style="margin-top:16px"><header><h2>محتاج منك النهارده</h2><span class="sub" id="health"></span></header><div class="todo" id="todo">${skeleton(2)}</div></section>
    <section class="grid g-wide" style="margin-top:16px">
      <div class="card"><header><div><h2>البيع بالساعة</h2><span class="sub">النهارده مقارنة بنفس اليوم الأسبوع اللي فات</span></div>
        <div class="legend"><span><i style="background:var(--s1)"></i>النهارده</span><span class="l2"><i style="background:var(--s2)"></i>الأسبوع اللي فات</span></div></header>
        <div id="hourly" style="height:270px">${skeleton(5)}</div></div>
      <div class="card"><header><h2>الأكتر بيعًا النهارده</h2><a class="sub" href="#/reports">التقارير ←</a></header><div class="list" id="top">${skeleton(6)}</div></div>
    </section>
    <section class="grid g3" style="margin-top:16px">
      <div class="card"><header><h2>الفلوس</h2></header><div class="list" id="money">${skeleton(4)}</div></div>
      <div class="card"><header><h2>آخر الفواتير</h2><span class="sub" id="live"></span></header><div class="list" id="feed">${skeleton(5)}</div></div>
      <div class="card"><header><h2>مواعيد صرف قرّبت</h2><a class="sub" href="#/customers">الكل ←</a></header><div class="list" id="refills">${skeleton(4)}</div></div>
    </section>`);
  $('#rf', el).addEventListener('click', () => load(true));
  const cleanups = [];

  async function load(again) {
    let d, daily, hourly, top, cash, feed, refills, health;
    try {
      [d, daily, hourly, top, cash, feed, refills, health] = await Promise.all([
        api.one('v_dashboard'),
        api.select('v_sales_daily', { business_day: 'gte.' + new Date(Date.now() - 16 * 864e5).toISOString().slice(0, 10), order: 'business_day.desc', limit: 15 }),   // آخر أسبوعين بس (السريع)
        api.select('v_sales_hourly', { order: 'hr' }),
        api.select('v_top_items_today', { order: 'value.desc', limit: 7 }),
        can(['owner', 'manager']) ? api.select('v_cash_balances', { order: 'id' }) : [],
        api.select('sales', { select: 'id,no,at,total,on_credit,channel,customers(name)', status: 'eq.posted', order: 'at.desc', limit: 7 }),
        api.select('v_refills_due', { order: 'days_late.desc', limit: 5 }),
        can(['owner', 'manager']) ? cachedHealth(api) : null,
      ]);
    } catch (e) { render($('#kpis', el), errorBox(e)); return; }
    if (!d) return;
    state.dash = d;
    const lw = Number(d.sales_last_week_same_time), today = Number(d.sales_today);
    const delta = lw > 0 ? ((today - lw) / lw) * 100 : null;
    const margin = Number(d.profit_today) && today ? (Number(d.profit_today) / (today - Number(d.returns_today))) * 100 : null;
    const avg = Number(d.invoices_today) ? today / Number(d.invoices_today) : 0;
    $('#sub', el).textContent = `${int(d.invoices_today)} فاتورة لحد دلوقتي · آخر تحديث ${time(new Date())}`;
    const series = daily.slice().reverse();   // من الأقدم للأحدث
    render($('#kpis', el), h`
      <div class="card kpi hero"><div class="l">${icon('cash')} مبيعات النهارده</div>
        <div class="v">${moneyR(today)}<small>ج</small></div>
        <div class="f">${delta == null ? 'أول يوم للمقارنة' : h`<span class="delta ${delta >= 0 ? 'up' : 'down'}">${delta >= 0 ? '▲' : '▼'} ${Math.abs(delta).toFixed(0)}%</span> عن نفس الوقت الأسبوع اللي فات`}</div>
        <div class="spark" id="sp1" style="color:#e3c77e"></div></div>
      <div class="card kpi"><div class="l">${icon('sparkle')} الربح التقريبي</div>
        <div class="v">${moneyR(d.profit_today)}<small>ج</small></div>
        <div class="f"><span class="pill p-good plain">هامش ${pct(margin)}</span> بعد تكلفة كل تشغيلة</div>
        <div class="spark" id="sp2" style="color:var(--s2)"></div></div>
      <div class="card kpi"><div class="l">${icon('wallet')} في الدرج دلوقتي</div>
        <div class="v">${moneyR(d.cash_in_drawer)}<small>ج</small></div>
        <div class="f">${Number(d.open_shifts) ? h`<span class="pill p-good">${int(d.open_shifts)} وردية مفتوحة</span>` : h`<span class="pill p-muted">مفيش وردية مفتوحة</span>`}${Number(d.credit_today) ? h` · آجل ${moneyR(d.credit_today)}` : ''}</div></div>
      <div class="card kpi"><div class="l">${icon('receipt')} متوسط الفاتورة</div>
        <div class="v">${moneyR(avg)}<small>ج</small></div>
        <div class="f">${int(d.invoices_today)} فاتورة${Number(d.returns_today) ? h` · مرتجع ${moneyR(d.returns_today)}` : ''}</div>
        <div class="spark" id="sp3" style="color:var(--s1)"></div></div>`);
    spark($('#sp1', el), series.map((r) => Number(r.net_sales)), { color: '#e3c77e' });
    spark($('#sp2', el), series.map((r) => Number(r.gross_profit)), { color: 'var(--s2)' });
    spark($('#sp3', el), series.map((r) => (Number(r.invoices) ? Number(r.total) / Number(r.invoices) : 0)), { color: 'var(--s1)' });

    const todo = [
      { n: d.shortages, t: 'صنف ناقص محتاج يتطلب', href: '#/orders', ic: 'truck', tone: 'i-crimson', show: true },
      { n: d.expiring_30d, t: `تشغيلة صلاحيتها أقل من شهر · ${moneyR(d.expiry_risk_value)} ج في خطر`, href: '#/expiry', ic: 'hourglass', tone: 'i-bad', show: true },
      { n: d.refills_due, t: 'عميل ميعاد علبته قرّب', href: '#/customers', ic: 'bell', tone: 'i-gold', show: true },
      { n: d.customers_over_limit, t: 'عميل عدّى حد الآجل', href: '#/customers/dues', ic: 'alert', tone: 'i-bad', show: Number(d.customers_over_limit) > 0 },
      { n: d.ordered_today, t: 'صنف اتطلب النهارده', href: '#/orders', ic: 'check', tone: 'i-good', show: true },
      { n: d.open_notes, t: 'ملاحظة تجربة مفتوحة', href: '#/settings', ic: 'note', tone: 'i-info', show: can(['owner', 'manager']) },
    ].filter((x) => x.show).slice(0, 6);
    render($('#todo', el), h`${todo.map((x) => h`<a href="${x.href}" data-row><span class="ico ${x.tone}">${icon(x.ic)}</span><div><b>${int(x.n)}</b><span>${x.t}</span></div></a>`)}`);
    if (health) {
      const bad = health.filter((c) => !c.ok);
      render($('#health', el), bad.length
        ? h`<a class="pill p-bad" href="#/settings">${bad.length} فحص فيه مشكلة</a>`
        : h`<span class="pill p-good" title="${health.map((c) => c.check_name).join(' · ')}">${icon('shield')} القاعدة سليمة ${health.length}/${health.length}</span>`);
    }

    // البيع بالساعة: يوم الصيدلية من 6 الصبح لـ 6 الصبح
    const order = [...Array(24).keys()].map((i) => (i + 6) % 24);
    const byHr = Object.fromEntries(hourly.map((r) => [r.hr, r]));
    const nowHr = new Date().getHours();
    const idxNow = order.indexOf(nowHr);
    const lbl = (hr) => (hr === 0 ? '12ص' : hr < 12 ? hr + 'ص' : hr === 12 ? '12م' : hr - 12 + 'م');
    const $h = $('#hourly', el);
    $h.innerHTML = '';
    cleanups.forEach((c) => c()); cleanups.length = 0;
    cleanups.push(barLine($h, {
      labels: order.map(lbl),
      bars: order.map((hr, i) => (i <= idxNow ? Number(byHr[hr]?.today || 0) : 0)),
      line: order.map((hr) => Number(byHr[hr]?.last_week || 0)),
      barName: 'النهارده', lineName: 'الأسبوع اللي فات',
      label: (i) => `الساعة ${lbl(order[i])}`,
    }));

    const maxTop = Math.max(1, ...top.map((r) => Number(r.value)));
    render($('#top', el), top.length ? h`${top.map((r, i) => h`<a class="li" data-row href="#/items/${r.item_id}" style="text-decoration:none;color:inherit">
        <span class="ico ${i < 3 ? 'i-gold' : 'i-crimson'}" style="font-family:var(--f-display);font-size:16px">${i + 1}</span>
        <div class="grow"><b>${r.name_ar || r.name_en}</b><div class="meter" style="margin-top:6px"><i style="width:${(Number(r.value) / maxTop) * 100}%;background:var(--s1)"></i></div></div>
        <div class="end"><b>${moneyR(r.value)}</b><div class="muted" style="font-size:12px">${int(r.invoices)} فاتورة</div></div></a>`)}`
      : h`<div class="empty"><b>لسه مفيش بيع النهارده</b>أول فاتورة هتظهر هنا</div>`);

    const moneyRows = [
      ...cash.map((c) => ({ ic: c.kind === 'drawer' ? 'cash' : c.kind === 'bank' ? 'card' : 'wallet', t: c.name, v: c.balance, tone: 'i-good' })),
      { ic: 'users', t: 'على العملاء (آجل)', v: d.customers_due, tone: 'i-gold' },
      ...(can(['owner', 'manager']) ? [{ ic: 'factory', t: 'علينا للموردين', v: d.suppliers_due, tone: 'i-crimson' }] : []),
    ];
    render($('#money', el), h`${moneyRows.map((m) => h`<div class="li"><span class="ico ${m.tone}">${icon(m.ic)}</span><div class="grow"><b>${m.t}</b></div><div class="end"><b>${money(m.v)}</b> <span class="muted">ج</span></div></div>`)}`);

    render($('#feed', el), feed.length ? h`${feed.map((s) => h`<div class="li"><span class="ico ${Number(s.on_credit) ? 'i-gold' : 'i-good'}">${icon(Number(s.on_credit) ? 'users' : 'receipt')}</span>
        <div class="grow"><b class="ltr" style="text-align:right">${s.no}</b><span class="muted" style="font-size:13px">${s.customers ? s.customers.name : 'عميل كاش'} · ${ago(s.at)}</span></div>
        <div class="end"><b>${money(s.total)}</b>${Number(s.on_credit) ? h`<div style="font-size:12px" class="muted">آجل ${money(s.on_credit)}</div>` : ''}</div></div>`)}` : h`<div class="empty"><b>مفيش فواتير</b></div>`);
    $('#live', el).innerHTML = String(h`<span class="pill p-good">مباشر</span>`);

    render($('#refills', el), refills.length ? h`${refills.map((r) => h`<a class="li" data-row href="#/customers" style="text-decoration:none;color:inherit"><span class="ico i-gold">${icon('heart')}</span>
        <div class="grow"><b>${r.customer}</b><span class="muted" style="font-size:13px">${r.name_ar || r.name_en} · كل ${r.every_days} يوم</span></div>
        <span class="pill ${r.days_late > 0 ? 'p-bad' : 'p-warn'}">${r.days_late > 0 ? 'متأخر ' + r.days_late + ' يوم' : inDays(-r.days_late)}</span></a>`)}`
      : h`<div class="empty"><b>مفيش مواعيد قريبة</b>العملاء المزمنين كلهم واخدين علبهم</div>`);
    if (again) import('../ui.js').then((u) => u.toast('اتحدّث ✓'));
  }
  await load();
  const t = setInterval(() => { if (document.visibilityState === 'visible') load(); }, 60000);
  return () => { clearInterval(t); cleanups.forEach((c) => c()); };
}
