#!/usr/bin/env python3
"""نسخة فارمافلاي متولّدة (مش داتا الصيدلية) بنفس جداول وأعمدة pf_raw وبنفس القواعد اللي اتأكدت من النسخة الحقيقية
(MAPPING.md): SalesReturn 1/2، السطر = SalesPrice × (Packs + Units ÷ iParts)، تذاكر الصفر تحصيل بصنف 1، الخصم
بيتطرح من اللي العميل دفعه، CashFlow 9 دفع لمورد و 2 نسخة تانية من التحصيل و 4 تحصيل من غير تذكرة، الجرد في ItemCards
(5 و 6)، التليفون جوه الاسم، Items.barcode متكرر، والرصيد النهارده في Work و NewBalance (آخر تذكرة أو CashFlow 4). الأرصدة الصح بتتحسب هنا، فالنقل لازم يطابقها بالظبط.

الاستخدام:  python3 tests/pharmafly-fake.py [عدد الأيام] > fake.sql   ثم  psql <القاعدة> -f fake.sql
"""
import datetime as dt
import random
import sys

DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 120
R = random.Random(7)
START = dt.datetime.combine(dt.date.today() - dt.timedelta(days=DAYS), dt.time(9))
out = []


def q(v):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(round(v, 4)) if isinstance(v, float) else str(v)
    if isinstance(v, (dt.datetime, dt.date)):
        return "'" + v.isoformat(sep=' ') + "'" if isinstance(v, dt.datetime) else "'" + v.isoformat() + "'"
    return "'" + str(v).replace("'", "''") + "'"


def table(name, cols):
    out.append(f'create table pf_raw."{name}" (' + ', '.join(f'"{c}" {t}' for c, t in cols) + ');')


def rows(name, cols, data):
    for i in range(0, len(data), 500):
        chunk = data[i:i + 500]
        out.append(f'insert into pf_raw."{name}" (' + ', '.join(f'"{c}"' for c in cols) + ') values '
                   + ', '.join('(' + ', '.join(q(v) for v in r) + ')' for r in chunk) + ';')


out.append('drop schema if exists pf_raw cascade; create schema pf_raw;')
B, F, T, BO, X = 'bigint', 'double precision', 'timestamp', 'boolean', 'text'
table('Stores', [('ID', B), ('Name', X), ('Hidden', BO)])
rows('Stores', ['ID', 'Name', 'Hidden'], [(1, 'Main - افتراضى', False), (2, 'مخزن هالك ومنتهى الصلاحية', True),
                                          (5, 'مخزن انتظار ابن سينا', False), (6, 'مخزن انتظار فارما', False), (7, 'مخزن انتظار سوفيكو', False)])
table('Categories', [('id', B), ('name', X), ('IsActive', BO)])
rows('Categories', ['id', 'name', 'IsActive'], [(1, 'ادوية', True), (2, 'مستحضرات', True), (3, 'مستلزمات', True)])

# الأصناف: 1 = «أصناف متنوعة». Items.barcode = 999 متكرر على أغلبهم (زي الحقيقي)، وكام واحد ليه باركود لوحده
items = {1: dict(parts=1, price=0.0, cost=0.0)}
irows = [(1, 'أصناف متنوعة', None, 1, 0.0, 0.0, 999, 3, True, False, False, False)]
for i in range(2, 202):
    parts = R.choice([1, 1, 2, 3, 10])
    price = float(R.randint(15, 300))
    items[i] = dict(parts=parts, price=price, cost=round(price * 0.75, 2))
    irows.append((i, f'ITEM {i} TAB', 'دواء ' + str(i) if i % 10 == 0 else None, parts, price, round(price * 0.75, 2),
                  (5000 + i) if i % 25 == 0 else 999, 1 + i % 3, True, False, i % 50 == 0, False))
table('Items', [('ID', B), ('name', X), ('DESCRIPTION', X), ('Parts', B), ('SalesPrice', F), ('CostPrice', F), ('barcode', B),
                ('form_id', B), ('IsActive', BO), ('Archived', BO), ('FridgeItem', BO), ('FreezedItem', BO)])
