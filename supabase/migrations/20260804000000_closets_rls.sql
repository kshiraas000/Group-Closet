create or replace function public.is_closet_member(check_closet_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from closet_members
    where closet_id = check_closet_id and user_id = auth.uid()
  );
$$;

grant execute on function public.is_closet_member(uuid) to authenticated;

grant select on public.closets to authenticated;
grant select, delete on public.closet_members to authenticated;

create policy "Members can view their closets"
  on public.closets for select
  using (is_closet_member(id));

create policy "Members can view closet membership"
  on public.closet_members for select
  using (is_closet_member(closet_id));

create policy "Users can leave a closet themselves"
  on public.closet_members for delete
  using (user_id = auth.uid());

create policy "Users can view profiles of closet-mates"
  on public.users for select
  using (
    exists (
      select 1 from public.closet_members cm1
      join public.closet_members cm2 on cm1.closet_id = cm2.closet_id
      where cm1.user_id = auth.uid() and cm2.user_id = users.id
    )
  );

create or replace function public.create_closet(p_name text)
returns public.closets
language plpgsql
security definer
set search_path = public
as $$
declare
  new_closet public.closets;
  new_invite_code text;
begin
  new_invite_code := substr(md5(random()::text || clock_timestamp()::text), 1, 8);

  insert into closets (name, invite_code, created_by)
  values (p_name, new_invite_code, auth.uid())
  returning * into new_closet;

  insert into closet_members (user_id, closet_id)
  values (auth.uid(), new_closet.id);

  return new_closet;
end;
$$;

grant execute on function public.create_closet(text) to authenticated;

create or replace function public.join_closet_by_invite_code(p_invite_code text)
returns public.closets
language plpgsql
security definer
set search_path = public
as $$
declare
  target_closet public.closets;
begin
  select * into target_closet from closets where invite_code = p_invite_code;

  if target_closet.id is null then
    raise exception 'Invalid invite code';
  end if;

  insert into closet_members (user_id, closet_id)
  values (auth.uid(), target_closet.id)
  on conflict (user_id, closet_id) do nothing;

  return target_closet;
end;
$$;

grant execute on function public.join_closet_by_invite_code(text) to authenticated;
