drop policy "Users can view storage objects for items they can see" on storage.objects;

create policy "Users can view storage objects for items they can see"
  on storage.objects for select
  using (
    bucket_id = 'item-photos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or (
        (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and can_view_item(((storage.foldername(name))[2])::uuid)
      )
    )
  );
