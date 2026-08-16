-- Invite codes were widened to a full 32-char UUID hex (20260804000002),
-- which is unguessable but far too long to read out or type. This swaps in a
-- 10-character Crockford-style base32 code: 32^10 ≈ 1.1e15 combinations
-- (~2^50), still far beyond brute-forcing a shared secret, but three times
-- shorter and human-friendly.
--
-- Randomness comes from gen_random_uuid(), NOT random() — 20260804000001
-- exists specifically because random() is not cryptographically secure, and
-- that fix must not be undone here. Ambiguous glyphs (I, L, O, U) are
-- excluded so codes can be read aloud without confusion.

create or replace function public.generate_invite_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  -- 13 hex chars = 52 bits, enough to fill 10 base32 digits (50 bits).
  v_num bigint := ('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 13))::bit(52)::bigint;
  result text := '';
  i int;
begin
  for i in 1..10 loop
    result := substr(alphabet, 1 + (v_num % 32)::int, 1) || result;
    v_num := v_num / 32;
  end loop;
  return result;
end;
$$;

revoke execute on function public.generate_invite_code() from public;

create or replace function public.create_closet(p_name text)
returns public.closets
language plpgsql
security definer
set search_path = public
as $$
declare
  new_closet public.closets;
  new_invite_code text;
begin
  -- invite_code is UNIQUE; collisions are vanishingly unlikely but a retry
  -- costs nothing and turns a hard insert failure into a non-event.
  loop
    new_invite_code := generate_invite_code();
    exit when not exists (select 1 from closets where invite_code = new_invite_code);
  end loop;

  insert into closets (name, invite_code, created_by)
  values (p_name, new_invite_code, auth.uid())
  returning * into new_closet;

  insert into closet_members (user_id, closet_id)
  values (auth.uid(), new_closet.id);

  return new_closet;
end;
$$;

-- Accept what people actually paste: any case, and with the display dash or
-- stray spaces included. Comparing case-insensitively also keeps any
-- remaining lowercase-hex codes working.
create or replace function public.join_closet_by_invite_code(p_invite_code text)
returns public.closets
language plpgsql
security definer
set search_path = public
as $$
declare
  target_closet public.closets;
  normalized text;
begin
  normalized := upper(regexp_replace(coalesce(p_invite_code, ''), '[^a-zA-Z0-9]', '', 'g'));

  select * into target_closet
  from closets
  where upper(regexp_replace(invite_code, '[^a-zA-Z0-9]', '', 'g')) = normalized;

  if target_closet.id is null then
    raise exception 'Invalid invite code';
  end if;

  insert into closet_members (user_id, closet_id)
  values (auth.uid(), target_closet.id)
  on conflict (user_id, closet_id) do nothing;

  return target_closet;
end;
$$;

-- Shorten the codes that already exist. This invalidates any 32-char code
-- already handed out, which is the intended trade — they're unusable in
-- practice, which is why they're being replaced.
do $$
declare
  r record;
  candidate text;
begin
  for r in select id from closets where length(invite_code) = 32 loop
    loop
      candidate := generate_invite_code();
      exit when not exists (select 1 from closets where invite_code = candidate);
    end loop;
    update closets set invite_code = candidate where id = r.id;
  end loop;
end;
$$;

grant execute on function public.create_closet(text) to authenticated;
grant execute on function public.join_closet_by_invite_code(text) to authenticated;
