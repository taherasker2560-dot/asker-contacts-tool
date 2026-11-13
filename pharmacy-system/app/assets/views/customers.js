// العملاء: مواعيد صرف المزمنين (رسالة تذكير جاهزة)، اقتراحات «مزمن» من تاريخ الشرا، المديونيات والتحصيل، وصفحة العميل.
import { h, render, $, $$, icon, money, moneyR, int, num, dateShort, dateTime, inDays, ago, skeleton, errorBox, empty, copyText, waLink, toast, modal } from '../ui.js';

const DOC_AR = { sale: 'فاتورة', sale_return: 'مرتجع', payment: 'دفعة', opening: 'رصيد أول', import: 'نقل', adjust: 'تسوية' };
const TABS = [['refills', 'مواعيد الصرف', 'bell'], ['chronic', 'اقتراحات مزمن', 'sparkle'], ['dues', 'المديونيات', 'wallet'], ['all', 'كل العملاء', 'users']];

export default async function customers(ctx) {
  const p0 = ctx.params[0];
  if (p0 && /^\d+$/.test(p0)) return customerPage(ctx, +p0);
  const { el, api } = ctx;
  let tab = TABS.some((t) => t[0] === p0) ? p0 : 'refills';
  render(el, h`
    <div class="head"><div><h1>العملاء</h1><p>العميل المزمن اللي بتفكّره بعلبته… مابيروحش لحد تاني.</p></div></div>
    <div class="chips" id="tabs" data-tabs style="margin-bottom:14px">${TABS.map(([k, l, ic]) => h`<button class="chip ${k === tab ? 'on' : ''}" data-t="${k}">${l}<span class="c" data-c="${k}"></span></button>`)}</div>
    <div class="card" id="body">${skeleton(6)}</div>`);
  $('#tabs', el).addEventListener('click', (e) => { const c = e.target.closest('.chip'); if (!c) return; tab = c.dataset.t; history.replaceState(null, '', '#/customers/' + tab); $$('#tabs .chip', el).forEach((x) => x.classList.toggle('on', x === c)); show(); });
  const body = $('#body', el);
  const reminder = (r) => `أهلًا ${r.customer.split(' ').slice(0, 2).join(' ')}، معاك صيدلية عسكر 🌿\nميعاد علبة ${r.name_ar || r.name_en} قرّب. تحب نجهزهالك ولا نبعتهالك البيت؟`;

  async function show() {
    render(body, skeleton(6));
    try {
      if (tab === 'refills') {
        const rows = await api.select('v_refills_due', { order: 'days_late.desc' });
        render(body, rows.length ? h`<header><div><h2>ميعاد علبتهم قرّب أو فات</h2><span class="sub">الرسالة بتتكتب لوحدها، وإنت اللي بتدوس إرسال</span></div></header>
          <div class="list">${rows.map((r, i) => h`<div class="li" data-row><span class="ico ${r.days_late > 0 ? 'i-bad' : 'i-gold'}">${icon('heart')}</span>
            <div class="grow"><a href="#/customers/${r.customer_id}" style="color:inherit;text-decoration:none"><b>${r.customer}</b></a><span class="muted" style="font-size:13px">${r.name_ar || r.name_en} · كل ${r.every_days} يوم · آخر مرة ${dateShort(r.last_bought)}</span></div>
            <span class="pill ${r.days_late > 0 ? 'p-bad' : 'p-warn'}">${r.days_late > 0 ? 'متأخر ' + r.days_late + ' يوم' : inDays(-r.days_late)}</span>
            <button class="btn sm ghost" data-copy="${i}" data-key="c" title="انسخ رسالة التذكير">${icon('copy')}</button>
            <a class="btn sm" data-key="w" title="فكّره على واتساب" target="_blank" rel="noopener" href="${waLink(r.phone, reminder(r))}">${icon('whatsapp')} فكّره <kbd style="background:transparent;color:#f0cdd5">W</kbd></a></div>`)}</div>`
          : empty('مفيش مواعيد قريبة', 'العملاء المزمنين كلهم واخدين علبهم'));
        body.onclick = (e) => { const b = e.target.closest('[data-copy]'); if (b) copyText(reminder(rows[+b.dataset.copy])); };
      } else if (tab === 'chronic') {
        const rows = await api.select('v_chronic_suggestions', { order: 'times.desc', limit: 60 });
        render(body, rows.length ? h`<header><div><h2>شكلهم مزمنين</h2><span class="sub">نفس الصنف 4 مرات أو أكتر بفترات منتظمة في آخر 8 شهور. سجّلهم والبرنامج يفكّرك</span></div></header>
          <div class="tbl-wrap"><table class="tbl"><thead><tr><th>العميل</th><th>الصنف</th><th class="n">مرات</th><th class="n">كل</th><th>الميعاد الجاي</th><th></th></tr></thead><tbody>
          ${rows.map((r, i) => h`<tr data-row><td><a href="#/customers/${r.customer_id}" style="color:inherit"><b>${r.customer}</b></a></td><td class="name"><b>${r.name_ar || r.name_en}</b><span class="en">${r.name_en}</span></td>
            <td class="n">${r.times}</td><td class="n">${r.every_days} يوم</td><td>${dateShort(r.next_due)}</td>
            <td><button class="btn sm ok" data-add="${i}" data-key="a" title="سجّله مزمن">${icon('plus')} سجّله مزمن <kbd style="background:transparent;color:#fff">A</kbd></button></td></tr>`)}</tbody></table></div>`
          : empty('مفيش اقتراحات جديدة'));
        body.onclick = async (e) => {
          const b = e.target.closest('[data-add]'); if (!b) return;
          const r = rows[+b.dataset.add]; b.disabled = true;
          try { await ctx.api.rpc('add_chronic', { p_customer: r.customer_id, p_item: r.item_id, p_every: r.every_days }); b.closest('tr').style.opacity = '.4'; b.textContent = 'اتسجل ✓'; toast(`${r.customer}: ${r.name_ar || r.name_en} كل ${r.every_days} يوم ✓`, 'good'); }
          catch (er) { b.disabled = false; toast(er.message, 'bad'); }
        };
      } else if (tab === 'dues') {
        const rows = await api.select('v_customer_dues', { order: 'balance.desc', balance: 'gt.0' });
        const tot = rows.reduce((s, r) => s + Number(r.balance), 0);
        render(body, h`<header><div><h2>على العملاء ${money(tot)} ج</h2><span class="sub">${rows.length} عميل · ${rows.filter((r) => r.over_limit).length} عدّوا الحد</span></div></header>
          ${rows.length ? h`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>العميل</th><th class="n">عليه</th><th>من الحد</th><th>آخر دفعة</th><th></th></tr></thead><tbody>
          ${rows.map((r, i) => { const used = Number(r.credit_limit) ? Number(r.balance) / Number(r.credit_limit) : 1; return h`<tr data-row><td><a href="#/customers/${r.id}" style="color:inherit"><b>${r.name}</b></a><div class="muted ltr" style="font-size:12px;text-align:right">${r.phone || ''}</div></td>
            <td class="n"><b>${money(r.balance)}</b></td><td style="min-width:150px"><div class="meter"><i class="${used > 1 ? 'bad' : used > 0.8 ? 'warn' : ''}" style="width:${Math.min(100, used * 100)}%"></i></div><span class="muted" style="font-size:12px">الحد ${money(r.credit_limit)}</span></td>
            <td>${r.last_payment ? ago(r.last_payment) : h`<span class="pill p-warn">مادفعش قبل كده</span>`}</td>
            <td><button class="btn sm" data-pay="${i}" data-key="p" title="حصّل منه">${icon('wallet')} حصّل <kbd style="background:transparent;color:#f0cdd5">P</kbd></button></td></tr>`; })}</tbody></table></div>` : empty('مفيش ديون على حد')}`);
        body.onclick = (e) => { const b = e.target.closest('[data-pay]'); if (b) { const r = rows[+b.dataset.pay]; collect(ctx, { id: r.id, name: r.name, balance: r.balance }, show); } };
      } else {
        render(body, h`<div class="search" style="margin-bottom:12px">${icon('search')}<input class="input" id="cs" data-search placeholder="اسم أو رقم موبايل ( / )"></div><div id="cl"></div>`);
        const cl = $('#cl', body);
        const run = async (t) => {
          const p = { order: 'name', limit: 60, active: 'eq.true' };
          const d = t.replace(/\D/g, '');
          if (t) p.or = d.length >= 3 ? `(phone.like.*${d}*)` : `(name.ilike.*${t.replace(/[(),*]/g, ' ')}*)`;
          const rows = await api.select('v_customer_pick', p);
          render(cl, rows.length ? h`<div class="list">${rows.map((c) => h`<a class="li" data-row href="#/customers/${c.id}" style="text-decoration:none;color:inherit"><span class="avatar" style="background:var(--crimson-100);color:var(--accent-ink)">${c.name.slice(0, 1)}</span><div class="grow"><b>${c.name}</b><span class="muted ltr" style="font-size:13px">${c.phone || ''}</span></div>${Number(c.balance) > 0 ? h`<span class="pill p-warn">عليه ${money(c.balance)}</span>` : ''}</a>`)}</div>` : empty('مفيش عميل بالاسم ده'));
        };
        let t; $('#cs', body).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => run(e.target.value.trim()), 200); });
        run('');
      }
    } catch (e) { render(body, errorBox(e)); }
  }
  // العدادات على التابات
  Promise.all([api.select('v_refills_due', { select: 'customer_id' }), api.select('v_chronic_suggestions', { select: 'customer_id' }), api.select('v_customer_dues', { select: 'id', balance: 'gt.0' })])
    .then(([a, b, c]) => { [['refills', a], ['chronic', b], ['dues', c]].forEach(([k, l]) => { const s = $(`[data-c="${k}"]`, el); if (s) s.textContent = l.length; }); }).catch(() => {});
  show();
}

