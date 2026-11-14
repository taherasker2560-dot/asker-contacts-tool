/* ألوان البرنامج والوضع الليلي: نفس اختيارات البوت والموقع بالظبط (asker-nawaqes: ar/settings.js و store/theme.js).
   «أزرق عسكر» (أزرق اللوجو) هو الأساسي، و24 لون جاهز تانيين (منهم «عنابي» القرمزي)، و«لون من اختيارك»، والليلي مع أي لون.
   كل لون بيطلع منه نفس الدرجات اللي البوت بيحسبها (palette)، فالبرنامج والبوت والموقع شكلهم واحد.
   الاختيار محفوظ على الجهاز ده (زي البوت)، والليلي بس لما يتختار (مش من إعداد الويندوز).
   بيتحمّل في <head> قبل ما الصفحة ترسم، فاللون صح من أول لحظة. */
(function (root) {
  'use strict';
  const PRESETS = [
    ['asker', 'أزرق عسكر', '#0a4aa6'], ['crimson', 'عنابي', '#7d1028'], ['red', 'أحمر', '#b3261e'], ['rose', 'وردي', '#c2185b'], ['fuchsia', 'فوشيا', '#a3127a'],
    ['purple', 'بنفسجي', '#5b3a8c'], ['violet', 'موف غامق', '#4527a0'], ['indigo', 'نيلي', '#283593'], ['blue', 'أزرق', '#1d4f91'],
    ['sky', 'لبني', '#0277bd'], ['cyan', 'سماوي', '#00838f'], ['teal', 'تركواز', '#0e6b72'], ['emerald', 'زمردي', '#00796b'],
    ['green', 'أخضر', '#1d6f48'], ['leaf', 'أخضر زرعي', '#2e7d32'], ['olive', 'زيتوني', '#556b2f'], ['lime', 'ليموني غامق', '#827717'],
    ['gold', 'دهبي', '#9a7414'], ['orange', 'برتقالي', '#a8501a'], ['flame', 'برتقالي فاقع', '#d84315'], ['copper', 'نحاسي', '#8d4e2a'],
    ['brown', 'بني', '#5d4037'], ['gray', 'رمادي', '#3f4650'], ['slate', 'رصاصي', '#455a64'], ['charcoal', 'فحمي', '#263238'],
  ].map(([id, name, hex]) => ({ id, name, hex }));
  const KEY = 'asker.accent', NIGHT = 'asker.theme';

  // ---------- الحسبة نفسها بتاعة البوت (ar/settings.js) ----------
  function hexToRgb(h) { const m = /^#?([0-9a-f]{6})$/i.exec(String(h || '').trim()); if (!m) return null; const n = parseInt(m[1], 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
  function rgbToHex(r, g, b) { return '#' + [r, g, b].map((x) => Math.max(0, Math.min(255, Math.round(x))).toString(16).padStart(2, '0')).join(''); }
  function rgbToHsl(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2;
    let h = 0, s = 0;
    if (mx !== mn) {
      const d = mx - mn;
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
      h /= 6;
    }
    return [h * 360, s * 100, l * 100];
  }
  function hslToHex(h, s, l) {
    h = ((h % 360) + 360) % 360 / 360; s = Math.max(0, Math.min(100, s)) / 100; l = Math.max(0, Math.min(100, l)) / 100;
    if (!s) return rgbToHex(l * 255, l * 255, l * 255);
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
    const f = (t) => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; };
    return rgbToHex(f(h + 1 / 3) * 255, f(h) * 255, f(h - 1 / 3) * 255);
  }
  function lum(hex) { const c = hexToRgb(hex).map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; }
  function contrast(a, b) { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }
  function palette(hex, night) {
    const rgb = hexToRgb(hex) || hexToRgb('#0a4aa6');
    let [h, s, l] = rgbToHsl(rgb[0], rgb[1], rgb[2]);
    let main = hslToHex(h, s, l);
    while (contrast(main, '#ffffff') < 4.6 && l > 4) { l -= 2; main = hslToHex(h, s, l); }
    const deep = hslToHex(h, s, Math.max(l - 13, 6));
    if (night) return { main, deep, ink: hslToHex(h, Math.min(s, 80), 80), soft: hslToHex(h, Math.min(s, 30), 19), line: hslToHex(h, Math.min(s, 22), 30), tint: hslToHex(h, Math.min(s, 28), 7), tint2: hslToHex(h, Math.min(s, 22), 12), hue: h };
    let il = Math.min(l - 4, 32), ink = hslToHex(h, s, il);
    while (contrast(ink, '#fbf8f8') < 7 && il > 4) { il -= 2; ink = hslToHex(h, s, il); }
    return { main, deep, ink, soft: hslToHex(h, Math.min(s, 55), 95), line: hslToHex(h, Math.min(s, 40), 86), tint: hslToHex(h, Math.min(s, 45), 97), tint2: hslToHex(h, Math.min(s, 40), 93), hue: h };
  }

  // ---------- الاختيار المحفوظ على الجهاز ----------
  const read = (k, d) => { try { const v = localStorage.getItem(k); return v == null ? d : v; } catch (e) { return d; } };
  const write = (k, v) => { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { /* شباك خاص */ } };
  function choice() {
    const a = read(KEY, 'asker'), night = read(NIGHT, '') === 'dark';
    const p = PRESETS.find((x) => x.id === a);
    const hex = p ? p.hex : /^c:#[0-9a-f]{6}$/i.test(a) ? a.slice(2) : PRESETS[0].hex;
    return { id: p ? p.id : /^c:/.test(a) ? 'custom' : 'asker', hex, night };
  }
  function apply() {
    const c = choice(), t = palette(c.hex, c.night), el = document.documentElement, st = el.style;
    st.setProperty('--c-main', t.main);
    st.setProperty('--c-deep', t.deep);
    st.setProperty('--c-ink', t.ink);
    st.setProperty('--c-soft', t.soft);
    st.setProperty('--c-line', t.line);
    st.setProperty('--c-tint', t.tint);
    st.setProperty('--c-tint2', t.tint2);
    st.setProperty('--glow', hexToRgb(t.main).join(', '));
    // اللون التاني في الرسوم: دهبي، إلا لو اللون نفسه دهبي/برتقالي ← أزرق عسكر
    const warm = t.hue >= 20 && t.hue <= 70;
    st.setProperty('--s2-base', warm ? '#2f6fd0' : '#b8862b');
    el.dataset.accent = c.id;
    el.dataset.theme = c.night ? 'dark' : 'light';
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', c.night ? t.tint : t.main);
    return c;
  }
  function setAccent(id) { write(KEY, id === 'asker' ? null : id); return apply(); }
  function setNight(on) { write(NIGHT, on ? 'dark' : null); return apply(); }
  root.AskerTheme = { PRESETS, palette, contrast, choice, apply, setAccent, setNight };
  if (typeof document !== 'undefined') apply();   // قبل ما الصفحة ترسم
})(typeof window === 'undefined' ? globalThis : window);