rows('Items', ['ID', 'name', 'DESCRIPTION', 'Parts', 'SalesPrice', 'CostPrice', 'barcode', 'form_id', 'IsActive', 'Archived', 'FridgeItem', 'FreezedItem'], irows)
table('CrossRefrences', [('Id', B), ('itemID', B), ('ref', X), ('IsActive', BO)])
rows('CrossRefrences', ['Id', 'itemID', 'ref', 'IsActive'], [(i, i, f'622{i:010d}', True) for i in range(2, 202, 3)])

# العملاء والموردين: 1–5 موردين، 6–45 عملاء (بعضهم تليفونه جوه الاسم)
cards = []
for c in range(1, 46):
    vendor = c <= 5
    name = f'مورد {c}' if vendor else (f'عميل {c} 010{c:08d}' if c % 3 == 0 else f'عميل {c}')
    cards.append([c, name, vendor, not vendor, 2000.0 if not vendor and c % 2 else 0.0, dt.datetime(2020, 1, 1)])
table('Cards', [('Id', B), ('Name', X), ('IsVendor', BO), ('IsCreditCustomer', BO), ('CreditLimit', F), ('JoiningDate', T), ('Credit', F),
                ('District', X), ('AddressDetails', X)])
table('Telephones', [('ID', B), ('CustomerID', B), ('Tel', X)])
rows('Telephones', ['ID', 'CustomerID', 'Tel'], [(1, 7, '01122334455')])
bal = {c: 0.0 for c in range(1, 46)}   # موجب = العميل عليه / إحنا علينا للمورد

stock = {}   # (item, expiry) -> units في المخزن 1
pinv, pitems, tix, lines, cash, icards = [], [], [], [], [], []
pid = pl = tid = lid = cid = 0


def add_cash(op, amount, dealer, when, acc=1, nb=0.0):
    global cid
    cid += 1
    cash.append((cid, acc, amount, dealer, nb, op, when))


