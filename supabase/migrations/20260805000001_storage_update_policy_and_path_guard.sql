-- Fix: upsert: true on the client's Storage upload needs UPDATE, which no
-- policy granted — retry-after-successful-upload was failing with an opaque
-- RLS error, exactly the case the retry design exists for.
create policy "Users can overwrite their own item photos"
  on storage.objects for update
  using (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  );

-- Fix: the INSERT policy never validated segment 2 (item id) is actually a
-- uuid-shaped string, so a malformed path could get uploaded and then
-- permanently break the SELECT policy's uuid cast for everyone. Guard at
-- insert time so a malformed object can never be created.
drop policy "Users can upload photos to their own folder" on storage.objects;

create policy "Users can upload photos to their own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  );

-- Fix: the SELECT policy also guards the cast defensively (defense in depth
-- alongside the INSERT-time guard above), and is simplified to call
-- can_view_item instead of duplicating its logic — the old inline
-- "or exists(item_shares...)" branch was dead code, since items' own SELECT
-- policy already applies can_view_item to the same subquery.
drop policy "Users can view photos of items they can see" on storage.objects;

create policy "Users can view storage objects for items they can see"
  on storage.objects for select
  using (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and can_view_item(((storage.foldername(name))[2])::uuid)
  );
