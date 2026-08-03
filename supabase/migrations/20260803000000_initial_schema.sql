create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  photo_url text,
  sizes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.closets (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique,
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now()
);

create table public.closet_members (
  user_id uuid not null references public.users(id) on delete cascade,
  closet_id uuid not null references public.closets(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (user_id, closet_id)
);

create type item_category as enum ('Top', 'Bottom', 'Dress', 'Outerwear', 'Shoes', 'Accessory');

create table public.items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  category item_category not null,
  size text,
  color text,
  occasion_tags text[] not null default '{}',
  caption text,
  created_at timestamptz not null default now()
);

create table public.item_photos (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  photo_url text not null,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create table public.item_shares (
  item_id uuid not null references public.items(id) on delete cascade,
  closet_id uuid not null references public.closets(id) on delete cascade,
  primary key (item_id, closet_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  item_id uuid references public.items(id) on delete cascade,
  reported_user_id uuid references public.users(id) on delete cascade,
  reporter_id uuid not null references public.users(id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now()
);

create table public.blocks (
  blocker_id uuid not null references public.users(id) on delete cascade,
  blocked_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

alter table public.users enable row level security;
alter table public.closets enable row level security;
alter table public.closet_members enable row level security;
alter table public.items enable row level security;
alter table public.item_photos enable row level security;
alter table public.item_shares enable row level security;
alter table public.reports enable row level security;
alter table public.blocks enable row level security;
