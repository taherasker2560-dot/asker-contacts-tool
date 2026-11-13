// الموردين: كارت لكل مورد (علينا كام، فواتيره وخصمه الفعلي في 90 يوم، عروضه)، كشف الحساب، والدفع.
import { h, render, $, $$, icon, money, moneyR, int, num, dateShort, dateTime, ago, skeleton, errorBox, empty, toast, modal } from '../ui.js';

const DOC_AR = { purchase: 'فاتورة شرا', purchase_return: 'مرتجع', payment: 'دفعة', opening: 'رصيد أول', import: 'نقل', adjust: 'تسوية' };

export default async function suppliers(ctx) {
  const { el, api } = ctx;
  if (ctx.params[0]) return supplierPage(ctx, +ctx.params[0]);
  render(el, h`<div class="head"><div><h1>الموردين</h1><p>الخصم الفعلي = بعد البونص، من فواتير الشرا نفسها مش من كلام المندوب.</p></div></div>
    <section class="grid g3" id="k"></section><section class="grid g3" id="cards" style="margin-top:16px">${skeleton(6)}</section>`);
  let rows;
  try { rows = await api.select('v_supplier_card', { order: 'balance.desc' }); } catch (e) { return render($('#cards', el), errorBox(e)); }
  const due = rows.reduce((s, r) => s + Math.max(0, Number(r.balance)), 0);
  const best = rows.filter((r) => r.avg_discount_90d != null).sort((a, b) => b.avg_discount_90d - a.avg_discount_90d)[0];
  render($('#k', el), h`
    <div class="card kpi hero"><div class="l">${icon('factory')} علينا للموردين</div><div class="v">${moneyR(due)}<small>ج</small></div><div class="f">${rows.filter((r) => Number(r.balance) > 0).length} مورد</div></div>
    <div class="card kpi"><div class="l">${icon('sparkle')} أعلى خصم فعلي (90 يوم)</div><div class="v">${best ? num(best.avg_discount_90d) : '—'}<small>%</small></div><div class="f">${best ? best.name : ''}</div></div>
    <div class="card kpi"><div class="l">${icon('receipt')} فواتير 90 يوم</div><div class="v">${int(rows.reduce((s, r) => s + Number(r.invoices_90d), 0))}</div><div class="f">${int(rows.reduce((s, r) => s + Number(r.offers_30d), 0))} عرض في آخر 30 يوم</div></div>`);
  const maxD = Math.max(1, ...rows.map((r) => Number(r.avg_discount_90d || 0)));
  render($('#cards', el), h`${rows.map((r) => h`<a class="card" data-row href="#/suppliers/${r.id}" style="text-decoration:none;color:inherit;display:block">
      <header><div><h2>${r.name}</h2><span class="sub">${r.kind === 'company' ? 'شركة' : r.kind === 'store' ? 'مخزن' : r.kind || ''}${r.last_invoice ? ' · آخر فاتورة ' + dateShort(r.last_invoice) : ''}</span></div><span class="ico i-crimson">${icon('factory')}</span></header>
      <div class="row between"><span class="muted">علينا</span><b style="font-family:var(--f-display);font-size:22px">${money(r.balance)}</b></div>
      <div style="margin-top:10px"><div class="row between" style="font-size:13px"><span class="muted">الخصم الفعلي</span><b>${r.avg_discount_90d == null ? '—' : num(r.avg_discount_90d) + '%'}</b></div>
        <div class="meter" style="margin-top:4px"><i style="width:${(Number(r.avg_discount_90d || 0) / maxD) * 100}%;background:var(--s2)"></i></div></div>
      <div class="row" style="margin-top:12px;gap:6px"><span class="pill p-muted plain">${int(r.invoices_90d)} فاتورة</span><span class="pill p-gold plain">${int(r.offers_30d)} عرض</span></div></a>`)}`);
}

