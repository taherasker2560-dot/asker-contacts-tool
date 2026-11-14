-- تجهيز اختبار الضغط: 200 صنف بسعر 10 ورصيد كبير، ومالك وكاشير. (tests/soak.sh و install/laptop/soak-trial.ps1)
insert into ph.settings (pharmacy_name) values ('اختبار ضغط');
insert into ph.branches (name) values ('الفرع');
insert into ph.locations (branch_id, name, kind, is_default_sale) values (1, 'الرئيسي', 'main', true);
insert into ph.cash_accounts (branch_id, name, kind) values (1, 'درج', 'drawer');
insert into ph.payment_methods values ('cash', 'كاش', 1), ('credit', 'آجل', null);
insert into auth.users (id, username, password_hash) values ('00000000-0000-0000-0000-0000000000a1', 'owner', '-'), ('00000000-0000-0000-0000-0000000000c1', 'cashier', '-');
insert into ph.staff (user_id, branch_id, name, role) values ('00000000-0000-0000-0000-0000000000a1', 1, 'المالك', 'owner'), ('00000000-0000-0000-0000-0000000000c1', 1, 'كاشير', 'cashier');
insert into ph.items (id, name_en, pack_parts, public_price) select g, 'ITEM ' || g, 1, 10 from generate_series(1, 200) g;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select ph.post_opening_stock(1::smallint, (select jsonb_agg(jsonb_build_object('item_id', g, 'packs', 100000, 'expiry', '2030-01-01')) from generate_series(1, 200) g));
