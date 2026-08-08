grant insert on public.reports to authenticated;

create policy "Users can create reports as themselves"
  on public.reports for insert
  with check (reporter_id = auth.uid());

grant insert on public.blocks to authenticated;

create policy "Users can block others as themselves"
  on public.blocks for insert
  with check (blocker_id = auth.uid() and blocked_id != auth.uid());

alter table public.reports alter column reason drop not null;

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
    and not exists (
      select 1 from blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = i.owner_id)
         or (b.blocker_id = i.owner_id and b.blocked_id = auth.uid())
    )
  );
$$;