for d in range(DAYS):
    day = START + dt.timedelta(days=d)
    # الشرا: فاتورة كل يومين، 4 سطور، كل صنف بصلاحية
    if d % 2 == 0:
        pid += 1
        v = 1 + pid % 5
        tot = 0.0
        for k in range(4):
            it = R.randint(2, 201)
            exp = (day + dt.timedelta(days=R.choice([200, 400, 600]))).date()
            packs = R.choice([10, 20])
            bonus = 1 if k == 0 and pid % 3 == 0 else 0
            sprice = items[it]['price']
            td = 25.0
            cost = round(sprice * (1 - td / 100), 4)
            pl += 1
            pitems.append((pl, pid, it, packs, 0, bonus, sprice, cost, td, exp, 0))
            stock[(it, exp)] = stock.get((it, exp), 0) + (packs + bonus) * items[it]['parts']
            tot += cost * packs
        pinv.append((pid, f'INV{pid}', day + dt.timedelta(hours=1), day + dt.timedelta(hours=1), v, 1, round(tot, 2), 1, 1.5))
        bal[v] += round(tot, 2)
        # كل 5 فواتير: دفع للمورد (CashFlow 9 بالسالب)
        if pid % 5 == 0:
            pay = round(bal[v] * 0.6, 2)
            add_cash(9, -pay, v, day + dt.timedelta(hours=2), 2)
            bal[v] -= pay
    # مرتجع شرا كل 15 يوم: علبتين من آخر سطر لسه فيه رصيد (الكمية موجبة والإجمالي سالب)
    if d % 15 == 14:
        cand = [r for r in pitems if stock.get((r[2], r[9]), 0) >= 2 * items[r[2]]['parts']]
        if cand:
            r = cand[-1]
            pid += 1
            pl += 1
            pitems.append((pl, pid, r[2], 2, 0, 0, r[6], r[7], r[8], r[9], 0))
            stock[(r[2], r[9])] -= 2 * items[r[2]]['parts']
            v = next(p[4] for p in pinv if p[0] == r[1])
            pinv.append((pid, f'RET{pid}', day + dt.timedelta(hours=3), day + dt.timedelta(hours=3), v, 2, -round(r[7] * 2, 2), 1, 0.0))
            bal[v] -= round(r[7] * 2, 2)
    # البيع: 25 تذكرة في اليوم
    for n in range(25):
        when = day + dt.timedelta(minutes=30 + n * 25)
        avail = [k for k, u in stock.items() if u > 0]
        cust = R.randint(6, 45) if n % 5 == 0 else 0
        tid += 1
        mylines, total = [], 0.0
        for _ in range(R.choice([1, 2])):
            if not avail:
                break
            it, exp = R.choice(avail)
            parts = items[it]['parts']
            if parts > 1 and R.random() < 0.3:
                packs, units = 0, 1
            else:
                packs, units = 1, 0
            q_units = packs * parts + units
            if stock[(it, exp)] < q_units:
                continue
            stock[(it, exp)] -= q_units
            price = items[it]['price']
            val = round(price * (packs + units / parts), 2)
            lid += 1
            mylines.append((lid, tid, it, packs, units, price, parts, exp))
            total += val
        if not mylines:
            tid -= 1
            continue
        total = round(total, 2)
        disc = 5.0 if n % 4 == 1 and total > 20 else 0.0
        net = total - disc
        if cust:
            paid = R.choice([0.0, round(net / 2, 2), net, net + 50.0])   # آجل، نص، كله، أو كله + سداد 50
            bal[cust] += net - paid
        else:
            paid = net
        tix.append((tid, when, cust, 1, total, disc, paid, 1, round(bal[cust], 2) if cust else 0.0))
        for r in mylines:
            lines.append((r[0], r[1], r[2], r[3], r[4], r[5], r[6], dt.datetime.combine(r[7], dt.time()), 1.0))
        add_cash(1, paid if not cust else 0.0, 0, when)
    # مرتجع بيع كل يوم: آخر سطر بيع بعلبة كاملة يرجع (التذكرة والسطر بالسالب)
    last = next((l for l in reversed(lines) if l[3] == 1 and l[4] == 0), None)
    if last:
        orig = next(t for t in tix if t[0] == last[1])
        tid += 1
        lid += 1
        val = last[5]
        cust = orig[2]
        lines.append((lid, tid, last[2], -1, 0, last[5], last[6], last[7], 1.0))
        exp = last[7].date()
        stock[(last[2], exp)] = stock.get((last[2], exp), 0) + last[6]
        refund = 0.0 if cust else -val   # العميل اللي ليه حساب: المرتجع على حسابه، والكاش: رجع فلوس
        if cust:
            bal[cust] -= val
        tix.append((tid, day + dt.timedelta(hours=20), cust, 2, -val, 0.0, refund, 1, round(bal[cust], 2) if cust else 0.0))
    # تحصيل: تذكرة صفر بصنف 1 + نفس المبلغ في CashFlow 2 (متسجل مرتين: النقل ياخد التذكرة بس)
    if d % 3 == 0:
        debtors = [c for c in range(6, 46) if bal[c] > 30]
        if debtors:
            c = R.choice(debtors)
            amt = round(bal[c] / 2, 2)
            tid += 1
            lid += 1
            when = day + dt.timedelta(hours=21)
            bal[c] -= amt
            tix.append((tid, when, c, 1, 0.0, 0.0, amt, 1, round(bal[c], 2)))
            lines.append((lid, tid, 1, 1, 0, 0.0, 1, None, 0.0))
            add_cash(2, amt, c, when)
    # الجرد (كارت الصنف): كل 20 يوم عجز وحدة (عملية 5)، وكل 30 يوم زيادة وحدة (عملية 6)، والرصيد بيتغير
    if d % 20 == 7 or d % 30 == 11:
        keys = [k for k, u in stock.items() if u >= 2]
        if keys:
            it, exp = R.choice(keys)
            delta = -1 if d % 20 == 7 else 1
            stock[(it, exp)] += delta
            icards.append((len(icards) + 1, it, 5 if delta < 0 else 6, 0, delta, day + dt.timedelta(hours=23), 1,
                           dt.datetime.combine(exp, dt.time())))
    # تحصيل من غير تذكرة (CashFlow 4، زي قبل 2021)
    if d % 10 == 5:
        debtors = [c for c in range(6, 46) if bal[c] > 20]
        if debtors:
            c = R.choice(debtors)
            bal[c] -= 20.0
            add_cash(4, 20.0, c, day + dt.timedelta(hours=22), nb=round(bal[c], 2))

