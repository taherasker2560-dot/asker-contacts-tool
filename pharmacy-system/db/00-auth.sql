-- =====================================================================================================
-- (0) الدخول في البرنامج المتسطب على كمبيوتر الصيدلية
-- =====================================================================================================
-- البرنامج: PostgreSQL + PostgREST على كمبيوتر الصيدلية. الموظفين والبوت بيدخلوا بيوزر من هنا، والداتا مابتطلعش برا.
-- كل موظف: اسم مستخدم وكلمة سر (bcrypt). البوت: يوزر من نوع bot بمفتاح طويل (JWT) المالك بيطلّعه ويقدر يلغيه.
-- PostgREST بيدخل بـ authenticator وبيبدّل لـ authenticated أو anon حسب المفتاح، وقبل كل طلب بيتأكد إن المفتاح
-- لسه شغال (auth.check_request). الإعدادات (سر المفاتيح) في auth.config، ومحدش يقراها غير الدوال دي.
-- ملحوظة: الملف ده للتسطيب المحلي بس. على Supabase الـ auth بتاعه بيقوم بالدور ده.
-- الرجوع: drop schema auth cascade;
-- =====================================================================================================

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator noinherit login; end if;
end $$;
grant anon, authenticated to authenticator;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema auth;
revoke all on schema auth from public;
grant usage on schema auth to anon, authenticated;

create table auth.config (
  key   text primary key,
  value text not null
);

create table auth.users (
  id            uuid primary key default gen_random_uuid(),
  username      text not null unique check (username ~ '^[a-z0-9_.-]{3,40}$'),
  password_hash text,                                  -- bcrypt. البوت مالوش كلمة سر
  kind          text not null default 'person' check (kind in ('person', 'bot')),
  active        boolean not null default true,
  token_version integer not null default 1,            -- بيزيد = كل المفاتيح القديمة بتتلغي
  failed_logins integer not null default 0,
  locked_until  timestamptz,
  created_at    timestamptz not null default now(),
  last_login_at timestamptz,
  check (kind = 'bot' or password_hash is not null)
);

-- مين اللي باعت الطلب (نفس اسم Supabase، فكل كود القاعدة شغال زي ما هو)
create function auth.uid() returns uuid
language sql stable set search_path = '' as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;

create function auth.b64url(b bytea) returns text
language sql immutable set search_path = '' as $$
  select translate(rtrim(replace(encode(b, 'base64'), E'\n', ''), '='), '+/', '-_')
$$;

create function auth.sign_jwt(payload jsonb) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  v_secret text := (select c.value from auth.config c where c.key = 'jwt_secret');
  v_data   text;
begin
  if coalesce(length(v_secret), 0) < 32 then raise exception 'سر المفاتيح (jwt_secret) مش متظبط'; end if;
  v_data := auth.b64url(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8')) || '.' || auth.b64url(convert_to(payload::text, 'utf8'));
  return v_data || '.' || auth.b64url(extensions.hmac(convert_to(v_data, 'utf8'), convert_to(v_secret, 'utf8'), 'sha256'));
end $$;

create function auth.make_token(p_user auth.users, p_valid interval) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'token', auth.sign_jwt(jsonb_build_object('sub', p_user.id, 'role', 'authenticated', 'ver', p_user.token_version,
                                              'exp', extract(epoch from now() + p_valid)::bigint)),
    'expires_at', now() + p_valid)
$$;

-- قبل كل طلب: المفتاح لازم يكون لسه شغال (اليوزر شغال ومالغاش مفاتيحه)
create function auth.check_request() returns void
language plpgsql stable security definer set search_path = '' as $$
declare
  c    jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v_ok boolean;
begin
  if c is null or c ->> 'sub' is null then return; end if;      -- زائر الموقع (anon)
  select u.active and u.token_version = coalesce((c ->> 'ver')::integer, -1) into v_ok
  from auth.users u where u.id = (c ->> 'sub')::uuid;
  if not coalesce(v_ok, false) then
    raise exception 'الدخول ده اتلغى: سجّل دخول تاني' using errcode = 'PT401';
  end if;
end $$;

-- الدخول بكلمة السر. الغلط بيتعدّ، و5 مرات ورا بعض = الحساب يتقفل ربع ساعة
-- (مابيرميش exception في الغلط عشان العدّاد مايرجعش، وبيرجّع حالة HTTP 401 بدالها)
create function auth.login(p_username text, p_password text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  u auth.users;
  v_bad text := 'اسم المستخدم أو كلمة السر غلط';
begin
  select * into u from auth.users where username = lower(btrim(coalesce(p_username, '')));
  if not found or not u.active or u.kind <> 'person' then
    perform set_config('response.status', '401', true);
    return jsonb_build_object('error', v_bad);
  end if;
  if u.locked_until > now() then
    perform set_config('response.status', '403', true);
    return jsonb_build_object('error', 'الحساب مقفول لحد ' || to_char(u.locked_until at time zone 'Africa/Cairo', 'HH24:MI') || ' بسبب كلمة سر غلط كذا مرة');
  end if;
  if extensions.crypt(coalesce(p_password, ''), u.password_hash) <> u.password_hash then
    update auth.users
       set failed_logins = failed_logins + 1,
           locked_until = case when failed_logins + 1 >= 5 then now() + interval '15 minutes' end
     where id = u.id;
    perform set_config('response.status', '401', true);
    return jsonb_build_object('error', v_bad);
  end if;
  update auth.users set failed_logins = 0, locked_until = null, last_login_at = now() where id = u.id;
  return auth.make_token(u, interval '12 hours') || jsonb_build_object('username', u.username);
end $$;

create function auth.hash_password(p text) returns text
language plpgsql volatile set search_path = '' as $$
begin
  if char_length(coalesce(p, '')) < 8 then raise exception 'كلمة السر لازم 8 حروف على الأقل'; end if;
  return extensions.crypt(p, extensions.gen_salt('bf', 10));
end $$;

revoke all on all functions in schema auth from public;
grant execute on function auth.uid(), auth.check_request() to anon, authenticated;
