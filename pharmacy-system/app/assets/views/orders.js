// الطلبيات الذكية: النواقص متجمّعة عند أحسن مورد (أعلى خصم فعلي/عرض)، بكميات مقترحة من سرعة البيع.
// المالك يعدّل الكمية، ينسخ الرسالة أو يفتح واتساب، يبعت بنفسه، وبعدين «اتطلبت» ← تتسجل طلبية والصنف يتعلم.
import { h, render, $, $$, icon, money, num, int, qty, dateTime, ago, skeleton, errorBox, empty, copyText, waLink, toast } from '../ui.js';

export default async function orders({ el, api, can }) {
  render(el, h`
    <div class="head"><div><h1>الطلبيات الذكية</h1><p>كل ناقص راح لأحسن مورد ليه. عدّل الكمية لو حابب، وابعت بنفسك.</p></div>
      <div class="actions"><button class="btn quiet" id="rf" data-hot="alt+r">${icon('refresh')} تحديث</button></div></div>
    <section class="grid g3" id="k"></section>
    <section id="groups" style="margin-top:16px">${skeleton(6)}</section>
    <section class="card" style="margin-top:16px"><header><h2>آخر الطلبيات اللي اتبعتت</h2></header><div class="list" id="hist">${skeleton(3)}</div></section>`);
  $('#rf', el).addEventListener('click', load);
  let groups = [];

  async function load() {
    let rows, hist, sups;
    try {
      [rows, hist, sups] = await Promise.all([
        api.select('v_order_advice', { order: 'name_en' }),
        api.select('purchase_orders', { select: 'id,no,sent_at,status,suppliers(name),purchase_order_lines(item_id,packs)', status: 'eq.sent', order: 'sent_at.desc', limit: 8 }),
        api.select('suppliers', { select: 'id,name,phone', active: 'eq.true' }),
      ]);
    } catch (e) { return render($('#groups', el), errorBox(e)); }
    const phone = Object.fromEntries(sups.map((s) => [s.id, s.phone]));
    const pending = rows.filter((r) => !r.ordered_today_from);
    const done = rows.filter((r) => r.ordered_today_from);
    const by = new Map();
    for (const r of pending) {
      const k = r.best_supplier_id || 0;
      const g = by.get(k) || { id: r.best_supplier_id, name: r.best_supplier || 'من غير عرض معروف', phone: phone[r.best_supplier_id], rows: [] };
      g.rows.push({ ...r, packs: Math.max(1, Math.ceil(Number(r.order_packs) || 1)) });
      by.set(k, g);
    }
    groups = [...by.values()].sort((a, b) => (a.id ? 0 : 1) - (b.id ? 0 : 1) || b.rows.length - a.rows.length);
    const gapAvg = pending.filter((r) => r.gap_pct != null).reduce((s, r, _, a) => s + Number(r.gap_pct) / a.length, 0);
    render($('#k', el), h`
      <div class="card kpi hero"><div class="l">${icon('truck')} محتاج يتطلب</div><div class="v">${int(pending.length)}<small>صنف</small></div><div class="f">عند ${groups.filter((g) => g.id).length} مورد</div></div>
      <div class="card kpi"><div class="l">${icon('check')} اتطلب النهارده</div><div class="v">${int(done.length)}<small>صنف</small></div><div class="f">${done.slice(0, 2).map((d) => d.name_ar || d.name_en).join('، ') || '—'}</div></div>
      <div class="card kpi"><div class="l">${icon('sparkle')} فرق أحسن عرض عن التاني</div><div class="v">${num(gapAvg.toFixed(1))}<small>%</small></div><div class="f">في المتوسط: ده اللي بتكسبه لما تطلب من الأحسن</div></div>`);
    render($('#groups', el), groups.length ? h`<div class="grid g2">${groups.map((g, gi) => h`
      <div class="card" data-g="${gi}" data-group><header><div><h2>${g.name}</h2><span class="sub">${g.rows.length} صنف${g.id ? '' : ' · اختار المورد بنفسك'}</span></div>
        ${g.id ? h`<span class="pill p-good plain">${icon('sparkle', 'icon-sm')} أحسن خصم</span>` : h`<span class="pill p-muted plain">مفيش عروض</span>`}</header>
        <div class="tbl-wrap"><table class="tbl"><thead><tr><th>الصنف</th><th class="n">عندنا</th><th class="n">اتباع 30 يوم</th><th class="n">الخصم</th><th class="n">الكمية</th><th></th></tr></thead><tbody>
        ${g.rows.map((r, ri) => h`<tr data-row><td class="name"><b>${r.name_ar || r.name_en}</b><span class="en">${r.name_en}</span></td>
          <td class="n">${Number(r.onhand_units) > 0 ? qty(r.onhand_units, r.pack_parts) : h`<span class="pill p-bad">صفر</span>`}</td>
          <td class="n">${qty(r.sold_30d_units, r.pack_parts)}</td>
          <td class="n">${r.best_pct != null ? h`<b>${num(r.best_pct)}%</b>${r.gap_pct != null && Number(r.gap_pct) > 0 ? h`<div class="muted" style="font-size:12px">+${num(r.gap_pct)} عن التاني</div>` : ''}` : '—'}</td>
          <td class="n"><input class="input num" type="number" min="0" step="1" value="${r.packs}" data-q="${gi}:${ri}" style="width:72px;height:34px;text-align:center"></td>
          <td><button class="btn sm quiet" data-x="${gi}:${ri}" data-key="Delete" title="مش دلوقتي">×</button></td></tr>`)}
        </tbody></table></div>
        <div class="row wrap" style="margin-top:12px">
          <button class="btn sm ghost" data-copy="${gi}" data-key="c" title="انسخ رسالة الطلبية">${icon('copy')} انسخ الرسالة <kbd>C</kbd></button>
          <a class="btn sm quiet" data-wa="${gi}" data-key="w" title="افتح واتساب المورد" target="_blank" rel="noopener" href="#">${icon('whatsapp')} افتح واتساب <kbd>W</kbd></a>
          ${g.id && can(['owner', 'manager', 'pharmacist']) ? h`<button class="btn sm ok" data-mark="${gi}" data-key="m" title="علّم الطلبية «اتطلبت»" style="margin-inline-start:auto">${icon('check')} اتطلبت <kbd style="background:transparent;color:#fff">M</kbd></button>` : ''}</div></div>`)}</div>`
      : h`<div class="card">${empty('مفيش نواقص', 'كل الأصناف فوق حدها الأدنى. برافو')}</div>`);
    $$('[data-wa]', el).forEach((a) => { const g = groups[+a.dataset.wa]; a.href = waLink(g.phone, message(g)); });

    render($('#hist', el), hist.length ? h`${hist.map((o) => h`<div class="li"><span class="ico i-good">${icon('truck')}</span><div class="grow"><b class="ltr" style="text-align:right">${o.no}</b><span class="muted" style="font-size:13px">${o.suppliers ? o.suppliers.name : ''} · ${o.purchase_order_lines.length} صنف</span></div><span class="muted">${ago(o.sent_at)}</span></div>`)}` : empty('لسه مفيش طلبيات'));
  }
  const message = (g) => 'السلام عليكم، طلبية صيدلية عسكر:\n' + g.rows.filter((r) => r.packs > 0).map((r) => `- ${r.name_en}: ${r.packs}`).join('\n') + '\nشكرًا';

  el.addEventListener('input', (e) => {
    const k = e.target.dataset.q; if (!k) return;
    const [gi, ri] = k.split(':').map(Number); groups[gi].rows[ri].packs = Math.max(0, Math.round(+e.target.value || 0));
    const a = $(`[data-wa="${gi}"]`, el); if (a) a.href = waLink(groups[gi].phone, message(groups[gi]));
  });
  el.addEventListener('click', async (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.copy) copyText(message(groups[+b.dataset.copy]));
    else if (b.dataset.x) { const [gi, ri] = b.dataset.x.split(':').map(Number); b.closest('tr').remove(); groups[gi].rows[ri].packs = 0; }
    else if (b.dataset.mark) {
      const g = groups[+b.dataset.mark], items = g.rows.filter((r) => r.packs > 0);
      if (!items.length) return toast('الطلبية فاضية', 'bad');
      b.disabled = true;
      try {
        const no = await api.rpc('mark_ordered', { p: { supplier_id: g.id, message: message(g), items: items.map((r) => ({ item_id: r.item_id, packs: r.packs, expected_pct: r.best_pct })) } });
        toast(`اتسجلت ${no} ✓ الأصناف دي مش هتظهر تاني النهارده`, 'good'); load();
      } catch (er) { b.disabled = false; toast(er.message, 'bad'); }
    }
  });
  await load();
}
