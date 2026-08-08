begin;
select plan(14);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com');

insert into public.users (id, name) values
  ('11111111-1111-1111-1111-111111111111', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'Bob');

insert into public.closets (id, name, invite_code, created_by) values
  ('33333333-3333-3333-3333-333333333333', 'Shared Closet', 'testcode', '11111111-1111-1111-1111-111111111111');

insert into public.closet_members (user_id, closet_id) values
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333'),
  ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333');

-- Fixture for the "Alice cannot share into a closet she isn't in" test below:
-- a second closet Bob created and belongs to, that Alice never joined.
insert into public.closets (id, name, invite_code, created_by) values
  ('55555555-5555-5555-5555-555555555555', 'Bob''s Other Closet', 'bobcode', '22222222-2222-2222-2222-222222222222');

insert into public.closet_members (user_id, closet_id) values
  ('22222222-2222-2222-2222-222222222222', '55555555-5555-5555-5555-555555555555');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.items (id, owner_id, category)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'Top');

select is(
  (select count(*)::int from public.items where owner_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Alice can insert her own item'
);

insert into public.item_photos (item_id, photo_url, position)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111/44444444-4444-4444-4444-444444444444/0.jpg', 0);

select is(
  (select count(*)::int from public.item_photos where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Alice can insert a photo for her own item'
);

select throws_ok(
  $$insert into public.item_photos (item_id, photo_url, position) values ('44444444-4444-4444-4444-444444444444', 'duplicate.jpg', 0)$$,
  '23505',
  null,
  'Cannot insert a second photo at the same position for the same item'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'Bob cannot see Alice''s item before it is shared'
);

select throws_ok(
  $$insert into public.item_shares (item_id, closet_id) values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333')$$,
  '42501',
  null,
  'Bob cannot share an item he does not own'
);

select throws_ok(
  $$insert into public.item_photos (item_id, photo_url, position) values ('44444444-4444-4444-4444-444444444444', 'fake/path/0.jpg', 0)$$,
  '42501',
  null,
  'Bob cannot insert a photo for an item he does not own'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.item_shares (item_id, closet_id)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333');

select is(
  (select count(*)::int from public.item_shares where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Alice can share her own item to a closet she is in'
);

select throws_ok(
  $$insert into public.item_shares (item_id, closet_id) values ('44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555')$$,
  '42501',
  null,
  'Alice cannot share her item into a closet she is not a member of'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Bob can see the item once it is shared to a closet he is in'
);

select is(
  (select count(*)::int from public.item_photos where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Bob can see the shared item''s photo row'
);

select throws_ok(
  $$insert into public.items (id, owner_id, category) values ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'Top')$$,
  '42501',
  null,
  'Bob cannot insert an item on Alice''s behalf'
);

-- A DELETE governed only by a `USING` policy never raises 42501 the way an
-- INSERT/UPDATE `WITH CHECK` violation does — RLS just filters the row out,
-- so the statement silently affects 0 rows. Assert that instead of throws_ok.
delete from public.item_shares
where item_id = '44444444-4444-4444-4444-444444444444' and closet_id = '33333333-3333-3333-3333-333333333333';

select is(
  (select count(*)::int from public.item_shares where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Bob''s delete attempt does not remove Alice''s share (RLS filters it silently)'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

delete from public.item_shares
where item_id = '44444444-4444-4444-4444-444444444444' and closet_id = '33333333-3333-3333-3333-333333333333';

select is(
  (select count(*)::int from public.item_shares where item_id = '44444444-4444-4444-4444-444444444444'),
  0,
  'Alice can remove her own item''s share'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'Bob can no longer see the item after Alice removes the share'
);

select * from finish();
rollback;
