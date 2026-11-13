// الإعدادات والتجربة: سلامة القاعدة، ملاحظات التجربة، الموظفين والصلاحيات، يوزر البوت ومفتاحه، والنقل من فارمافلاي.
import { h, render, $, $$, icon, money, int, dateTime, ago, skeleton, errorBox, empty, toast, modal, copyText, confirmBox } from '../ui.js';
import { colorDialog } from '../app.js';

const ROLE_AR = { owner: 'المالك', manager: 'مدير', pharmacist: 'صيدلي', cashier: 'كاشير', delivery: 'دليفري', bot: 'البوت' };
const SEV = { blocker: ['واقف', 'p-bad'], bug: ['غلط', 'p-warn'], annoyance: ['مزعج', 'p-info'], idea: ['فكرة', 'p-gold'] };
const AREA = { sales: 'البيع', purchases: 'الشرا', stock: 'المخزن', accounts: 'الحسابات', reports: 'التقارير', import: 'النقل', install: 'التسطيب', bot: 'البوت', other: 'تاني' };
const ISSUE_AR = { sold_without_stock: 'اتباع من غير رصيد في فارمافلاي', sold_expired: 'اتباع منتهي في فارمافلاي', over_limit: 'عميل عدّى حده', missing_numbers: 'أرقام فواتير ناقصة', stock_reconciled: 'رصيد اتظبط على الحالي', balance_reconciled: 'حساب اتظبط على الحالي' };

