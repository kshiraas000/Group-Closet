insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', false)
on conflict (id) do nothing;

create policy "Users can upload their own profile photo"
  on storage.objects for insert
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can overwrite their own profile photo"
  on storage.objects for update
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can view their own or closet-mates' profile photos"
  on storage.objects for select
  using (
    bucket_id = 'profile-photos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1 from public.closet_members cm1
        join public.closet_members cm2 on cm1.closet_id = cm2.closet_id
        where cm1.user_id = auth.uid()
        and cm2.user_id = ((storage.foldername(name))[1])::uuid
      )
    )
  );

grant select, delete on public.blocks to authenticated;

create policy "Users can view their own blocks"
  on public.blocks for select
  using (blocker_id = auth.uid());

create policy "Users can remove their own blocks"
  on public.blocks for delete
  using (blocker_id = auth.uid());

create policy "Users can view profiles of people they've blocked"
  on public.users for select
  using (
    exists (select 1 from public.blocks where blocker_id = auth.uid() and blocked_id = users.id)
  );

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
