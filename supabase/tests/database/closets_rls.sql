begin;
select plan(12);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

create temporary table captured_invite (code text);

insert into public.users (id, name) values ('11111111-1111-1111-1111-111111111111', 'Alice');

insert into captured_invite (code)
select (public.create_closet('Roommates')).invite_code;

select is(
  (select count(*)::int from public.closets where created_by = '11111111-1111-1111-1111-111111111111'),
  1,
  'create_closet created a closet row'
);

select is(
  (select count(*)::int from public.closet_members where user_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Alice was auto-joined as a member'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
insert into public.users (id, name) values ('22222222-2222-2222-2222-222222222222', 'Bob');

select is(
  (select count(*)::int from public.closets),
  0,
  'Bob cannot see Alice''s closet before joining'
);

select is(
  (select count(*)::int from public.users where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Bob cannot see Alice''s profile before sharing a closet'
);

select throws_ok(
  $$select public.join_closet_by_invite_code('not-a-real-code')$$,
  'P0001',
  'Invalid invite code',
  'Bob cannot join with a bogus invite code'
);

select lives_ok(
  (select format('select public.join_closet_by_invite_code(%L)', (select code from captured_invite))),
  'Bob can join with the real invite code'
);

select is(
  (select count(*)::int from public.closets),
  1,
  'Bob can now see the closet he joined'
);

select is(
  (select name from public.users where id = '11111111-1111-1111-1111-111111111111'),
  'Alice',
  'Bob can now see Alice''s profile (closet-mate visibility)'
);

select throws_ok(
  $$insert into public.closet_members (user_id, closet_id) values (auth.uid(), (select id from public.closets limit 1))$$,
  '42501',
  null,
  'Direct insert into closet_members is blocked (must go through create_closet/join_closet_by_invite_code)'
);

select throws_ok(
  $$insert into public.closets (name, invite_code, created_by) values ('Fake', 'fakecode', auth.uid())$$,
  '42501',
  null,
  'Direct insert into closets is blocked (must go through create_closet)'
);

delete from public.closet_members
where user_id = '11111111-1111-1111-1111-111111111111'
  and closet_id = (select id from public.closets limit 1);

select is(
  (select count(*)::int from public.closet_members where user_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Bob cannot delete Alice''s membership (DELETE policy is self-only)'
);

delete from public.closet_members
where user_id = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.closets),
  0,
  'Bob no longer sees the closet after leaving'
);

select * from finish();
rollback;
