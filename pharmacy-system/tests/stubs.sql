-- بديل صغير لـ Supabase عشان نجرب القاعدة على Postgres محلي (مش على قاعدة الصيدلية):
-- auth.users و auth.uid(). الـ roles (anon و authenticated) بيعملها check-db.sh مرة واحدة على السيرفر.
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
