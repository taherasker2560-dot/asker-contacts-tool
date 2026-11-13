// كود البوت بنفس المكتبة اللي بيستخدمها دلوقتي (supabase-js)، بس العنوان عنوان البرنامج اللي في الصيدلية ومفتاح يوزر البوت.
// الاستخدام: NODE_PATH=<فيه @supabase/supabase-js> ASKER_URL=http://… BOT_TOKEN=… node tests/bot-client.cjs
'use strict';
const { createClient } = require('@supabase/supabase-js');
(async () => {
  const db = createClient(process.env.ASKER_URL, 'local', {
    db: { schema: 'ph' },
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: 'Bearer ' + process.env.BOT_TOKEN } }
  });
  const sh = await db.from('v_shortages').select('item_id,order_packs');
  const ins = await db.from('supplier_offers').insert({ supplier_id: 10000, item_id: 1259, source: 'whatsapp', discount_pct: 27, raw_text: 'من supabase-js' });
  const cust = await db.from('customers').select('id');
  const best = await db.from('v_best_offer').select('best_pct').eq('item_id', 1259);
  console.log(JSON.stringify({
    shortages: sh.error ? sh.error.message : sh.data,
    insert: ins.error ? ins.error.message : ins.status,
    customers: cust.error ? cust.error.message : cust.data.length,
    best: best.error ? best.error.message : best.data
  }));
})();
