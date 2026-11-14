// رسوم خفيفة من غير مكتبات: SVG بيترسم على مقاس الكارت، وتلميح عند المرور على أي عمود.
// القواعد (dataviz): لون ثابت لكل سلسلة، أعمدة رفيعة بأطراف مدورة 4px على خط الصفر، فاصل 2px، خط 2px،
// مفتاح ألوان لما يكون فيه سلسلتين، محور واحد بس، والأرقام بلون الكلام مش لون السلسلة.
import { money, esc } from './ui.js';

const NS = 'http://www.w3.org/2000/svg';

function niceMax(v) {
  if (v <= 0) return 1;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  const n = v / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p;
}
function short(v) {
  if (Math.abs(v) >= 1e6) return (v / 1e6).toFixed(v >= 1e7 ? 0 : 1).replace(/\.0$/, '') + 'م';
  if (Math.abs(v) >= 1e3) return (v / 1e3).toFixed(v >= 1e4 ? 0 : 1).replace(/\.0$/, '') + 'ك';
  return String(Math.round(v));
}
// عمود بطرف مدور من فوق بس (الطرف اللي فيه القيمة)، وقاعدته مستقيمة على خط الصفر
function barPath(x, y, w, h, r = 4) {
  if (h <= 0) return '';
  r = Math.min(r, w / 2, h);
  return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
}

function mount(el, draw) {
  el.classList.add('chart');
  let tip = el.querySelector('.tip');
  const redraw = () => {
    const w = el.clientWidth || 600, hgt = el.clientHeight || 260;
    el.innerHTML = '';
    tip = document.createElement('div'); tip.className = 'tip'; tip.hidden = true;
    const svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', `0 0 ${w} ${hgt}`);
    svg.setAttribute('role', 'img');
    el.append(svg, tip);
    draw(svg, w, hgt, tip);
  };
  redraw();
  if ('ResizeObserver' in window) {
    let last = el.clientWidth;
    const ro = new ResizeObserver(() => { if (Math.abs(el.clientWidth - last) > 4) { last = el.clientWidth; redraw(); } });
    ro.observe(el);
    return () => ro.disconnect();
  }
  return () => {};
}
function svgEl(tag, attrs, parent) {
  const n = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
  if (parent) parent.appendChild(n);
  return n;
}
function showTip(tip, el, x, y, html) {
  tip.innerHTML = html; tip.hidden = false;
  const r = el.getBoundingClientRect();
  tip.style.left = Math.max(70, Math.min(r.width - 70, x)) + 'px';
  tip.style.top = Math.max(40, y) + 'px';
}

// أعمدة (السلسلة الأولى) + خط (السلسلة التانية) على نفس المحور. الترتيب من اليمين للشمال (عربي).
export function barLine(el, { labels, bars, line, barName, lineName, label = (i) => labels[i], rtl = true }) {
  return mount(el, (svg, W, H, tip) => {
    el.setAttribute('aria-label', `${barName} و${lineName}`);
    const padT = 10, padB = 26, padS = 40;
    const max = niceMax(Math.max(1, ...bars, ...line.filter((v) => v != null)));
    const plotW = W - padS - 8, plotH = H - padT - padB, n = labels.length;
    const step = plotW / n, bw = Math.max(4, Math.min(26, step * 0.56));
    const X = (i) => (rtl ? W - padS - (i + 0.5) * step : padS + (i + 0.5) * step);
    const Y = (v) => padT + plotH - (v / max) * plotH;
    for (let k = 0; k <= 4; k++) {
      const v = (max / 4) * k, y = Y(v);
      svgEl('line', { x1: rtl ? 8 : padS, x2: rtl ? W - padS : W - 8, y1: y, y2: y, class: 'grid-l' }, svg);
      svgEl('text', { x: rtl ? W - padS + 8 : padS - 8, y: y + 4, class: 'axis-t', 'text-anchor': rtl ? 'start' : 'end' }, svg).textContent = short(v);
    }
    const every = Math.ceil(n / Math.max(1, Math.floor(plotW / 44)));
    labels.forEach((l, i) => {
      if (i % every) return;
      svgEl('text', { x: X(i), y: H - 6, class: 'axis-t', 'text-anchor': 'middle' }, svg).textContent = l;
    });
    bars.forEach((v, i) => {
      const y = Y(v);
      svgEl('path', { d: barPath(X(i) - bw / 2, y, bw, padT + plotH - y), class: 's1' }, svg);
    });
    const pts = line.map((v, i) => (v == null ? null : [X(i), Y(v)]));
    let d = ''; pts.forEach((p, i) => { if (p) d += (d && pts[i - 1] ? 'L' : 'M') + p[0].toFixed(1) + ',' + p[1].toFixed(1); });
    svgEl('path', { d, class: 's2-line' }, svg);
    labels.forEach((l, i) => {
      const hit = svgEl('rect', { x: X(i) - step / 2, y: padT, width: step, height: plotH, class: 'hit' }, svg);
      hit.addEventListener('mouseenter', () => showTip(tip, el, X(i), Y(Math.max(bars[i], line[i] || 0)) - 4,
        `<b>${esc(label(i))}</b><br>${esc(barName)}: ${money(bars[i])}<br>${esc(lineName)}: ${line[i] == null ? '—' : money(line[i])}`));
      hit.addEventListener('mouseleave', () => { tip.hidden = true; });
    });
  });
}