export default async function settings({ el, api, state, can }) {
  const owner = can(['owner']);
  render(el, h`
    <div class="head"><div><h1>الإعدادات والتجربة</h1><p>كل حاجة بتتقاس: سلامة القاعدة، المشاكل اللي اتسجلت، ومين بيدخل بإيه.</p></div></div>
    <section class="grid g2">
      <div class="card"><header><div><h2>سلامة القاعدة</h2><span class="sub">10 قواعد لازم تفضل صح مهما حصل</span></div><button class="btn sm quiet" id="hc" data-hot="alt+h">${icon('refresh')} افحص <kbd>Alt+H</kbd></button></header><div class="list" id="health">${skeleton(5)}</div></div>
      <div class="card"><header><div><h2>ملاحظات التجربة</h2><span class="sub">اللي اتسجل من الشاشات أو من المحادثة</span></div><span id="ncount"></span></header><div class="list" id="notes">${skeleton(5)}</div></div>
    </section>
    ${owner ? h`<section class="card" style="margin-top:16px"><header><div><h2>الموظفين والصلاحيات</h2><span class="sub">كل واحد بيشوف ويعمل اللي دوره يسمح بيه بس (من القاعدة نفسها)</span></div><button class="btn sm" id="add" data-hot="alt+a">${icon('plus')} موظف جديد <kbd style="background:transparent;color:var(--on-c-2)">Alt+A</kbd></button></header><div id="staff">${skeleton(4)}</div></section>` : ''}
    <section class="grid g2" style="margin-top:16px">
      <div class="card"><header><div><h2>بيانات الصيدلية</h2></div></header><form class="stack" id="sf"></form>
        <div class="row between" style="margin-top:14px;padding-top:14px;border-top:1px solid var(--line-2)"><div><b>ألوان البرنامج</b><div class="muted" style="font-size:13px">نفس ألوان البوت والموقع، والليلي. على الجهاز ده</div></div>
          <button class="btn ghost sm" id="colors" type="button" data-hot="alt+k">${icon('sparkle')} الألوان <kbd>Alt+K</kbd></button></div></div>
      <div class="card"><header><div><h2>النقل من فارمافلاي</h2><span class="sub">التاريخ من 2018 بأرقامه وتواريخه الأصلية</span></div></header><div id="imp">${skeleton(4)}</div></div>
    </section>`);

  async function health() {
    const box = $('#health', el); render(box, skeleton(5));
    try {
      const rows = await api.rpc('health_check');
      render(box, h`${rows.map((r) => h`<div class="li"><span class="ico ${r.ok ? 'i-good' : 'i-bad'}">${icon(r.ok ? 'check' : 'alert')}</span><div class="grow"><b>${r.check_name}</b>${!r.ok && r.detail ? h`<span class="muted" style="font-size:13px">${r.detail}</span>` : ''}</div><span class="pill ${r.ok ? 'p-good' : 'p-bad'}">${r.ok ? 'سليم' : 'مشكلة'}</span></div>`)}`);
    } catch (e) { render(box, errorBox(e)); }
  }
  async function notes() {
    const box = $('#notes', el);
    try {
      const rows = await api.select('trial_notes', { order: 'status.desc,at.desc', limit: 30 });
      const open = rows.filter((r) => r.status === 'open');
      $('#ncount', el).innerHTML = String(h`<span class="pill ${open.length ? 'p-warn' : 'p-good'}">${open.length} مفتوحة</span>`);
      render(box, rows.length ? h`${rows.map((r) => h`<div class="li" data-row style="align-items:flex-start;opacity:${r.status === 'open' ? 1 : 0.55}">
        <span class="pill ${SEV[r.severity][1]}">${SEV[r.severity][0]}</span>
        <div class="grow"><b style="font-weight:500">${r.note}</b><span class="muted" style="font-size:12px">${AREA[r.area] || r.area} · ${ago(r.at)}${r.fixed_note ? ' · اتصلح: ' + r.fixed_note : ''}</span></div>
        ${r.status === 'open' && can(['owner', 'manager']) ? h`<button class="btn sm quiet" data-fix="${r.id}" data-key="f" title="علّمها اتصلحت">${icon('check')} اتصلحت <kbd>F</kbd></button>` : ''}</div>`)}` : empty('مفيش ملاحظات', 'استخدم زرار «سجّل ملاحظة» تحت في أي شاشة'));
    } catch (e) { render(box, errorBox(e)); }
  }
  $('#notes', el).addEventListener('click', async (e) => {
    const b = e.target.closest('[data-fix]'); if (!b) return;
    const m = modal({ title: 'اتصلحت إزاي؟', body: h`<input class="input" id="fx" placeholder="مثلاً: اتصلحت في تعديل 202611140930" autofocus>`, footer: h`<button class="btn quiet" data-close>إلغاء</button><button class="btn ok" id="go">قفلها</button>` });
    $('#go', m.el).addEventListener('click', async () => {
      try { await api.update('trial_notes', { id: 'eq.' + b.dataset.fix }, { status: 'fixed', fixed_note: $('#fx', m.el).value || null, fixed_at: new Date().toISOString() }); m.close(); notes(); }
      catch (er) { toast(er.message, 'bad'); }
    });
  });
  $('#hc', el).addEventListener('click', health);

  async function staff() {
    const box = $('#staff', el); if (!box) return;
    try {
      const rows = await api.select('v_staff', { order: 'role,name' });
      render(box, h`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>الاسم</th><th>اسم الدخول</th><th>الدور</th><th>آخر دخول</th><th></th></tr></thead><tbody>
        ${rows.map((r) => h`<tr data-row><td><b>${r.name}</b> ${r.active ? '' : h`<span class="pill p-muted">موقوف</span>`} ${r.locked_until && new Date(r.locked_until) > new Date() ? h`<span class="pill p-bad">مقفول مؤقتًا</span>` : ''}</td>
          <td class="ltr" style="text-align:right">${r.username}</td><td><span class="pill ${r.role === 'bot' ? 'p-info' : r.role === 'owner' ? 'p-gold' : 'p-muted'} plain">${r.role === 'bot' ? icon('bot', 'icon-sm') : ''} ${ROLE_AR[r.role] || r.role}</span></td>
          <td>${r.last_login_at ? ago(r.last_login_at) : '—'}</td>
          <td class="row" style="justify-content:flex-end">${r.kind === 'bot' ? h`<button class="btn sm" data-token="${r.username}" data-key="k" title="مفتاح جديد للبوت">${icon('key')} مفتاح جديد <kbd style="background:transparent;color:var(--on-c-2)">K</kbd></button>` : h`<button class="btn sm quiet" data-pw="${r.username}" data-key="w" title="كلمة سر جديدة">كلمة سر <kbd>W</kbd></button>`}
            ${r.role !== 'owner' ? h`<button class="btn sm quiet" data-revoke="${r.username}" data-key="l" title="اقفل جلساته (يخرج من كل الأجهزة)">اقفل جلساته <kbd>L</kbd></button>` : ''}</td></tr>`)}</tbody></table></div>`);
    } catch (e) { render(box, errorBox(e)); }
  }
  if (owner) {
    $('#staff', el).addEventListener('click', async (e) => {
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.token) {
        if (!(await confirmBox('مفتاح جديد للبوت', 'هيطلع مفتاح جديد صالح سنة. المفاتيح القديمة هتفضل شغالة لحد ما تقفل جلساته. المفتاح بيظهر مرة واحدة بس.', 'اعمل مفتاح'))) return;
        try {
          const r = await api.rpc('issue_bot_token', { p_username: b.dataset.token, p_days: 365 });
          const m = modal({ title: 'مفتاح البوت', body: h`<div class="stack"><p style="margin:0">انسخه وحطه في إعدادات البوت على الجهاز. <b>مش هيظهر تاني</b>، ومايتبعتش في شات ولا يترفع على GitHub.</p>
            <textarea class="input ltr" rows="4" readonly style="font-family:var(--f-mono);font-size:12px">${r.token}</textarea><p class="muted" style="margin:0">صالح لحد ${dateTime(r.expires_at)}</p></div>`,
            footer: h`<button class="btn" id="cp">${icon('copy')} انسخ</button>` });
          $('#cp', m.el).addEventListener('click', () => copyText(r.token));
        } catch (er) { toast(er.message, 'bad'); }
      } else if (b.dataset.revoke) {
        if (!(await confirmBox('اقفل كل جلساته', `${b.dataset.revoke} هيخرج من كل الأجهزة وكل مفاتيحه القديمة هتبطل.`, 'اقفل', true))) return;
        try { await api.rpc('revoke_tokens', { p_username: b.dataset.revoke }); toast('اتقفلت ✓', 'good'); } catch (er) { toast(er.message, 'bad'); }
      } else if (b.dataset.pw) {
        const m = modal({ title: 'كلمة سر جديدة لـ ' + b.dataset.pw, body: h`<input class="input ltr" id="np" type="password" minlength="8" placeholder="8 حروف على الأقل" autofocus>`, footer: h`<button class="btn quiet" data-close>إلغاء</button><button class="btn" id="go">غيّر</button>` });
        $('#go', m.el).addEventListener('click', async () => { try { await api.rpc('set_password', { p_username: b.dataset.pw, p_new: $('#np', m.el).value }); m.close(); toast('اتغيرت ✓', 'good'); } catch (er) { toast(er.message, 'bad'); } });
      }
    });
    $('#add', el).addEventListener('click', () => {
      const m = modal({ title: 'موظف جديد', body: h`<div class="stack">
          <div class="field"><label>الاسم</label><input class="input" id="nn" autofocus></div>
          <div class="field"><label>اسم الدخول (إنجليزي)</label><input class="input ltr" id="nu" pattern="[a-z0-9_.]{3,30}"></div>
          <div class="field"><label>الدور</label><select class="input" id="nr"><option value="cashier">كاشير: البيع بس</option><option value="pharmacist">صيدلي: البيع والمخزن والعملاء</option><option value="manager">مدير: كل حاجة إلا الموظفين</option><option value="delivery">دليفري</option><option value="bot">بوت (من غير كلمة سر، بمفتاح)</option></select></div>
          <div class="field" id="pwf"><label>كلمة السر</label><input class="input ltr" id="np" type="password" minlength="8"></div></div>`,
        footer: h`<button class="btn quiet" data-close>إلغاء</button><button class="btn" id="go">ضيف</button>` });
      $('#nr', m.el).addEventListener('change', (e) => { $('#pwf', m.el).hidden = e.target.value === 'bot'; });
      $('#go', m.el).addEventListener('click', async () => {
        try { await api.rpc('create_user', { p_username: $('#nu', m.el).value.trim(), p_password: $('#np', m.el).value || null, p_name: $('#nn', m.el).value.trim(), p_role: $('#nr', m.el).value }); m.close(); toast('اتضاف ✓', 'good'); staff(); }
        catch (er) { toast(er.message, 'bad'); }
      });
    });
  }

  // بيانات الصيدلية
  const st = state.settings || {};
  render($('#sf', el), h`
    <div class="field"><label>اسم الصيدلية (على الإيصال وفوق)</label><input class="input" id="pn" value="${st.pharmacy_name || ''}" ${owner ? '' : 'disabled'}></div>
    <div class="field"><label>«قرّب يخلص» = صلاحيته في خلال كام يوم</label><input class="input num" id="ne" type="number" min="7" max="730" value="${st.near_expiry_days || 90}" ${owner ? '' : 'disabled'}></div>
    <div class="row between"><span class="muted" style="font-size:13px">اليوم بيبدأ الساعة ${st.day_starts_at ?? 6} الصبح · ${st.time_zone || 'Africa/Cairo'}</span>${owner ? h`<button class="btn sm" id="ss" type="button" data-hot="alt+s">احفظ <kbd style="background:transparent;color:var(--on-c-2)">Alt+S</kbd></button>` : ''}</div>`);
  $('#colors', el).addEventListener('click', colorDialog);
  const ss = $('#ss', el);
  if (ss) ss.addEventListener('click', async () => {
    try { const [r] = await api.update('settings', { id: 'eq.1' }, { pharmacy_name: $('#pn', el).value.trim(), near_expiry_days: +$('#ne', el).value }); state.settings = r; toast('اتحفظ ✓', 'good'); }
    catch (e) { toast(e.message, 'bad'); }
  });

  // النقل
  (async () => {
    const box = $('#imp', el);
    try {
      const [runs, issues] = await Promise.all([api.select('import_runs', { order: 'started_at.desc', limit: 3 }), api.select('import_issues', { select: 'kind', limit: 5000 })]);
      const counts = {}; issues.forEach((i) => { counts[i.kind] = (counts[i.kind] || 0) + 1; });
      const last = runs[0];
      render(box, last ? h`<div class="li"><span class="ico i-good">${icon('check')}</span><div class="grow"><b>آخر نقل ${dateTime(last.finished_at || last.started_at)}</b><span class="muted" style="font-size:13px">${last.source || ''}</span></div></div>
        ${last.summary ? h`<div class="chips" style="margin:10px 0">${Object.entries(last.summary).filter(([, v]) => typeof v === 'number').slice(0, 8).map(([k, v]) => h`<span class="pill p-muted plain">${k}: ${int(v)}</span>`)}</div>` : ''}
        <h3 style="font-size:14px;margin:12px 0 4px">ملاحظات النقل (للمراجعة، مش أخطاء)</h3>
        <div class="list">${Object.entries(counts).map(([k, v]) => h`<div class="li"><div class="grow">${ISSUE_AR[k] || k}</div><b>${int(v)}</b></div>`)}</div>` : empty('لسه مااتنقلش حاجة', 'شوف docs/migration.md'));
    } catch (e) { render(box, errorBox(e)); }
  })();

  health(); notes(); staff();
}
