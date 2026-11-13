// الصلاحية: مش بس «إيه اللي قرّب يخلص»، لأ «إيه اللي هيخلص قبل ما يتباع بسرعة البيع الحالية» وقيمته،
// وتجميع المرتجع لكل مورد في رسالة جاهزة (المالك بيبعتها بنفسه).
import { h, render, $, $$, icon, money, moneyR, int, num, qty, dateShort, dateMY, inDays, skeleton, errorBox, empty, copyText, waLink, toDate } from '../ui.js';
import { bars } from '../charts.js';

export default async function expiry({ el, api, state }) {
  render(el, h`
    <div class="head"><div><h1>الصلاحية</h1><p>بسرعة البيع الحالية، والبيع من الأقرب صلاحية الأول: إيه اللي هيفضل لحد ما يخلص؟</p></div></div>
    <section class="grid g3" id="k">${[1, 2, 3].map(() => h`<div class="card kpi">${skeleton(3)}</div>`)}</section>
    <section class="grid g-wide" style="margin-top:16px">
      <div class="card"><header><div><h2>هيخلص قبل ما يتباع</h2><span class="sub">مترتب بالقيمة اللي في خطر (بالتكلفة)</span></div></header><div class="tbl-wrap"><table class="tbl"><thead><tr>
        <th>الصنف</th><th>الصلاحية</th><th class="n">الموجود</th><th class="n">هيتباع منه</th><th class="n">في خطر</th></tr></thead><tbody id="risk">${h`<tr><td colspan="5">${skeleton(6)}</td></tr>`}</tbody></table></div></div>
      <div class="card"><header><div><h2>قيمة المخزون حسب شهر الصلاحية</h2><span class="sub">الـ 12 شهر الجايين (بالتكلفة)</span></div></header><div id="months" style="height:300px"></div></div>
    </section>
    <section class="card" style="margin-top:16px"><header><div><h2>مرتجع للموردين</h2><span class="sub">اللي صلاحيته أقل من شهر أو خلصت، متجمّع لكل مورد</span></div></header><div class="grid g3" id="ret">${skeleton(3)}</div></section>`);
  let risk, exp, stock;
  try {
    const until = new Date(Date.now() + 366 * 864e5).toISOString().slice(0, 10);
    [risk, exp, stock] = await Promise.all([
      api.select('v_expiry_risk', { order: 'at_risk_value.desc', limit: 60 }),
      api.select('v_expiring', { order: 'expiry' }),
      api.select('v_stock', { select: 'expiry,cost_value,counts_as_stock', qty_units: 'gt.0', expiry: 'lte.' + until, counts_as_stock: 'eq.true' }),
    ]);
  } catch (e) { return render($('#k', el), errorBox(e)); }
  const total = risk.reduce((s, r) => s + Number(r.at_risk_value), 0);
  const red = exp.filter((r) => r.level === 'red' || r.level === 'expired');
  const expired = exp.filter((r) => r.level === 'expired');
  render($('#k', el), h`
    <div class="card kpi hero"><div class="l">${icon('hourglass')} فلوس في خطر</div><div class="v">${moneyR(total)}<small>ج</small></div><div class="f">${risk.length} تشغيلة مش هتلحق تتباع بالسرعة دي</div></div>
    <div class="card kpi"><div class="l">${icon('alert')} أقل من شهر</div><div class="v">${int(red.length)}<small>تشغيلة</small></div><div class="f">${expired.length ? h`<span class="pill p-bad">${expired.length} خلصت فعلًا</span> مابتتباعش` : 'مفيش حاجة خلصت'}</div></div>
    <div class="card kpi"><div class="l">${icon('clock')} قرّبت تخلص</div><div class="v">${int(exp.length)}<small>تشغيلة</small></div><div class="f">صلاحيتها في حدود ${(state.settings && state.settings.near_expiry_days) || 90} يوم</div></div>`);

  render($('#risk', el), risk.length ? h`${risk.map((r) => h`<tr class="click" data-id="${r.item_id}">
      <td class="name"><b>${r.name_ar || r.name_en}</b><span class="en">${r.name_en} · ${r.location}</span></td>
      <td><span class="pill ${r.days_left <= 30 ? 'p-bad' : r.days_left <= 90 ? 'p-warn' : 'p-muted'}">${dateMY(r.expiry)}</span><div class="muted" style="font-size:12px">${inDays(r.days_left)}</div></td>
      <td class="n">${num(r.qty_units)}</td>
      <td class="n">${num(Number(r.qty_units) - Number(r.at_risk_units))}<div class="muted" style="font-size:12px">${Number(r.daily_rate) ? num(r.daily_rate) + ' في اليوم' : 'مابيتباعش'}</div></td>
      <td class="n"><b style="color:var(--bad)">${money(r.at_risk_value)}</b><div class="muted" style="font-size:12px">${num(r.at_risk_units)} وحدة</div></td></tr>`)}`
    : h`<tr><td colspan="5">${empty('مفيش حاجة في خطر', 'كل اللي في المخزن هيتباع قبل صلاحيته بسرعة البيع الحالية')}</td></tr>`);
  $('#risk', el).addEventListener('click', (e) => { const r = e.target.closest('tr[data-id]'); if (r) location.hash = '#/items/' + r.dataset.id; });

  // شهور الصلاحية
  const now = new Date(), months = [];
  for (let i = 0; i < 12; i++) months.push(new Date(now.getFullYear(), now.getMonth() + i, 1));
  const vals = months.map(() => 0);
  for (const s of stock) {
    if (!s.expiry) continue;
    const d = toDate(s.expiry), idx = (d.getFullYear() - now.getFullYear()) * 12 + d.getMonth() - now.getMonth();
    if (idx >= 0 && idx < 12) vals[idx] += Number(s.cost_value || 0);
  }
  const labels = months.map((m) => new Intl.DateTimeFormat('ar-EG-u-nu-latn', { month: 'short' }).format(m));
  const c = bars($('#months', el), { labels, values: vals, name: 'قيمة بتنتهي', label: (i) => dateMY(months[i]) });

  // المرتجع لكل مورد
  const by = new Map();
  for (const r of red) { const k = r.supplier_id || 0; const g = by.get(k) || { name: r.supplier || 'من غير مورد معروف', rows: [] }; g.rows.push(r); by.set(k, g); }
  let phones = {};
  try { const sups = await api.select('suppliers', { select: 'id,phone', id: 'in.(' + [...by.keys()].filter(Boolean).join(',') + ')' }); phones = Object.fromEntries(sups.map((s) => [s.id, s.phone])); } catch (e) {}
  const groups = [...by.entries()];
  render($('#ret', el), groups.length ? h`${groups.map(([sid, g]) => {
    const msg = `السلام عليكم، معانا أصناف صلاحيتها قرّبت ومحتاجين نرجّعها:\n` + g.rows.map((r) => `- ${r.name_en}: ${num(r.packs)} علبة${Number(r.units) ? ' و' + num(r.units) + ' شريط' : ''} (صلاحية ${r.expiry.slice(0, 7)})`).join('\n') + `\nياريت تبلغنا ميعاد المندوب. شكرًا`;
    return h`<div class="card" style="box-shadow:none;background:var(--card-2)"><header><h2>${g.name}</h2><span class="pill p-bad">${g.rows.length} صنف</span></header>
      <div class="list">${g.rows.slice(0, 6).map((r) => h`<div class="li"><div class="grow"><b>${r.name_ar || r.name_en}</b><span class="muted" style="font-size:12px">${qty(Number(r.packs) * 1, 1, 'علبة')}${Number(r.units) ? ' و' + num(r.units) + ' شريط' : ''}</span></div><span class="pill ${r.level === 'expired' ? 'p-bad' : 'p-warn'}">${r.level === 'expired' ? 'خلصت' : inDays(r.days_left)}</span></div>`)}</div>
      <div class="row" style="margin-top:12px"><button class="btn sm ghost" data-copy="${sid}">${icon('copy')} انسخ الرسالة</button>
        <a class="btn sm quiet" target="_blank" rel="noopener" href="${waLink(phones[sid], msg)}">${icon('whatsapp')} افتح واتساب</a></div>
      <textarea hidden data-msg="${sid}">${msg}</textarea></div>`;
  })}` : empty('مفيش مرتجع', 'مفيش حاجة صلاحيتها أقل من شهر'));
  $('#ret', el).addEventListener('click', (e) => { const b = e.target.closest('[data-copy]'); if (b) copyText($(`[data-msg="${b.dataset.copy}"]`, el).value); });
  return c;
}
