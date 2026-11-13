#!/usr/bin/env python3
"""(3) خريطة نسخة فارمافلاي: كل جدول، أعمدته وأنواعها، عدد الصفوف، وأول وآخر تاريخ في كل عمود تاريخ.

الاستخدام:  python3 discover.py <الشغل>
بيكتب <الشغل>/discovery.json و <الشغل>/discovery.md. الملفين فيهم أسامي الجداول والأعمدة والأعداد بس، من غير صفوف.
قراية بس من القاعدة المسترجعة (pf)، مابيغيّرش فيها حاجة.
"""
import json
import os
import sys

import pymssql


def connect(work):
    """SQL Server بتاع restore.sh (Docker)، أو أي SQL Server عليه نسخة فارمافلاي (زي اللي الهَب بيرجّعها على اللاب):
    MSSQL_HOST / MSSQL_PORT / MSSQL_USER / MSSQL_PASSWORD / MSSQL_DB."""
    password = os.environ.get('MSSQL_PASSWORD')
    env_file = os.path.join(work, 'mssql.env')
    if password is None and os.path.exists(env_file):
        env = dict(line.strip().split('=', 1) for line in open(env_file) if '=' in line)
        password = env.get('MSSQL_SA_PASSWORD')
    if password is None:
        sys.exit('مفيش كلمة سر: شغّل restore.sh الأول، أو اكتب MSSQL_USER و MSSQL_PASSWORD و MSSQL_DB')
    extra = {'port': int(os.environ['MSSQL_PORT'])} if os.environ.get('MSSQL_PORT') else {}   # من غيره: 1433 أو اسم الـ instance
    return pymssql.connect(server=os.environ.get('MSSQL_HOST', '127.0.0.1'), user=os.environ.get('MSSQL_USER', 'sa'),
                           password=password, database=os.environ.get('MSSQL_DB', 'pf'), charset='UTF-8', login_timeout=30, **extra)


DATE_TYPES = {'date', 'datetime', 'datetime2', 'smalldatetime', 'datetimeoffset'}


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')   # شاشة ويندوز والعربي
    work = sys.argv[1]
    con = connect(work)
    cur = con.cursor(as_dict=True)
    cur.execute("""
        select s.name as sch, t.name as tbl, sum(p.rows) as n
        from sys.tables t join sys.schemas s on s.schema_id = t.schema_id
        join sys.partitions p on p.object_id = t.object_id and p.index_id in (0, 1)
        group by s.name, t.name order by s.name, t.name""")
    tables = cur.fetchall()
    out = []
    for t in tables:
        cur.execute("""
            select c.name as col, ty.name as type, c.max_length, c.precision, c.scale, c.is_nullable,
                   case when exists (select 1 from sys.index_columns ic join sys.indexes i
                                     on i.object_id = ic.object_id and i.index_id = ic.index_id
                                     where i.is_primary_key = 1 and ic.object_id = c.object_id and ic.column_id = c.column_id)
                        then 1 else 0 end as pk
            from sys.columns c join sys.types ty on ty.user_type_id = c.user_type_id
            where c.object_id = object_id(%s) order by c.column_id""", (f"[{t['sch']}].[{t['tbl']}]",))
        cols = cur.fetchall()
        for c in cols:
            if c['type'] in DATE_TYPES and t['n']:
                cur.execute(f"select min([{c['col']}]) as a, max([{c['col']}]) as b from [{t['sch']}].[{t['tbl']}]")
                r = cur.fetchone()
                c['min'] = str(r['a']) if r['a'] is not None else None
                c['max'] = str(r['b']) if r['b'] is not None else None
        out.append({'schema': t['sch'], 'table': t['tbl'], 'rows': int(t['n'] or 0), 'columns': cols})
    con.close()

    with open(os.path.join(work, 'discovery.json'), 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1, default=str)
    total = sum(t['rows'] for t in out)
    lines = [f'# خريطة نسخة فارمافلاي', '', f'{len(out)} جدول · {total:,} صف.', '',
             '| الجدول | الصفوف | الأعمدة | الفترة |', '|---|---:|---:|---|']
    for t in sorted(out, key=lambda x: -x['rows']):
        spans = [(c['min'], c['max']) for c in t['columns'] if c.get('min')]
        span = f"{min(a for a, _ in spans)[:10]} → {max(b for _, b in spans)[:10]}" if spans else ''
        lines.append(f"| `{t['schema']}.{t['table']}` | {t['rows']:,} | {len(t['columns'])} | {span} |")
    lines += ['', '## الأعمدة', '']
    for t in sorted(out, key=lambda x: -x['rows']):
        if not t['rows']:
            continue
        cols = ', '.join(f"`{c['col']}`{'*' if c['pk'] else ''} {c['type']}" for c in t['columns'])
        lines.append(f"- **{t['table']}** ({t['rows']:,}): {cols}")
    with open(os.path.join(work, 'discovery.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'{len(out)} جدول، {total:,} صف ← {os.path.join(work, "discovery.md")}')


if __name__ == '__main__':
    main()
