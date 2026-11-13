// الخزن: رصيد كل خزنة، وحركتها حركة حركة بالرصيد بعدها، والمصروفات، والتحويل بين الخزن (توريد الدرج للخزنة)، والورديات.
// كل حاجة بتتسجل بدوال القاعدة (post_expense و post_cash_transfer)، والدفتر مابيتعدلش.
import { h, render, $, $$, icon, money, moneyR, int, dateShort, dateTime, toast, modal, skeleton, errorBox, empty } from '../ui.js';

export const keys = [
  { k: ['Alt+KeyE'], t: 'مصروف جديد' },
  { k: ['Alt+KeyR'], t: 'تحويل بين الخزن (توريد الدرج للخزنة)' },
  { k: ['BracketRight', 'BracketLeft'], t: 'الخزنة اللي بعدها / قبلها' },
  { k: ['Shift+BracketRight', 'Shift+BracketLeft'], t: 'الفترة' },
];
const KIND_ICON = { drawer: 'cash', safe: 'wallet', bank: 'card', wallet: 'wallet' };
const DOC_AR = { sale: 'بيع', sale_return: 'مرتجع', payment: 'دفعة', expense: 'مصروف', purchase: 'شرا', shift: 'وردية', transfer: 'تحويل' };

export default async function cash({ el, api }) {
  let acc = 'all', days = 1, accs = [];
  render(el, h`
    <div class="head"><div><h1>الخزن</h1><p>كل جنيه داخل أو خارج متسجل بمستنده، والرصيد بعد كل حركة.</p></div>
      <div class="actions"><button class="btn quiet" id="exp" data-hot="alt+e">${icon('receipt')} مصروف <kbd>Alt+E</kbd></button>
        <button class="btn" id="trf" data-hot="alt+r">${icon('swap')} تحويل بين الخزن <kbd style="background:transparent;color:var(--on-c-2)">Alt+R</kbd></button></div></div>
    <section class="grid g4" id="cards">${[1, 2, 3, 4].map(() => h`<div class="card kpi">${skeleton(3)}</div>`)}</section>
    <section class="card" style="margin-top:16px">
      <div class="row wrap" style="gap:10px;margin-bottom:12px"><div class="chips" id="acc" data-tabs></div>
        <div class="chips" id="per" data-tabs="period" style="margin-inline-start:auto"><button class="chip on" data-d="1">النهارده</button><button class="chip" data-d="7">7 أيام</button><button class="chip" data-d="30">30 يوم</button></div></div>
      <div class="tbl-wrap"><table class="tbl"><thead><tr><th>الوقت</th><th>الخزنة</th><th>المستند</th><th>البيان</th><th class="n">داخل</th><th class="n">خارج</th><th class="n">الرصيد بعدها</th></tr></thead><tbody id="mv"></tbody></table></div>
    </section>
    <section class="grid g2" style="margin-top:16px">
      <div class="card"><header><div><h2>الورديات</h2><span class="sub">آخر 30 يوم: المفروض في الدرج واللي اتعدّ</span></div></header><div id="sh">${skeleton(4)}</div></div>
      <div class="card"><header><div><h2>المصروفات</h2><span class="sub">آخر 30 يوم</span></div></header><div id="ex">${skeleton(4)}</div></div>
    </section>`);

  const today = () => new Date(Date.now() - 6 * 3600e3 - new Date().getTimezoneOffset() * 6e4).toISOString().slice(0, 10);
  const since = (n) => { const d = new Date(today() + 'T12:00:00'); d.setDate(d.getDate() - (n - 1)); return d.toISOString().slice(0, 10); };

  async function cards() {
    try { accs = await api.select('v_cash_balances', { order: 'id' }); } catch (e) { return render($('#cards', el), errorBox(e)); }
    const total = accs.reduce((s, a) => s + Number(a.balance), 0);
    render($('#cards', el), h`<div class="card kpi hero"><div class="l">${icon('wallet')} الفلوس كلها</div><div class="v">${moneyR(total)}<small>ج</small></div><div class="f">${accs.length} خزنة</div></div>
      ${accs.slice(0, 3).map((a) => h`<div class="card kpi"><div class="l">${icon(KIND_ICON[a.kind] || 'wallet')} ${a.name}</div><div class="v">${money(a.balance)}<small>ج</small></div><div class="f">${{ drawer: 'درج كاشير', safe: 'خزنة', bank: 'بنك', wallet: 'محفظة' }[a.kind] || ''}</div></div>`)}`);
    render($('#acc', el), h`<button class="chip ${acc === 'all' ? 'on' : ''}" data-a="all">الكل</button>${accs.map((a) => h`<button class="chip ${String(a.id) === String(acc) ? 'on' : ''}" data-a="${a.id}">${a.name}</button>`)}`);
  }
  async function moves() {
    const p = { order: 'at.desc,id.desc', limit: 300, business_day: 'gte.' + since(days) };
    if (acc !== 'all') p.account_id = 'eq.' + acc;
    render($('#mv', el), h`<tr><td colspan="7">${skeleton(5)}</td></tr>`);
    let rows; try { rows = await api.select('v_cash_moves', p); } catch (e) { return render($('#mv', el), h`<tr><td colspan="7">${errorBox(e)}</td></tr>`); }
    render($('#mv', el), rows.length ? h`${rows.map((m) => h`<tr data-row><td>${dateTime(m.at)}</td><td>${m.account}</td>
      <td><span class="pill p-muted plain">${DOC_AR[m.doc_type] || m.doc_type}</span> <span class="ltr" style="font-size:12px">${m.doc_no || ''}</span></td>
      <td>${m.description || ''}</td>
      <td class="n" style="color:var(--good)">${Number(m.amount) > 0 ? money(m.amount) : ''}</td><td class="n" style="color:var(--bad)">${Number(m.amount) < 0 ? money(-m.amount) : ''}</td>
      <td class="n"><b>${money(m.balance_after)}</b></td></tr>`)}` : h`<tr><td colspan="7">${empty('مفيش حركة في الفترة دي')}</td></tr>`);
  }
  async function side() {
    try {
      const sh = await api.rpc('rep_by_shift', { p_from: since(30), p_to: today() });
      render($('#sh', el), sh.length ? h`<div class="list">${sh.slice(0, 10).map((r) => h`<div class="li" data-row><span class="ico ${r.status === 'open' ? 'i-good' : Number(r.diff) ? 'i-bad' : 'i-crimson'}">${icon('cash')}</span>
        <div class="grow"><b>${r.opened_by || '—'} · ${r.account}</b><span class="muted" style="font-size:13px">${dateTime(r.opened_at)} · ${int(r.invoices)} فاتورة · بيع ${money(r.sales)}</span></div>
        <div class="end">${r.status === 'open' ? h`<span class="pill p-good">مفتوحة</span><div class="muted" style="font-size:12px">المفروض ${money(r.expected)}</div>` : Number(r.diff) === 0 ? h`<span class="pill p-good plain">مظبوط</span>` : h`<span class="pill ${Number(r.diff) < 0 ? 'p-bad' : 'p-warn'}">${Number(r.diff) < 0 ? 'عجز ' : 'زيادة '}${money(Math.abs(r.diff))}</span>`}</div></div>`)}</div>` : empty('مفيش ورديات'));
    } catch (e) { render($('#sh', el), errorBox(e)); }
    try {
      const ex = await api.select('expenses', { select: 'no,amount,note,business_day,expense_categories(name)', business_day: 'gte.' + since(30), order: 'business_day.desc,id.desc', limit: 40 });
      const tot = ex.reduce((s, x) => s + Number(x.amount), 0);
      render($('#ex', el), ex.length ? h`<p class="muted" style="margin:0 0 6px">المجموع <b>${money(tot)}</b> ج</p><div class="list">${ex.slice(0, 12).map((x) => h`<div class="li" data-row><div class="grow"><b>${x.expense_categories ? x.expense_categories.name : 'مصروف'}</b><span class="muted" style="font-size:13px">${dateShort(x.business_day)}${x.note ? ' · ' + x.note : ''}</span></div><b>${money(x.amount)}</b></div>`)}</div>` : empty('مفيش مصروفات', 'Alt+E مصروف جديد'));
    } catch (e) { render($('#ex', el), errorBox(e)); }
  }
  const all = async () => { await cards(); moves(); side(); };

  $('#acc', el).addEventListener('click', (e) => { const c = e.target.closest('[data-a]'); if (!c) return; acc = c.dataset.a; $$('#acc .chip', el).forEach((x) => x.classList.toggle('on', x === c)); moves(); });
  $('#per', el).addEventListener('click', (e) => { const c = e.target.closest('[data-d]'); if (!c) return; days = +c.dataset.d; $$('#per .chip', el).forEach((x) => x.classList.toggle('on', x === c)); moves(); });

  // مصروف
  $('#exp', el).addEventListener('click', async () => {
    let cats = []; try { cats = await api.select('expense_categories', { order: 'name' }); } catch (e) {}
    const safe = (accs.find((a) => a.kind === 'safe') || accs[0] || {}).id;
    const m = modal({ title: 'مصروف جديد', body: h`<div class="stack">
        <div class="field"><label for="ec">النوع</label><select class="input" id="ec">${cats.map((c) => h`<option value="${c.id}">${c.name}</option>`)}<option value="new">+ نوع جديد…</option></select></div>
        <div class="field" id="ecnf" hidden><label for="ecn">اسم النوع الجديد</label><input class="input" id="ecn"></div>
        <div class="field"><label for="ea">المبلغ</label><input class="input num" id="ea" type="number" min="0.5" step="0.5" autofocus></div>
        <div class="field"><label for="eacc">اتدفع من</label><select class="input" id="eacc">${accs.map((a) => h`<option value="${a.id}" ${a.id === safe ? 'selected' : ''}>${a.name} (${money(a.balance)})</option>`)}</select></div>
        <div class="field"><label for="en">ملاحظة</label><input class="input" id="en" placeholder="اختياري"></div></div>`,
      footer: h`<button class="btn quiet" data-close>إلغاء</button><button class="btn" id="go">سجّل المصروف</button>` });
    $('#ec', m.el).addEventListener('change', (e) => { $('#ecnf', m.el).hidden = e.target.value !== 'new'; if (e.target.value === 'new') $('#ecn', m.el).focus(); });
    $('#go', m.el).addEventListener('click', async () => {
      const amount = +$('#ea', m.el).value; if (!(amount > 0)) return $('#ea', m.el).focus();
      try {
        let cat = $('#ec', m.el).value;
        if (cat === 'new') { const n = $('#ecn', m.el).value.trim(); if (!n) return $('#ecn', m.el).focus(); const [r] = await api.insert('expense_categories', { name: n }); cat = r.id; }
        const no = await api.rpc('post_expense', { p: { category_id: +cat, amount, account_id: +$('#eacc', m.el).value, note: $('#en', m.el).value.trim() || null } });
        m.close(); toast(`اتسجل ${no} ✓`, 'good'); all();
      } catch (e) { toast(e.message, 'bad'); }
    });
  });
  // تحويل
  $('#trf', el).addEventListener('click', () => {
    const drawer = (accs.find((a) => a.kind === 'drawer') || accs[0] || {}).id, safe = (accs.find((a) => a.kind === 'safe') || accs[1] || {}).id;
    const m = modal({ title: 'تحويل بين الخزن', body: h`<div class="stack">
        <p class="muted" style="margin:0">مثلًا توريد الدرج للخزنة آخر الوردية، أو من الخزنة للبنك.</p>
        <div class="field"><label for="tf">من</label><select class="input" id="tf">${accs.map((a) => h`<option value="${a.id}" ${a.id === drawer ? 'selected' : ''}>${a.name} (${money(a.balance)})</option>`)}</select></div>
        <div class="field"><label for="tt">لـ</label><select class="input" id="tt">${accs.map((a) => h`<option value="${a.id}" ${a.id === safe ? 'selected' : ''}>${a.name}</option>`)}</select></div>
        <div class="field"><label for="ta">المبلغ</label><input class="input num" id="ta" type="number" min="1" step="0.5" autofocus></div>
        <div class="field"><label for="tn">ملاحظة</label><input class="input" id="tn" placeholder="مثلًا: توريد وردية الصبح"></div></div>`,
      footer: h`<button class="btn quiet" data-close>إلغاء</button><button class="btn" id="go">حوّل</button>` });
    $('#go', m.el).addEventListener('click', async () => {
      const amount = +$('#ta', m.el).value; if (!(amount > 0)) return $('#ta', m.el).focus();
      try {
        const no = await api.rpc('post_cash_transfer', { p: { from_account: +$('#tf', m.el).value, to_account: +$('#tt', m.el).value, amount, note: $('#tn', m.el).value.trim() || null, client_uuid: api.uuid() } });
        m.close(); toast(`اتحوّل ${no} ✓`, 'good'); all();
      } catch (e) { toast(e.message, 'bad'); }
    });
  });
  await all();
}
