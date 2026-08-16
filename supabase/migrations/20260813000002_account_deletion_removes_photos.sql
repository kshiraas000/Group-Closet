-- delete_own_account() deleted the auth user, which cascades through
-- public.users -> items -> item_photos/item_shares. It never touched
-- Storage, so the actual image files were left orphaned in both buckets
-- forever. That makes "deleting your account removes your photos" false —
-- which is a claim the privacy policy needs to be able to make, and which
-- data-erasure requests depend on.
--
-- Both buckets key on the owner's uuid as the first path segment
-- ("<uid>/<item>/0.jpg" and "<uid>/photo.jpg"), so the user's objects can be
-- removed directly. This runs before the auth.users delete, while
-- auth.uid() is still resolvable.

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid text := auth.uid()::text;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  delete from storage.objects
  where bucket_id in ('item-photos', 'profile-photos')
    and (storage.foldername(name))[1] = uid;

  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
