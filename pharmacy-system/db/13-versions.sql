-- =====================================================================================================
-- (13) نسخة القاعدة: أي تعديل بعد التسطيب الأول بيبقى ملف في db/migrations ومتسجل هنا
-- =====================================================================================================
-- الملفات من 00 لـ 13 = «التسطيب الأول» (base). بعد ما البرنامج يتسطب على اللاب، الملفات دي ماتتعدلش:
-- أي إضافة أو حذف أو تعديل = ملف جديد مرقّم في db/migrations، بيتطبق مرة واحدة في عملية واحدة، ويتسجل هنا.
-- tools/migrate.sh (Linux) و install/laptop/update-trial.ps1 (ويندوز) هما اللي بيطبقوه.
create table ph.schema_migrations (
  version    text primary key,                 -- اسم الملف من غير .sql: 202611140930_add_shelf
  checksum   text,                             -- بصمة الملف وقت التطبيق (لو اتعدّل بعدها = تحذير)
  applied_at timestamptz not null default now(),
  applied_by text not null default current_user
);
insert into ph.schema_migrations (version, checksum) values ('base', null);
alter table ph.schema_migrations enable row level security;
create policy managers_read on ph.schema_migrations for select to authenticated using (ph.has_role(array['owner', 'manager']));
grant select on ph.schema_migrations to authenticated;