# التذاكر اللي تاريخها 1980 (زي الحقيقي): بتتساب
tid += 1
tix.append((tid, dt.datetime(1980, 1, 4), 0, 1, 10.0, 0.0, 10.0, 1, 0.0))
lid += 1
lines.append((lid, tid, 2, 0, 0, 10.0, 1, None, 1.0))

table('PurchaseInvoices', [('ID', B), ('inv_code', X), ('inv_date', T), ('ztime', T), ('vendor_id', B), ('SalesReturn', B),
                           ('total', F), ('StoreID', B), ('AmountAdjustment', F)])
rows('PurchaseInvoices', ['ID', 'inv_code', 'inv_date', 'ztime', 'vendor_id', 'SalesReturn', 'total', 'StoreID', 'AmountAdjustment'], pinv)
table('PurchaseItems', [('ID', B), ('inv_id', B), ('item_id', B), ('packs', B), ('units', B), ('bonus', B), ('sprice', F),
                        ('CostPrice', F), ('trade_discount', F), ('expirydate', T), ('Returned', B)])
rows('PurchaseItems', ['ID', 'inv_id', 'item_id', 'packs', 'units', 'bonus', 'sprice', 'CostPrice', 'trade_discount', 'expirydate', 'Returned'],
     [r[:9] + (dt.datetime.combine(r[9], dt.time()), r[10]) for r in pitems])
table('posTickets', [('ID', B), ('ztime', T), ('CustomerID', B), ('SalesReturn', B), ('Total', F), ('Discount', F),
                     ('PaidByCustomer', F), ('StoreID', B), ('NewBalance', F)])
rows('posTickets', ['ID', 'ztime', 'CustomerID', 'SalesReturn', 'Total', 'Discount', 'PaidByCustomer', 'StoreID', 'NewBalance'], tix)
table('posItems', [('ID', B), ('TicketID', B), ('ItemID', B), ('Packs', B), ('Units', B), ('SalesPrice', F), ('iParts', B),
                   ('ExpDate', T), ('Cost', F)])
rows('posItems', ['ID', 'TicketID', 'ItemID', 'Packs', 'Units', 'SalesPrice', 'iParts', 'ExpDate', 'Cost'], lines)
table('CashFlow', [('ID', B), ('AccountID', B), ('Amount', F), ('DealerID', B), ('NewBalance', F), ('Operation', B), ('ztime', T)])
rows('CashFlow', ['ID', 'AccountID', 'Amount', 'DealerID', 'NewBalance', 'Operation', 'ztime'], cash)
# الرصيد النهارده: علب + وحدات لكل صنف وصلاحية في المخزن 1
work, w = [], 0
for (it, exp), u in sorted(stock.items()):
    if u:
        w += 1
        parts = items[it]['parts']
        work.append((w, it, 1, u // parts, u % parts, dt.datetime.combine(exp, dt.time())))
table('Work', [('ID', B), ('item_id', B), ('StoreID', B), ('Packs', B), ('Units', B), ('exp_date', T)])
rows('Work', ['ID', 'item_id', 'StoreID', 'Packs', 'Units', 'exp_date'], work)
table('Transfers', [('ID', B), ('FromId', B), ('ToId', B), ('zDate', T)])
table('ItemCards', [('ID', B), ('ItemID', B), ('Operation', B), ('Packs', B), ('Units', B), ('ztime', T), ('StoreID', B), ('ExpiryDate', T)])
rows('ItemCards', ['ID', 'ItemID', 'Operation', 'Packs', 'Units', 'ztime', 'StoreID', 'ExpiryDate'], icards)
for c in cards:
    c.append(round(bal[c[0]], 2))
for c in cards:
    c += [None, None]
rows('Cards', ['Id', 'Name', 'IsVendor', 'IsCreditCustomer', 'CreditLimit', 'JoiningDate', 'Credit', 'District', 'AddressDetails'], cards)
print('\n'.join(out))
print(f"-- متولّد: {len(tix)} تذكرة، {len(lines)} سطر بيع، {len(pinv)} فاتورة شرا، {len(cash)} حركة خزنة، {len(work)} صف رصيد")
