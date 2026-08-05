insert into storage.buckets (id, name, public)
values ('item-photos', 'item-photos', false)
on conflict (id) do nothing;

grant select, insert on public.items to authenticated;
grant select, insert on public.item_photos to authenticated;
grant select, insert on public.item_shares to authenticated;

-- SECURITY DEFINER, same reason as Phase 2's is_closet_member: items' SELECT policy
-- needs to check item_shares, and item_shares' SELECT policy needs to check items.
-- Two ordinary policies referencing each other directly causes infinite RLS
-- recursion (found the hard way in Task 1's first implementation attempt). This
-- helper bypasses RLS internally, breaking the cycle, exactly like is_closet_member
-- does for closets/closet_members.
create or replace function public.can_view_item(check_item_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from items i
    where i.id = check_item_id
    and (
      i.owner_id = auth.uid()
      or exists (
        select 1 from item_shares s
        join closet_members cm on cm.closet_id = s.closet_id
        where s.item_id = i.id and cm.user_id = auth.uid()
      )
    )
  );
$$;

grant execute on function public.can_view_item(uuid) to authenticated;

create policy "Users can view items they own or that are shared with them"
  on public.items for select
  using (can_view_item(id));

create policy "Users can insert their own items"
  on public.items for insert
  with check (owner_id = auth.uid());

create policy "Users can view photos of items they can see"
  on public.item_photos for select
  using (can_view_item(item_id));

create policy "Users can insert photos for their own items"
  on public.item_photos for insert
  with check (
    exists (select 1 from public.items where id = item_photos.item_id and owner_id = auth.uid())
  );

create policy "Users can view shares for items they can see"
  on public.item_shares for select
  using (
    can_view_item(item_id)
    or exists (select 1 from public.closet_members where closet_id = item_shares.closet_id and user_id = auth.uid())
  );

create policy "Item owners can share their own items to closets they're in"
  on public.item_shares for insert
  with check (
    exists (select 1 from public.items where id = item_shares.item_id and owner_id = auth.uid())
    and exists (select 1 from public.closet_members where closet_id = item_shares.closet_id and user_id = auth.uid())
  );

create policy "Users can upload photos to their own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can view photos of items they can see"
  on storage.objects for select
  using (
    bucket_id = 'item-photos'
    and exists (
      select 1 from public.items i
      where i.id = ((storage.foldername(name))[2])::uuid
      and (
        i.owner_id = auth.uid()
        or exists (
          select 1 from public.item_shares s
          join public.closet_members cm on cm.closet_id = s.closet_id
          where s.item_id = i.id and cm.user_id = auth.uid()
        )
      )
    )
  );

create policy "Users can delete their own item photos"
  on storage.objects for delete
  using (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
