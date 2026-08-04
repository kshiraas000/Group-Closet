begin;
select plan(4);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com');

-- Simulate Alice's authenticated request
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.users (id, name)
values ('11111111-1111-1111-1111-111111111111', 'Alice');

select is(
  (select name from public.users where id = '11111111-1111-1111-1111-111111111111'),
  'Alice',
  'Alice can insert and read her own profile'
);

-- Simulate Bob's authenticated request
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.users where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Bob cannot see Alice''s profile'
);

select throws_ok(
  $$insert into public.users (id, name) values ('11111111-1111-1111-1111-111111111111', 'Fake Alice')$$,
  '42501',
  null,
  'Bob cannot insert a profile for another user''s id'
);

insert into public.users (id, name)
values ('22222222-2222-2222-2222-222222222222', 'Bob');

select is(
  (select name from public.users where id = '22222222-2222-2222-2222-222222222222'),
  'Bob',
  'Bob can insert and read his own profile'
);

select * from finish();
rollback;
