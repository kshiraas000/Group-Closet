-- Edit/Delete on ItemDetailView were wired to disabled stubs because
-- authenticated only had SELECT+INSERT on items (see AddItemViewModel's
-- save() comment). Adds owner-scoped UPDATE on items and DELETE on items +
-- item_photos (item_shares and the storage object already have owner
-- delete policies from earlier phases; items/item_photos cascade on delete
-- but RLS still gates the cascade itself, so item_photos needs its own
-- policy even though no app code deletes it directly).

grant update, delete on public.items to authenticated;
grant delete on public.item_photos to authenticated;

create policy "Item owners can update their own items"
  on public.items for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "Item owners can delete their own items"
  on public.items for delete
  using (owner_id = auth.uid());

create policy "Item owners can delete photos of their own items"
  on public.item_photos for delete
  using (
    exists (select 1 from public.items where id = item_photos.item_id and owner_id = auth.uid())
  );
