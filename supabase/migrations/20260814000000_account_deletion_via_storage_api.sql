-- 20260813000002 made delete_own_account() delete straight out of
-- storage.objects. That table is only Storage's metadata — the image bytes
-- live in the storage backend — so the delete never removed the actual files;
-- it just unlinked them, leaving the photos in the bucket untracked. Newer
-- Storage versions now block the write outright via storage.protect_delete(),
-- so the function raises 42501 and account deletion fails entirely.
--
-- Photo removal moves to the client, which goes through the Storage API and
-- deletes the bytes for real. This function goes back to doing one thing:
-- removing the auth user, which still cascades public.users -> items ->
-- item_photos/item_shares.

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;

-- item-photos got a DELETE policy in 20260804000004, but profile-photos never
-- did, so the client could not remove a profile picture through the Storage
-- API at all — not on account deletion, and not on a plain photo change.
create policy "Users can delete their own profile photos"
  on storage.objects for delete
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
