-- Deleting a closet. Until now closets could only be left, never deleted, and
-- there was no DELETE policy on public.closets at all.

grant delete on public.closets to authenticated;

-- The creator owns the closet. If they deleted their account, created_by was
-- set to null (20260804000003) and the closet would otherwise be undeletable
-- forever, so any remaining member can clean it up.
create policy "Creator or any member of an orphaned closet can delete it"
on public.closets
for delete
using (
  created_by = auth.uid()
  or (created_by is null and public.is_closet_member(id))
);

-- A closet with no members is unreachable through the members-only SELECT
-- policy, so drop it rather than leaving an invisible row behind.
--
-- security definer is required, not optional: this fires after the last member
-- has already deleted their own closet_members row, so the caller no longer
-- satisfies is_closet_member and RLS would hide the closet from them.
create function public.delete_closet_if_empty()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from closet_members where closet_id = old.closet_id
  ) then
    -- On a direct closet delete this trigger re-enters via the cascade into
    -- closet_members; the row is already gone by then, so this is a no-op.
    delete from closets where id = old.closet_id;
  end if;
  return null;
end;
$$;

create trigger closet_members_delete_empty_closet
after delete on public.closet_members
for each row
execute function public.delete_closet_if_empty();
