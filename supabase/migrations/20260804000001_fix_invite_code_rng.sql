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
  new_invite_code := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into closets (name, invite_code, created_by)
  values (p_name, new_invite_code, auth.uid())
  returning * into new_closet;

  insert into closet_members (user_id, closet_id)
  values (auth.uid(), new_closet.id);

  return new_closet;
end;
$$;
