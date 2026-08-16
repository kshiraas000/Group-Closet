begin;
select plan(9);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'carol@example.com');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into public.users (id, name) values ('11111111-1111-1111-1111-111111111111', 'Alice');

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
insert into public.users (id, name) values ('22222222-2222-2222-2222-222222222222', 'Bob');

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
insert into public.users (id, name) values ('33333333-3333-3333-3333-333333333333', 'Carol');

-- ---------------------------------------------------------------------------
-- Creator can delete; items survive, shares cascade
-- ---------------------------------------------------------------------------
create temporary table ctx (closet_id uuid, invite_code text, item_id uuid);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into ctx (closet_id, invite_code)
select c.id, c.invite_code from public.create_closet('Roommates') c;

-- Alice owns an item shared into the closet (setup bypasses RLS).
reset role;
insert into public.items (owner_id, category)
values ('11111111-1111-1111-1111-111111111111', 'Top');
update ctx set item_id = (select id from public.items limit 1);
insert into public.item_shares (item_id, closet_id)
select (select item_id from ctx), (select closet_id from ctx);
set local role authenticated;

delete from public.closets where id = (select closet_id from ctx);

reset role;
select is(
  (select count(*)::int from public.closets where id = (select closet_id from ctx)),
  0,
  'Creator can delete their own closet'
);

select is(
  (select count(*)::int from public.items where id = (select item_id from ctx)),
  1,
  'Deleting a closet does NOT delete anyone''s items'
);

select is(
  (select count(*)::int from public.item_shares where closet_id = (select closet_id from ctx)),
  0,
  'Deleting a closet cascades away its item_shares'
);

-- ---------------------------------------------------------------------------
-- Non-creator member cannot delete; non-member cannot delete
-- ---------------------------------------------------------------------------
delete from ctx;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into ctx (closet_id, invite_code)
select c.id, c.invite_code from public.create_closet('Formal Fits') c;

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select public.join_closet_by_invite_code((select invite_code from ctx));

delete from public.closets where id = (select closet_id from ctx);

reset role;
select is(
  (select count(*)::int from public.closets where id = (select closet_id from ctx)),
  1,
  'A member who is not the creator cannot delete the closet'
);

set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
delete from public.closets where id = (select closet_id from ctx);

reset role;
select is(
  (select count(*)::int from public.closets where id = (select closet_id from ctx)),
  1,
  'A non-member cannot delete the closet'
);

-- ---------------------------------------------------------------------------
-- Orphaned closet (creator deleted their account): any member can delete
-- ---------------------------------------------------------------------------
update public.closets set created_by = null where id = (select closet_id from ctx);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
delete from public.closets where id = (select closet_id from ctx);

reset role;
select is(
  (select count(*)::int from public.closets where id = (select closet_id from ctx)),
  0,
  'Any member can delete an orphaned closet (created_by is null)'
);

-- ---------------------------------------------------------------------------
-- Auto-delete when the last member leaves
-- ---------------------------------------------------------------------------
delete from ctx;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into ctx (closet_id, invite_code)
select c.id, c.invite_code from public.create_closet('Ski Trip') c;

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select public.join_closet_by_invite_code((select invite_code from ctx));

-- Bob leaves, Alice remains.
delete from public.closet_members
where closet_id = (select closet_id from ctx) and user_id = auth.uid();

reset role;
select is(
  (select count(*)::int from public.closets where id = (select closet_id from ctx)),
  1,
  'Closet survives while at least one member remains'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
delete from public.closet_members
where closet_id = (select closet_id from ctx) and user_id = auth.uid();

reset role;
select is(
  (select count(*)::int from public.closets where id = (select closet_id from ctx)),
  0,
  'Closet is auto-deleted when the last member leaves'
);

select is(
  (select count(*)::int from public.closet_members where closet_id = (select closet_id from ctx)),
  0,
  'Cascade re-entry into the trigger does not error or leave orphan members'
);

select * from finish();
rollback;
