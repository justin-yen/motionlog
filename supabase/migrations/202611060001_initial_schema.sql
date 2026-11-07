create extension if not exists "pgcrypto";

create type public.tracking_mode as enum ('reps', 'duration');
create type public.weight_unit as enum ('lb', 'kg');
create type public.transcription_status as enum ('pending', 'processing', 'complete', 'failed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  tracking_mode public.tracking_mode,
  instructions text[],
  image_path text,
  video_url text,
  pt_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.routines (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text,
  scheduled_for date not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, scheduled_for)
);

create table public.routine_items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  routine_id uuid not null references public.routines(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  position integer not null check (position >= 0),
  target_sets integer check (target_sets > 0),
  target_reps integer check (target_reps > 0),
  target_duration_seconds integer check (target_duration_seconds > 0),
  target_band_resistance text,
  target_weight_value numeric(8,2) check (target_weight_value >= 0),
  target_weight_unit public.weight_unit,
  prescription_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (routine_id, position)
);

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  routine_id uuid references public.routines(id) on delete set null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  general_notes text,
  created_at timestamptz not null default now()
);

create table public.exercise_logs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete set null,
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  routine_item_id uuid references public.routine_items(id) on delete set null,
  performed_at timestamptz not null default now(),
  sets_completed integer check (sets_completed > 0),
  reps_per_set integer check (reps_per_set > 0),
  duration_seconds integer check (duration_seconds > 0),
  band_resistance text,
  weight_value numeric(8,2) check (weight_value >= 0),
  weight_unit public.weight_unit,
  pain_before smallint check (pain_before between 0 and 10),
  pain_after smallint check (pain_after between 0 and 10),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audio_recordings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete cascade,
  exercise_log_id uuid references public.exercise_logs(id) on delete set null,
  storage_path text,
  duration_seconds numeric(8,2) check (duration_seconds >= 0),
  transcript text,
  structured_data jsonb,
  transcription_status public.transcription_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index routines_owner_date_idx on public.routines(owner_id, scheduled_for desc);
create index routine_items_routine_position_idx on public.routine_items(routine_id, position);
create index exercise_logs_owner_performed_idx on public.exercise_logs(owner_id, performed_at desc);
create index audio_recordings_owner_created_idx on public.audio_recordings(owner_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger exercises_set_updated_at before update on public.exercises
for each row execute function public.set_updated_at();
create trigger routines_set_updated_at before update on public.routines
for each row execute function public.set_updated_at();
create trigger routine_items_set_updated_at before update on public.routine_items
for each row execute function public.set_updated_at();
create trigger exercise_logs_set_updated_at before update on public.exercise_logs
for each row execute function public.set_updated_at();
create trigger audio_recordings_set_updated_at before update on public.audio_recordings
for each row execute function public.set_updated_at();

create or replace function public.create_profile_for_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.create_profile_for_new_user();

alter table public.profiles enable row level security;
alter table public.exercises enable row level security;
alter table public.routines enable row level security;
alter table public.routine_items enable row level security;
alter table public.sessions enable row level security;
alter table public.exercise_logs enable row level security;
alter table public.audio_recordings enable row level security;

create policy "profiles are owned" on public.profiles for all
using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "exercises are owned" on public.exercises for all
using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "routines are owned" on public.routines for all
using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "routine items are owned" on public.routine_items for all
using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "sessions are owned" on public.sessions for all
using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "exercise logs are owned" on public.exercise_logs for all
using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "audio recordings are owned" on public.audio_recordings for all
using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('session-audio', 'session-audio', false, 26214400, array['audio/mp4', 'audio/x-m4a', 'audio/m4a'])
on conflict (id) do nothing;

create policy "users upload their own session audio"
on storage.objects for insert to authenticated
with check (bucket_id = 'session-audio' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "users read their own session audio"
on storage.objects for select to authenticated
using (bucket_id = 'session-audio' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "users update their own session audio"
on storage.objects for update to authenticated
using (bucket_id = 'session-audio' and (storage.foldername(name))[1] = (select auth.uid())::text)
with check (bucket_id = 'session-audio' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "users delete their own session audio"
on storage.objects for delete to authenticated
using (bucket_id = 'session-audio' and (storage.foldername(name))[1] = (select auth.uid())::text);

create view public.weekly_adherence
with (security_invoker = true) as
select
  r.owner_id,
  date_trunc('week', r.scheduled_for::timestamptz)::date as week_start,
  count(ri.id)::integer as prescribed_exercises,
  count(distinct el.routine_item_id)::integer as completed_exercises
from public.routines r
join public.routine_items ri on ri.routine_id = r.id
left join public.exercise_logs el on el.routine_item_id = ri.id
group by r.owner_id, date_trunc('week', r.scheduled_for::timestamptz);

grant select on public.weekly_adherence to authenticated;