// أعمدة متراكبة (سلسلتين: التكلفة تحت والربح فوق) بفاصل 2px بينهم
export function stacked(el, { labels, a, b, aName, bName, label = (i) => labels[i], rtl = true }) {
  return mount(el, (svg, W, H, tip) => {
    el.setAttribute('aria-label', `${aName} و${bName}`);
    const padT = 10, padB = 26, padS = 40;
    const max = niceMax(Math.max(1, ...a.map((v, i) => v + Math.max(0, b[i]))));
    const plotW = W - padS - 8, plotH = H - padT - padB, n = labels.length;
    const step = plotW / n, bw = Math.max(3, Math.min(22, step * 0.6));
    const X = (i) => (rtl ? W - padS - (i + 0.5) * step : padS + (i + 0.5) * step);
    const Y = (v) => padT + plotH - (v / max) * plotH;
    for (let k = 0; k <= 4; k++) {
      const v = (max / 4) * k, y = Y(v);
      svgEl('line', { x1: rtl ? 8 : padS, x2: rtl ? W - padS : W - 8, y1: y, y2: y, class: 'grid-l' }, svg);
      svgEl('text', { x: rtl ? W - padS + 8 : padS - 8, y: y + 4, class: 'axis-t', 'text-anchor': rtl ? 'start' : 'end' }, svg).textContent = short(v);
    }
    const every = Math.ceil(n / Math.max(1, Math.floor(plotW / 52)));
    labels.forEach((l, i) => { if (!(i % every)) svgEl('text', { x: X(i), y: H - 6, class: 'axis-t', 'text-anchor': 'middle' }, svg).textContent = l; });
    a.forEach((va, i) => {
      const vb = Math.max(0, b[i]);
      const ya = Y(va), hA = padT + plotH - ya;
      // السفلي من غير تدوير لو فوقه حاجة، والفاصل 2px بلون الكارت
      if (vb > 0) svgEl('rect', { x: X(i) - bw / 2, y: ya, width: bw, height: Math.max(0, hA), class: 's1' }, svg);
      else svgEl('path', { d: barPath(X(i) - bw / 2, ya, bw, hA), class: 's1' }, svg);
      if (vb > 0) {
        const yb = Y(va + vb), hB = ya - yb - 2;
        if (hB > 0) svgEl('path', { d: barPath(X(i) - bw / 2, yb, bw, hB), class: 's2' }, svg);
      }
      const hit = svgEl('rect', { x: X(i) - step / 2, y: padT, width: step, height: plotH, class: 'hit' }, svg);
      hit.addEventListener('mouseenter', () => showTip(tip, el, X(i), Y(va + vb) - 4,
        `<b>${esc(label(i))}</b><br>${esc(aName)}: ${money(va)}<br>${esc(bName)}: ${money(b[i])}`));
      hit.addEventListener('mouseleave', () => { tip.hidden = true; });
    });
  });
}

// أعمدة سلسلة واحدة (من غير مفتاح ألوان: العنوان بيقول هي إيه)
export function bars(el, { labels, values, name, label = (i) => labels[i], fmt = money, rtl = true, cls = 's1' }) {
  return mount(el, (svg, W, H, tip) => {
    el.setAttribute('aria-label', name);
    const padT = 10, padB = 26, padS = 40;
    const max = niceMax(Math.max(1, ...values));
    const plotW = W - padS - 8, plotH = H - padT - padB, n = labels.length;
    const step = plotW / n, bw = Math.max(4, Math.min(34, step * 0.56));
    const X = (i) => (rtl ? W - padS - (i + 0.5) * step : padS + (i + 0.5) * step);
    const Y = (v) => padT + plotH - (v / max) * plotH;
    for (let k = 0; k <= 4; k++) {
      const v = (max / 4) * k, y = Y(v);
      svgEl('line', { x1: rtl ? 8 : padS, x2: rtl ? W - padS : W - 8, y1: y, y2: y, class: 'grid-l' }, svg);
      svgEl('text', { x: rtl ? W - padS + 8 : padS - 8, y: y + 4, class: 'axis-t', 'text-anchor': rtl ? 'start' : 'end' }, svg).textContent = short(v);
    }
    const every = Math.ceil(n / Math.max(1, Math.floor(plotW / 48)));
    labels.forEach((l, i) => { if (!(i % every)) svgEl('text', { x: X(i), y: H - 6, class: 'axis-t', 'text-anchor': 'middle' }, svg).textContent = l; });
    values.forEach((v, i) => {
      const y = Y(v);
      svgEl('path', { d: barPath(X(i) - bw / 2, y, bw, padT + plotH - y), class: cls }, svg);
      const hit = svgEl('rect', { x: X(i) - step / 2, y: padT, width: step, height: plotH, class: 'hit' }, svg);
      hit.addEventListener('mouseenter', () => showTip(tip, el, X(i), y - 4, `<b>${esc(label(i))}</b><br>${esc(name)}: ${fmt(v)}`));
      hit.addEventListener('mouseleave', () => { tip.hidden = true; });
    });
  });
}

// خط صغير جوه كارت الرقم (اتجاه بس، من غير محاور). آخر نقطة عليها دايرة.
export function spark(el, values, { color = 'currentColor' } = {}) {
  const w = 110, h = 36, n = values.length;
  if (n < 2) { el.innerHTML = ''; return; }
  const max = Math.max(...values), min = Math.min(...values), span = max - min || 1;
  // من اليمين للشمال: أقدم يوم على اليمين
  const pts = values.map((v, i) => [w - 3 - (i / (n - 1)) * (w - 6), h - 4 - ((v - min) / span) * (h - 8)]);
  const d = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ',' + p[1].toFixed(1)).join('');
  const last = pts[n - 1];
  el.innerHTML = `<svg viewBox="0 0 ${w} ${h}" width="${w}" height="${h}" aria-hidden="true">
    <path d="${d}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" opacity=".9"/>
    <circle cx="${last[0]}" cy="${last[1]}" r="3.2" fill="${color}"/></svg>`;
}
