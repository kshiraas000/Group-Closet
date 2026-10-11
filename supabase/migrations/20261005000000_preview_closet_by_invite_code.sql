-- Lets the Join-a-Closet sheet show a closet's name and size before the user
-- commits to joining, from the invite code alone. SECURITY DEFINER so it can
-- read a closet the caller isn't a member of yet (closets.select RLS is
-- members-only) — read-only, no row is inserted, unlike join_closet_by_invite_code.
create or replace function public.preview_closet_by_invite_code(p_invite_code text)
returns table (
  closet_id uuid,
  name text,
  member_count bigint,
  piece_count bigint,
  already_member boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_closet public.closets;
  normalized text;
begin
  -- Same normalization as join_closet_by_invite_code: accepts any case and
  -- the display dash, so a pasted code matches regardless of formatting.
  normalized := upper(regexp_replace(coalesce(p_invite_code, ''), '[^a-zA-Z0-9]', '', 'g'));

  select * into target_closet
  from closets c
  where upper(regexp_replace(c.invite_code, '[^a-zA-Z0-9]', '', 'g')) = normalized;

  if target_closet.id is null then
    raise exception 'Invalid invite code';
  end if;

  return query
  select
    target_closet.id,
    target_closet.name,
    (select count(*) from closet_members cm where cm.closet_id = target_closet.id),
    (select count(*) from item_shares its where its.closet_id = target_closet.id),
    exists (
      select 1 from closet_members cm
      where cm.closet_id = target_closet.id and cm.user_id = auth.uid()
    );
end;
$$;

revoke execute on function public.preview_closet_by_invite_code(text) from public;
grant execute on function public.preview_closet_by_invite_code(text) to authenticated;
