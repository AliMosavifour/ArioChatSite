-- v413: shared pinned messages.
-- A pinned message is now stored on the server, so every member of a group (or both people of a
-- one-to-one chat) sees the same pins. Run this whole file once in the Supabase SQL editor.
-- It does not touch any existing table except adding a trigger that removes pins of deleted messages.

create table if not exists public.link_pins (
  link_id   text not null,                 -- chat id (= link_messages.link_id; for a group, the group id)
  msg_id    text not null,
  k         text not null default 'g',     -- message kind (g text, p photo, v video, ...)
  t         text not null default '',      -- short preview
  n         text not null default '',      -- sender name
  c         bigint not null default 0,     -- message time in ms (sort order)
  pinned_by text not null default '',
  pinned_at timestamptz not null default now(),
  primary key (link_id, msg_id)
);
create index if not exists link_pins_link_idx on public.link_pins (link_id, c);

-- is the signed-in user a member of this chat? (counselor chat, friend chat or group)
create or replace function public.pin_is_member(p_link text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.links l
                  where l.id::text = p_link and auth.uid()::text in (l.counselor_id::text, l.student_id::text))
      or exists (select 1 from public.friend_links f
                  where f.id::text = p_link and auth.uid()::text in (f.owner_id::text, f.friend_id::text))
      or exists (select 1 from public.chat_group_members g
                  where g.group_id::text = p_link and g.user_id::text = auth.uid()::text);
$$;

alter table public.link_pins enable row level security;
drop policy if exists link_pins_read on public.link_pins;
create policy link_pins_read on public.link_pins for select using (public.pin_is_member(link_id));
-- no insert / update / delete policies: writes go through pin_set() only

-- pin (p_on = true) or unpin (false) a message for everybody in the chat
create or replace function public.pin_set(
  p_link text, p_msg text, p_on boolean,
  p_k text default 'g', p_t text default '', p_n text default '', p_c bigint default 0)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'err', 'auth'); end if;
  if not public.pin_is_member(p_link) then return jsonb_build_object('ok', false, 'err', 'member'); end if;
  if p_on then
    if (select count(*) from public.link_pins where link_id = p_link and msg_id <> p_msg) >= 20 then
      return jsonb_build_object('ok', false, 'err', 'max');
    end if;
    insert into public.link_pins (link_id, msg_id, k, t, n, c, pinned_by)
    values (p_link, p_msg, left(coalesce(p_k,'g'),2), left(coalesce(p_t,''),90), left(coalesce(p_n,''),40), coalesce(p_c,0), auth.uid()::text)
    on conflict (link_id, msg_id) do update set k = excluded.k, t = excluded.t, n = excluded.n, c = excluded.c;
  else
    delete from public.link_pins where link_id = p_link and msg_id = p_msg;
  end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.pin_set(text,text,boolean,text,text,text,bigint) to authenticated;
grant select on public.link_pins to authenticated;

-- a deleted message loses its pin for everybody
create or replace function public.pin_drop_deleted() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.link_pins where link_id = old.link_id::text and msg_id = old.id::text;
  return old;
end $$;
drop trigger if exists link_messages_pin_drop on public.link_messages;
create trigger link_messages_pin_drop after delete on public.link_messages
  for each row execute function public.pin_drop_deleted();