async function collect({ api }, c, after) {
  let shift = null, accs = [];
  try { [shift] = await api.rpc('my_open_shift'); } catch (e) {}
  try { accs = await api.select('cash_accounts', { active: 'eq.true', order: 'id' }); } catch (e) {}
  const m = modal({ title: 'تحصيل من ' + c.name, body: h`<div class="stack">
      <p class="muted" style="margin:0">عليه دلوقتي <b>${money(c.balance)}</b> ج</p>
      <div class="field"><label>المبلغ</label><input class="input num" id="am" type="number" min="1" step="0.5" value="${Number(c.balance) || ''}" autofocus></div>
      ${shift ? h`<p class="muted" style="margin:0">${icon('cash', 'icon-sm')} هيدخل درج ورديتك (${shift.account})</p>` : h`<div class="field"><label>دخل فين</label><select class="input" id="ac">${accs.map((a) => h`<option value="${a.id}">${a.name}</option>`)}</select></div>`}
      <div class="field"><label>ملاحظة</label><input class="input" id="nt" placeholder="اختياري"></div></div>`,
    footer: h`<button class="btn quiet" data-close>إلغاء</button><button class="btn ok" id="go">سجّل الدفعة</button>` });
  $('#go', m.el).addEventListener('click', async () => {
    const amount = +$('#am', m.el).value; if (!(amount > 0)) return $('#am', m.el).focus();
    try {
      const r = await api.rpc('post_payment', { p: { kind: 'from_customer', party_id: c.id, amount, shift_id: shift ? shift.id : null, account_id: shift ? null : +$('#ac', m.el).value, note: $('#nt', m.el).value || null, client_uuid: api.uuid() } });
      m.close(); toast(`اتسجلت ${r.no || ''} ✓ ${money(amount)} ج`, 'good'); if (after) after();
    } catch (e) { toast(e.message, 'bad'); }
  });
}

