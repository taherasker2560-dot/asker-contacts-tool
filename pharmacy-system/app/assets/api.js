// الاتصال بالقاعدة: نفس عنوان Supabase (/rest/v1) عن طريق Caddy → PostgREST.
// كل حاجة بتعدّي على صلاحيات القاعدة نفسها (RLS + دوال الترحيل)، الشاشة مابتقررش حاجة لوحدها.
const BASE = '/rest/v1';
const KEY = 'asker.session';
const OUTBOX = 'asker.outbox';

export const session = {
  get() { try { return JSON.parse(localStorage.getItem(KEY)) || null; } catch (e) { return null; } },
  set(s) { try { localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) {} },
  clear() { try { localStorage.removeItem(KEY); } catch (e) {} },
};

export class ApiError extends Error {
  constructor(status, body) {
    super(humanize(body, status));
    this.status = status; this.body = body; this.code = body && body.code;
  }
}

// رسايل القاعدة بالعربي أصلًا (raise exception). الباقي نترجمه لكلام مفهوم.
function humanize(body, status) {
  if (!body) return status === 0 ? 'مفيش اتصال بالسيرفر' : 'حصلت مشكلة (' + status + ')';
  const m = body.message || body.error || '';
  if (body.error && /[\u0600-\u06FF]/.test(body.error)) return body.error;   // الدخول: «كلمة السر غلط» / «الحساب مقفول»
  if (status === 401 || /JWT|jwt/.test(m)) return 'انتهت الجلسة: ادخل تاني';
  if (body.code === '42501' || /permission denied|ليس لديك|مش مسموح/.test(m)) return m && /[؀-ۿ]/.test(m) ? m : 'مش مسموح لك بالعملية دي';
  if (/[؀-ۿ]/.test(m)) return m;
  if (/duplicate key/.test(m)) return 'الحاجة دي متسجلة قبل كده';
  if (/violates check constraint/.test(m)) return 'في قيمة مش مقبولة';
  return m || 'حصلت مشكلة (' + status + ')';
}

let onUnauthorized = () => {};
export function setUnauthorizedHandler(fn) { onUnauthorized = fn; }

async function request(method, path, { body, headers = {}, signal } = {}) {
  const s = session.get();
  const h = { 'Content-Type': 'application/json', Accept: 'application/json', ...headers };
  if (s && s.token) h.Authorization = 'Bearer ' + s.token;
  let res;
  try {
    res = await fetch(BASE + path, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body), signal });
  } catch (e) {
    if (e.name === 'AbortError') throw e;
    throw new ApiError(0, null);
  }
  const text = await res.text();
  let data = null;
  if (text) { try { data = JSON.parse(text); } catch (e) { data = { message: text }; } }
  if (!res.ok) {
    const err = new ApiError(res.status, data);
    if (res.status === 401 && path !== '/rpc/login') onUnauthorized(err);
    throw err;
  }
  return data;
}

// select('v_stock', {item_id: 'eq.5', order: 'expiry.asc', limit: 50})
export function select(table, params = {}, opts = {}) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== null && v !== '') q.append(k, v);
  const qs = q.toString();
  return request('GET', '/' + table + (qs ? '?' + qs : ''), opts);
}
export async function one(table, params = {}) {
  const rows = await select(table, { ...params, limit: 1 });
  return rows && rows[0] || null;
}
export function rpc(fn, args = {}, opts = {}) { return request('POST', '/rpc/' + fn, { body: args, ...opts }); }
export function insert(table, row) { return request('POST', '/' + table, { body: row, headers: { Prefer: 'return=representation' } }); }
export function update(table, match, patch) {
  const q = new URLSearchParams(match).toString();
  return request('PATCH', '/' + table + '?' + q, { body: patch, headers: { Prefer: 'return=representation' } });
}

export async function login(username, password) {
  const r = await rpc('login', { username, password });
  session.set({ token: r.token, name: r.name, role: r.role, username: r.username, expires_at: r.expires_at });
  return r;
}

export function uuid() {
  if (crypto.randomUUID) return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16)); b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

// ---------------------------------------------------------------- صندوق الصادر (البيع وقت انقطاع الشبكة)
// الفاتورة بتتحفظ بالـ client_uuid بتاعها. لما الشبكة ترجع بتتبعت تاني، والقاعدة مابتسجلهاش مرتين أبدًا.
export const outbox = {
  all() { try { return JSON.parse(localStorage.getItem(OUTBOX)) || []; } catch (e) { return []; } },
  save(list) { try { localStorage.setItem(OUTBOX, JSON.stringify(list)); } catch (e) {} },
  push(payload) { const l = outbox.all(); l.push({ payload, at: Date.now() }); outbox.save(l); },
  async flush() {
    const l = outbox.all(); if (!l.length) return { sent: 0, left: 0 };
    const left = []; let sent = 0;
    for (const it of l) {
      try { await rpc('post_sale', { p: it.payload }); sent++; }
      catch (e) { if (e.status === 0) left.push(it); else { left.push({ ...it, error: e.message }); } }
    }
    outbox.save(left);
    return { sent, left: left.length };
  },
};
