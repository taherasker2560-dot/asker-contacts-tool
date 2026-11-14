\set n random(1, 200)
select count(*) from ph.find_items('ITEM ' || :n);
