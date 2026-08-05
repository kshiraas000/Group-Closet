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
  new_invite_code := replace(gen_random_uuid()::text, '-', '');

  insert into closets (name, invite_code, created_by)
  values (p_name, new_invite_code, auth.uid())
  returning * into new_closet;

  insert into closet_members (user_id, closet_id)
  values (auth.uid(), new_closet.id);

  return new_closet;
end;
$$;

revoke execute on function public.create_closet(text) from public;
revoke execute on function public.join_closet_by_invite_code(text) from public;
revoke execute on function public.is_closet_member(uuid) from public;

grant execute on function public.create_closet(text) to authenticated;
grant execute on function public.join_closet_by_invite_code(text) to authenticated;
grant execute on function public.is_closet_member(uuid) to authenticated;
