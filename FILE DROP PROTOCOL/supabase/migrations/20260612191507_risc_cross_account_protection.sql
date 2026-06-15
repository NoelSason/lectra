-- Cross-Account Protection (RISC) support

create table if not exists public.risc_events (
  jti          text primary key,
  event_type   text not null,
  subject_sub  text,
  user_id      uuid references auth.users (id) on delete set null,
  reason       text,
  payload      jsonb not null,
  received_at  timestamptz not null default now()
);

create index if not exists risc_events_user_id_idx    on public.risc_events (user_id);
create index if not exists risc_events_received_at_idx on public.risc_events (received_at desc);

alter table public.risc_events enable row level security;

create table if not exists public.risc_account_flags (
  user_id        uuid primary key references auth.users (id) on delete cascade,
  signin_blocked boolean not null default false,
  reason         text,
  updated_at     timestamptz not null default now()
);

alter table public.risc_account_flags enable row level security;

create or replace function public.user_id_for_google_sub(p_sub text)
returns uuid
language sql
security definer
set search_path = auth, public
as $$
  select user_id
  from auth.identities
  where provider = 'google'
    and provider_id = p_sub
  limit 1;
$$;

create or replace function public.revoke_user_sessions(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = auth, public
as $$
declare
  deleted_count integer;
begin
  delete from auth.sessions where user_id = p_user_id;
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.user_id_for_google_sub(text) from public, anon, authenticated;
revoke all on function public.revoke_user_sessions(uuid)   from public, anon, authenticated;
grant execute on function public.user_id_for_google_sub(text) to service_role;
grant execute on function public.revoke_user_sessions(uuid)   to service_role;