async function customerPage(ctx, id) {
  const { el, api } = ctx;
  render(el, h`<div class="card">${skeleton(8)}</div>`);
  let c, meds, stmt, sales;
  try {
    [c, meds, stmt, sales] = await Promise.all([
      api.one('v_customer_pick', { id: 'eq.' + id }),
      api.select('customer_meds', { customer_id: 'eq.' + id, active: 'eq.true', select: 'item_id,every_days,last_bought,items(name_ar,name_en)' }),
      api.select('v_party_statement', { party_type: 'eq.customer', party_id: 'eq.' + id, order: 'at.desc', limit: 30 }).catch(() => []),
      api.select('sales', { customer_id: 'eq.' + id, status: 'eq.posted', select: 'id,no,at,total,on_credit', order: 'at.desc', limit: 200 }),
    ]);
  } catch (e) { return render(el, errorBox(e)); }
  if (!c) return render(el, h`<div class="card">${empty('العميل ده مش موجود')}</div>`);
  const spent = sales.reduce((s, x) => s + Number(x.total), 0);
  const visits = new Set(sales.map((s) => s.at.slice(0, 10))).size;
  const used = Number(c.credit_limit) ? Number(c.balance) / Number(c.credit_limit) : 0;
  render(el, h`
    <div class="head"><div><a href="#/customers/all" data-back class="muted" style="text-decoration:none;font-size:14px">${icon('back', 'icon-sm')} العملاء</a>
      <h1 style="margin-top:4px">${c.name}</h1><p class="ltr" style="text-align:right">${c.phone || ''}${c.area ? ' · ' + c.area : ''}</p></div>
      <div class="actions"><button class="btn" id="pay" data-hot="alt+p">${icon('wallet')} حصّل <kbd style="background:transparent;color:#f0cdd5">Alt+P</kbd></button><a class="btn quiet" data-hot="alt+w" target="_blank" rel="noopener" href="${waLink(c.phone, 'أهلًا ' + c.name.split(' ')[0] + '، معاك صيدلية عسكر')}">${icon('whatsapp')} واتساب</a></div></div>
    <section class="grid g4">
      <div class="card kpi hero"><div class="l">${icon('wallet')} عليه</div><div class="v">${money(c.balance)}<small>ج</small></div><div class="f">الحد ${money(c.credit_limit)}</div></div>
      <div class="card kpi"><div class="l">${icon('receipt')} اشترى بـ</div><div class="v">${moneyR(spent)}<small>ج</small></div><div class="f">آخر ${sales.length} فاتورة</div></div>
      <div class="card kpi"><div class="l">${icon('users')} زيارات</div><div class="v">${int(visits)}</div><div class="f">${sales[0] ? 'آخر مرة ' + ago(sales[0].at) : 'لسه'}</div></div>
      <div class="card kpi"><div class="l">${icon('heart')} أدوية مزمنة</div><div class="v">${int(meds.length)}</div><div class="f">${used > 1 ? h`<span class="pill p-bad">عدّى الحد</span>` : used > 0.8 ? h`<span class="pill p-warn">قرّب من الحد</span>` : h`<span class="pill p-good">في الأمان</span>`}</div></div>
    </section>
    <section class="grid g2" style="margin-top:16px">
      <div class="card"><header><h2>أدويته المزمنة</h2></header><div class="list">${meds.length ? meds.map((m) => {
        const due = m.last_bought ? Math.round((new Date(m.last_bought + 'T12:00:00').getTime() + m.every_days * 864e5 - Date.now()) / 864e5) : null;
        return h`<div class="li"><span class="ico i-gold">${icon('heart')}</span><div class="grow"><b>${m.items.name_ar || m.items.name_en}</b><span class="muted" style="font-size:13px">كل ${m.every_days} يوم · آخر مرة ${dateShort(m.last_bought)}</span></div>${due == null ? '' : h`<span class="pill ${due < 0 ? 'p-bad' : due <= 3 ? 'p-warn' : 'p-good'}">${inDays(due)}</span>`}</div>`;
      }) : empty('مش متسجل له أدوية مزمنة')}</div></div>
      <div class="card"><header><h2>كشف الحساب</h2><span class="sub">آخر 30 حركة</span></header>
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th>الوقت</th><th>الحركة</th><th class="n">المبلغ</th><th class="n">الرصيد</th></tr></thead><tbody>
        ${stmt.map((s) => h`<tr><td>${dateTime(s.at)}</td><td>${DOC_AR[s.doc_type] || s.doc_type}</td><td class="n" style="color:${Number(s.amount) < 0 ? 'var(--good)' : 'inherit'}">${money(s.amount)}</td><td class="n"><b>${money(s.balance_after)}</b></td></tr>`)}
        </tbody></table></div></div>
    </section>`);
  $('#pay', el).addEventListener('click', () => collect(ctx, c, () => customerPage(ctx, id)));
}
