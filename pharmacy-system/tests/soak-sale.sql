\set item random(1, 200)
\set packs random(1, 3)
select ph.post_sale(jsonb_build_object('client_uuid', gen_random_uuid(), 'lines', jsonb_build_array(jsonb_build_object('item_id', :item, 'packs', :packs)), 'payments', jsonb_build_array(jsonb_build_object('method', 'cash', 'amount', :packs * 10))));
