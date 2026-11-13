-- أدوات الاختبار: tst.eq (النتيجة = المتوقع)، tst.fails (لازم يرفض برسالة فيها كلمة)، tst.as_user (ادخل بحساب)
create schema tst;
create function tst.eq(got anyelement, want anyelement, msg text) returns void language plpgsql as $$
begin
  if got is distinct from want then raise exception 'FAIL %: طلع % والمتوقع %', msg, got, want; end if;
  raise notice 'OK   %', msg;
end $$;
create function tst.fails(sql text, frag text, msg text) returns void language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    if position(frag in sqlerrm) > 0 then raise notice 'OK   % ← «%»', msg, sqlerrm; return; end if;
    raise exception 'FAIL %: الغلط «%» مافيهوش «%»', msg, sqlerrm, frag;
  end;
  raise exception 'FAIL %: عدّى من غير غلط', msg;
end $$;
create function tst.as_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u, false); end $$;
grant usage on schema tst to authenticated, anon;
grant execute on all functions in schema tst to authenticated, anon;
