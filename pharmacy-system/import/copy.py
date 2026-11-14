#!/usr/bin/env python3
"""(4) نسخ كل جداول فارمافلاي زي ما هي لـ Postgres (schema اسمها pf_raw)، وبعدين التأكد إن عدد الصفوف هو هو.

الاستخدام:  PGURL=postgresql://… python3 copy.py <الشغل> [جدول1 جدول2 …]
من غير أسامي جداول = كله. الجدول بيتمسح ويتعمل من جديد في كل مرة (pf_raw نسخة للقراية بس).
بعدها: import/pharmafly-to-stage.sql (pf_raw ← stage) ثم ph.import_history().
"""
import os
import sys

import psycopg
import pymssql

from discover import connect

PG_TYPE = {
    'bigint': 'bigint', 'int': 'bigint', 'smallint': 'integer', 'tinyint': 'smallint', 'bit': 'boolean',
    'decimal': 'numeric', 'numeric': 'numeric', 'money': 'numeric', 'smallmoney': 'numeric',
    'float': 'double precision', 'real': 'double precision',
    'date': 'date', 'datetime': 'timestamp', 'datetime2': 'timestamp', 'smalldatetime': 'timestamp',
    'datetimeoffset': 'timestamptz', 'time': 'time', 'uniqueidentifier': 'uuid',
    'binary': 'bytea', 'varbinary': 'bytea', 'image': 'bytea', 'timestamp': 'bytea', 'rowversion': 'bytea',
}
TEXT_TYPES = {'char', 'varchar', 'nchar', 'nvarchar', 'text', 'ntext', 'sysname'}
BATCH = 20000


def qi(name):
    return '"' + name.replace('"', '""') + '"'


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')   # شاشة ويندوز والعربي
    work = sys.argv[1]
    only = set(sys.argv[2:])
    src = connect(work)
    cur = src.cursor(as_dict=True)
    cur.execute("""select s.name as sch, t.name as tbl from sys.tables t join sys.schemas s on s.schema_id = t.schema_id
                   order by s.name, t.name""")
    tables = [t for t in cur.fetchall() if not only or t['tbl'] in only]
    with psycopg.connect(os.environ['PGURL']) as pg:
        pg.execute('create schema if not exists pf_raw')
        pg.execute('revoke all on schema pf_raw from public')
        report = []
        for t in tables:
            full = f"[{t['sch']}].[{t['tbl']}]"
            target = 'pf_raw.' + qi(t['tbl'] if t['sch'] == 'dbo' else f"{t['sch']}.{t['tbl']}")
            cur.execute("""select c.name as col, ty.name as type from sys.columns c
                           join sys.types ty on ty.user_type_id = c.user_type_id
                           where c.object_id = object_id(%s) order by c.column_id""", (full,))
            cols = cur.fetchall()
            pg.execute(f'drop table if exists {target}')
            pg.execute(f'create table {target} (' + ', '.join(f"{qi(c['col'])} {PG_TYPE.get(c['type'], 'text')}" for c in cols) + ')')
            # النص (عربي) والأرقام والتواريخ بتيجي زي ما هي، والأنواع الغريبة (xml، sql_variant…) بتتحوّل لنص
            select = ', '.join(f"[{c['col']}]" if c['type'] in PG_TYPE or c['type'] in TEXT_TYPES
                               else f"cast([{c['col']}] as nvarchar(max)) as [{c['col']}]" for c in cols)
            rd = src.cursor()
            rd.execute(f'select {select} from {full}')
            n = 0
            with pg.cursor() as w, w.copy(f'copy {target} from stdin') as cp:
                while True:
                    rows = rd.fetchmany(BATCH)
                    if not rows:
                        break
                    for r in rows:
                        cp.write_row(r)
                    n += len(rows)
            cur.execute(f'select count_big(*) as n from {full}')
            src_n = cur.fetchone()['n']
            dst_n = pg.execute(f'select count(*) from {target}').fetchone()[0]
            report.append((t['tbl'], src_n, dst_n))
            print(f"{'OK  ' if src_n == dst_n else 'FAIL'} {t['tbl']}: {src_n:,} ← {dst_n:,}", flush=True)
        pg.commit()
    bad = [r for r in report if r[1] != r[2]]
    print(f'اتنسخ {len(report)} جدول' + (f'، و{len(bad)} جدول العدد فيهم مختلف' if bad else '، كله نفس العدد'))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
