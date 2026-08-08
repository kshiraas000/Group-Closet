grant delete on public.item_shares to authenticated;

create policy "Item owners can remove their own item shares"
  on public.item_shares for delete
  using (
    exists (select 1 from public.items where id = item_shares.item_id and owner_id = auth.uid())
  );
