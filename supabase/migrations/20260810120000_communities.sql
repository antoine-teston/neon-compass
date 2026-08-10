-- Hub communautaire — annuaire de communautés et événements de communauté
--
-- Spec : docs/superpowers/specs/2026-08-10-hub-communautaire-design.md
-- Cible : v1.1 (décembre 2026)

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table communities (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id) unique,
  name            text not null
                  check (length(name) between 3 and 30)
                  check (name ~ '^[a-zA-Z0-9 -]+$'),
  platform        text not null
                  check (platform in ('ps5','xbox','pc','cross-platform')),
  playstyles      text[] not null default '{}',
  languages       text[] not null default '{}',
  discord_invite  text check (discord_invite is null or discord_invite ~ '^https://discord\.gg/'),
  member_count    int not null default 1 check (member_count >= 1),
  server_address  text,
  promoted        bool not null default false,
  promoted_until  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table community_events (
  id             uuid primary key default gen_random_uuid(),
  community_id   uuid not null references communities(id) on delete cascade,
  event_type     text not null
                 check (event_type in (
                   'tournament','themed_night','recruitment',
                   'launch','training','other'
                 )),
  platform       text not null
                 check (platform in ('ps5','xbox','pc','cross-platform')),
  starts_at      timestamptz not null,
  ends_at        timestamptz,
  slots          int check (slots is null or slots > 0),
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table communities enable row level security;

create policy "communities_select" on communities
  for select using (true);
create policy "communities_insert" on communities
  for insert with check (auth.uid() = owner_id);
create policy "communities_update" on communities
  for update using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);
create policy "communities_delete" on communities
  for delete using (auth.uid() = owner_id);

alter table community_events enable row level security;

create policy "community_events_select" on community_events
  for select using (true);
create policy "community_events_insert" on community_events
  for insert with check (
    exists (
      select 1 from communities
      where id = community_id
        and owner_id = auth.uid()
        and promoted = true
    )
  );
create policy "community_events_delete" on community_events
  for delete using (
    exists (
      select 1 from communities
      where id = community_events.community_id
        and owner_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- Trigger — plafond de 3 événements actifs par communauté
-- ---------------------------------------------------------------------------

create or replace function enforce_community_event_limit()
returns trigger as $$
begin
  if (
    select count(*) from community_events
    where community_id = NEW.community_id
      and (ends_at is null or ends_at > now())
  ) >= 3 then
    raise exception 'community_event_limit_reached';
  end if;
  return NEW;
end;
$$ language plpgsql;

create trigger trg_community_event_limit
  before insert on community_events
  for each row execute function enforce_community_event_limit();

-- ---------------------------------------------------------------------------
-- Privilèges — révocation propre à cette migration
-- ---------------------------------------------------------------------------

revoke all on communities from anon, authenticated, public;
revoke all on community_events from anon, authenticated, public;
revoke all on function enforce_community_event_limit() from anon, authenticated, public;

grant select on communities to anon, authenticated;
grant select on community_events to anon, authenticated;
grant select, insert, update, delete on communities to authenticated;
grant select, insert, update, delete on community_events to authenticated;
