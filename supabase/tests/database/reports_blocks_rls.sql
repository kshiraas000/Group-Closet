begin;
select plan(9);

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

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.items (id, owner_id, category)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'Top');

insert into public.item_shares (item_id, closet_id)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333');

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

insert into public.items (id, owner_id, category)
values ('66666666-6666-6666-6666-666666666666', '22222222-2222-2222-2222-222222222222', 'Bottom');

insert into public.item_shares (item_id, closet_id)
values ('66666666-6666-6666-6666-666666666666', '33333333-3333-3333-3333-333333333333');

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Bob can see Alice''s item before any block (baseline)'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select is(
  (select count(*)::int from public.items where id = '66666666-6666-6666-6666-666666666666'),
  1,
  'Alice can see Bob''s item before any block (baseline)'
);

insert into public.reports (item_id, reporter_id)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111');

-- reports has no SELECT grant to authenticated at all (by design — nothing in
-- this phase reads it back), so verifying the insert actually landed requires
-- stepping outside the authenticated role's privileges entirely; reset role
-- returns to the session's original (superuser) role, which can read any
-- table regardless of grants or RLS. Immediately restore authenticated +
-- the JWT claim afterward, since every other assertion in this file depends
-- on acting as a specific real user.
reset role;

select is(
  (select count(*)::int from public.reports where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Alice can report an item as herself, with no reason'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select throws_ok(
  $$insert into public.reports (item_id, reporter_id) values ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222')$$,
  '42501',
  null,
  'Alice cannot file a report claiming to be Bob'
);

select throws_ok(
  $$insert into public.blocks (blocker_id, blocked_id) values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111')$$,
  '42501',
  null,
  'Alice cannot insert a block claiming to be Bob'
);

select throws_ok(
  $$insert into public.blocks (blocker_id, blocked_id) values ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111')$$,
  '42501',
  null,
  'Alice cannot block herself'
);

insert into public.blocks (blocker_id, blocked_id)
values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

-- Same reasoning as the reports check above: blocks has no SELECT grant to
-- authenticated either, so bypass to verify, then restore the role/claim.
reset role;

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111' and blocked_id = '22222222-2222-2222-2222-222222222222'),
  1,
  'Alice can block Bob as herself'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select is(
  (select count(*)::int from public.items where id = '66666666-6666-6666-6666-666666666666'),
  0,
  'Alice can no longer see Bob''s item after blocking him'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'Bob can no longer see Alice''s item after Alice blocked him (mutual hide)'
);

select * from finish();
rollback;
