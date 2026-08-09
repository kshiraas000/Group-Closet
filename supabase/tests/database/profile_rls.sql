begin;
select plan(9);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com');

insert into public.users (id, name) values
  ('11111111-1111-1111-1111-111111111111', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'Bob');

-- Alice and Bob share no closet at the point the blocked-profile-view
-- policy is tested below, isolating it from the pre-existing closet-mates
-- policy. This closet/membership fixture is only for the delete_own_account
-- cascade checks near the end of this file, and must be inserted now, as
-- the superuser session role — public.closets/closet_members were never
-- granted direct INSERT to authenticated (Phase 2 routes closet
-- creation/joining only through the create_closet()/
-- join_closet_by_invite_code() SECURITY DEFINER RPCs), so this would fail
-- with "permission denied for table closets" if attempted after switching
-- to authenticated below.
insert into public.closets (id, name, invite_code, created_by)
values ('33333333-3333-3333-3333-333333333333', 'Alice''s Closet', 'testcode', '11111111-1111-1111-1111-111111111111');

insert into public.closet_members (user_id, closet_id)
values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.blocks (blocker_id, blocked_id)
values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Alice can see her own block via the blocks SELECT policy'
);

select is(
  (select name from public.users where id = '22222222-2222-2222-2222-222222222222'),
  'Bob',
  'Alice can see Bob''s name because she has blocked him, even with no shared closet'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Bob cannot see Alice''s block of him (blocks SELECT is blocker-only)'
);

select is(
  (select count(*)::int from public.users where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Bob cannot see Alice''s name (Alice has not blocked Bob, and they share no closet)'
);

delete from public.blocks
where blocker_id = '11111111-1111-1111-1111-111111111111' and blocked_id = '22222222-2222-2222-2222-222222222222';

-- Bob's own "Users can view their own blocks" policy (blocker_id =
-- auth.uid()) would hide Alice's row from him regardless of whether his
-- delete attempt actually succeeded — Bob is never the blocker on this row,
-- so a count from his vantage point is always 0 and can't distinguish "row
-- still there, hidden from Bob" from "row deleted." Verify from a vantage
-- point that can actually see it, same pattern already used below for the
-- delete_own_account() checks.
reset role;

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Bob''s delete attempt does not remove Alice''s block (blocks DELETE is blocker-only)'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

delete from public.blocks
where blocker_id = '11111111-1111-1111-1111-111111111111' and blocked_id = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Alice can remove her own block'
);

-- Items for the delete_own_account() cascade checks below. items has its
-- own INSERT policy scoped to owner_id = auth.uid() (Phase 3), so these
-- work fine directly under authenticated, unlike closets/closet_members
-- above.
insert into public.items (id, owner_id, category)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'Top');

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

insert into public.items (id, owner_id, category)
values ('66666666-6666-6666-6666-666666666666', '22222222-2222-2222-2222-222222222222', 'Bottom');

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select public.delete_own_account();

reset role;

select is(
  (select count(*)::int from public.users where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'delete_own_account removes Alice''s public.users row'
);

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'delete_own_account cascades to Alice''s items'
);

select is(
  (select count(*)::int from public.items where id = '66666666-6666-6666-6666-666666666666'),
  1,
  'delete_own_account does not touch Bob''s data'
);

select * from finish();
rollback;
