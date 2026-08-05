alter table public.closets alter column created_by drop not null;
alter table public.closets drop constraint closets_created_by_fkey;
alter table public.closets add constraint closets_created_by_fkey
  foreign key (created_by) references public.users(id) on delete set null;