async function supplierPage({ el, api, can }, id) {
  render(el, h`<div class="card">${skeleton(8)}</div>`);
  let s, stmt, inv;
  try {
    [s, stmt, inv] = await Promise.all([
      api.one('v_supplier_card', { id: 'eq.' + id }),
      api.select('v_party_statement', { party_type: 'eq.supplier', party_id: 'eq.' + id, order: 'at.desc', limit: 30 }),
      api.select('purchase_invoices', { supplier_id: 'eq.' + id, status: 'eq.posted', select: 'id,no,supplier_doc_no,invoice_date,total,legacy_no', order: 'invoice_date.desc', limit: 12 }),
    ]);
  } catch (e) { return render(el, errorBox(e)); }
  if (!s) return render(el, h`<div class="card">${empty('المورد ده مش موجود')}</div>`);
  render(el, h`
    <div class="head"><div><a href="#/suppliers" data-back class="muted" style="text-decoration:none;font-size:14px">${icon('back', 'icon-sm')} الموردين</a><h1 style="margin-top:4px">${s.name}</h1></div>
      <div class="actions">${can(['owner', 'manager']) ? h`<button class="btn" id="pay" data-hot="alt+p">${icon('cash')} دفع للمورد <kbd style="background:transparent;color:var(--on-c-2)">Alt+P</kbd></button>` : ''}</div></div>
    <section class="grid g3">
      <div class="card kpi hero"><div class="l">${icon('wallet')} علينا</div><div class="v">${money(s.balance)}<small>ج</small></div><div class="f">${s.last_invoice ? 'آخر فاتورة ' + dateShort(s.last_invoice) : ''}</div></div>
      <div class="card kpi"><div class="l">${icon('sparkle')} الخصم الفعلي</div><div class="v">${s.avg_discount_90d == null ? '—' : num(s.avg_discount_90d)}<small>%</small></div><div class="f">متوسط 90 يوم بعد البونص</div></div>
      <div class="card kpi"><div class="l">${icon('receipt')} فواتير 90 يوم</div><div class="v">${int(s.invoices_90d)}</div><div class="f">${int(s.offers_30d)} عرض في 30 يوم</div></div></section>
    <section class="grid g2" style="margin-top:16px">
      <div class="card"><header><h2>آخر الفواتير</h2></header><div class="list">${inv.length ? inv.map((i) => h`<div class="li"><span class="ico i-crimson">${icon('receipt')}</span><div class="grow"><b class="ltr" style="text-align:right">${i.no || i.legacy_no}</b><span class="muted" style="font-size:13px">${dateShort(i.invoice_date)}${i.supplier_doc_no ? ' · رقمهم ' + i.supplier_doc_no : ''}</span></div><b>${money(i.total)}</b></div>`) : empty('مفيش فواتير')}</div></div>
      <div class="card"><header><h2>كشف الحساب</h2></header><div class="tbl-wrap"><table class="tbl"><thead><tr><th>الوقت</th><th>الحركة</th><th class="n">المبلغ</th><th class="n">الرصيد</th></tr></thead><tbody>
        ${stmt.map((x) => h`<tr><td>${dateTime(x.at)}</td><td>${DOC_AR[x.doc_type] || x.doc_type}</td><td class="n">${money(x.amount)}</td><td class="n"><b>${money(x.balance_after)}</b></td></tr>`)}</tbody></table></div></div></section>`);
  const btn = $('#pay', el);
  if (btn) btn.addEventListener('click', async () => {
    let accs = []; try { accs = await api.select('cash_accounts', { active: 'eq.true', kind: 'neq.drawer', order: 'id' }); } catch (e) {}
    const m = modal({ title: 'دفع لـ ' + s.name, body: h`<div class="stack"><p class="muted" style="margin:0">علينا ${money(s.balance)} ج</p>
        <div class="field"><label>المبلغ</label><input class="input num" id="am" type="number" min="1" autofocus></div>
        <div class="field"><label>من</label><select class="input" id="ac">${accs.map((a) => h`<option value="${a.id}">${a.name}</option>`)}</select></div>
        <div class="field"><label>رقم الإيصال</label><input class="input" id="rc" placeholder="اختياري"></div></div>`,
      footer: h`<button class="btn quiet" data-close>إلغاء</button><button class="btn" id="go">سجّل</button>` });
    $('#go', m.el).addEventListener('click', async () => {
      const amount = +$('#am', m.el).value; if (!(amount > 0)) return;
      try { await api.rpc('post_payment', { p: { kind: 'to_supplier', party_id: id, amount, account_id: +$('#ac', m.el).value, receipt_no: $('#rc', m.el).value || null, client_uuid: api.uuid() } }); m.close(); toast('اتسجل ✓', 'good'); supplierPage({ el, api, can }, id); }
      catch (e) { toast(e.message, 'bad'); }
    });
  });
}
