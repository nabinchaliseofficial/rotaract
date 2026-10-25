
-- ROTARACT QUIZ SYSTEM
-- Safe standalone SQL for the existing Supabase project.
-- IMPORTANT: This script does NOT touch existing application tables/triggers.
-- It also avoids the existing generic notify_admin_on_insert() trigger problem.

create extension if not exists pgcrypto;

-- Clean up only objects belonging to this quiz system, if this script is re-run.
drop function if exists public.quiz_leaderboard(uuid);
drop function if exists public.quiz_submit_attempt(uuid, jsonb);
drop function if exists public.quiz_start_attempt(uuid);
drop function if exists public.quiz_get_participant(text);
drop function if exists public.quiz_register(uuid,text,text,text,text,text);
drop function if exists public.quiz_public_info(uuid);
drop function if exists public.quiz_server_time();
drop function if exists public.quiz_questions_public(uuid);
drop function if exists public.quiz_is_admin();

drop table if exists public.quiz_leaderboard cascade;
drop table if exists public.quiz_attempts cascade;
drop table if exists public.quiz_participants cascade;
drop table if exists public.quiz_questions cascade;
drop table if exists public.quiz_quizzes cascade;

create table public.quiz_quizzes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  quiz_date date not null,
  start_time time not null,
  end_time time not null,
  duration_minutes integer not null default 30 check (duration_minutes > 0),
  status text not null default 'draft' check (status in ('draft','published','closed')),
  max_participants integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quiz_time_order check (end_time > start_time)
);

create table public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quiz_quizzes(id) on delete cascade,
  question_no integer not null,
  question_text text not null,
  option_a text not null,
  option_b text not null,
  option_c text not null,
  option_d text not null,
  correct_option char(1) not null check (correct_option in ('A','B','C','D')),
  points numeric(10,2) not null default 1 check (points >= 0),
  created_at timestamptz not null default now(),
  unique (quiz_id, question_no)
);

create table public.quiz_participants (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quiz_quizzes(id) on delete cascade,
  full_name text not null,
  email text,
  phone text,
  organization text,
  member_type text,
  registration_code text not null unique,
  registered_at timestamptz not null default now(),
  unique (quiz_id, email)
);

-- One participant can participate in many quizzes.
create table public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quiz_quizzes(id) on delete cascade,
  participant_id uuid not null references public.quiz_participants(id) on delete cascade,
  started_at timestamptz,
  submitted_at timestamptz,
  score numeric(10,2) not null default 0,
  total_points numeric(10,2) not null default 0,
  correct_answers integer not null default 0,
  wrong_answers integer not null default 0,
  unanswered integer not null default 0,
  time_taken_seconds integer not null default 0,
  rank integer,
  result_status text not null default 'not_started'
    check (result_status in ('not_started','in_progress','submitted','expired')),
  answers jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (quiz_id, participant_id)
);

create table public.quiz_leaderboard (
  attempt_id uuid primary key references public.quiz_attempts(id) on delete cascade,
  quiz_id uuid not null references public.quiz_quizzes(id) on delete cascade,
  participant_id uuid not null references public.quiz_participants(id) on delete cascade,
  full_name text not null,
  organization text,
  score numeric(10,2) not null default 0,
  total_points numeric(10,2) not null default 0,
  time_taken_seconds integer not null default 0,
  rank integer,
  updated_at timestamptz not null default now()
);

create index idx_quiz_questions_quiz on public.quiz_questions(quiz_id, question_no);
create index idx_quiz_participants_quiz on public.quiz_participants(quiz_id);
create index idx_quiz_attempts_quiz on public.quiz_attempts(quiz_id, rank);
create index idx_quiz_leaderboard_quiz on public.quiz_leaderboard(quiz_id, rank);

create or replace function public.quiz_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.user_id = auth.uid()
      and lower(coalesce(ur.role,'')) = 'admin'
      and lower(coalesce(ur.status,'')) = 'active'
  );
$$;

create or replace function public.quiz_server_time()
returns timestamptz
language sql
stable
as $$ select now(); $$;

-- All quiz schedule calculations are explicitly Nepal time.
create or replace function public.quiz_public_info(p_quiz_id uuid)
returns table (
  id uuid,
  title text,
  description text,
  quiz_date date,
  start_time time,
  end_time time,
  duration_minutes integer,
  status text,
  max_participants integer,
  server_now timestamptz,
  starts_at timestamptz,
  ends_at timestamptz,
  is_live boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select q.id, q.title, q.description, q.quiz_date, q.start_time, q.end_time,
         q.duration_minutes, q.status, q.max_participants,
         now(),
         ((q.quiz_date + q.start_time) at time zone 'Asia/Kathmandu'),
         ((q.quiz_date + q.end_time) at time zone 'Asia/Kathmandu'),
         (
           q.status = 'published'
           and now() >= ((q.quiz_date + q.start_time) at time zone 'Asia/Kathmandu')
           and now() <  ((q.quiz_date + q.end_time) at time zone 'Asia/Kathmandu')
         )
  from public.quiz_quizzes q
  where q.id = p_quiz_id;
$$;

-- Public question RPC NEVER exposes correct_option.
create or replace function public.quiz_questions_public(p_quiz_id uuid)
returns table (
  id uuid,
  question_no integer,
  question_text text,
  option_a text,
  option_b text,
  option_c text,
  option_d text,
  points numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select qq.id, qq.question_no, qq.question_text,
         qq.option_a, qq.option_b, qq.option_c, qq.option_d, qq.points
  from public.quiz_questions qq
  join public.quiz_quizzes q on q.id = qq.quiz_id
  where qq.quiz_id = p_quiz_id
    and q.status = 'published'
    and now() >= ((q.quiz_date + q.start_time) at time zone 'Asia/Kathmandu')
    and now() <  ((q.quiz_date + q.end_time) at time zone 'Asia/Kathmandu')
  order by qq.question_no;
$$;

create or replace function public.quiz_register(
  p_quiz_id uuid,
  p_full_name text,
  p_email text default null,
  p_phone text default null,
  p_organization text default null,
  p_member_type text default null
)
returns table(participant_id uuid, registration_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_code text;
begin
  if not exists (
    select 1 from public.quiz_quizzes q
    where q.id = p_quiz_id
      and q.status = 'published'
      and now() >= ((q.quiz_date + q.start_time) at time zone 'Asia/Kathmandu')
      and now() <  ((q.quiz_date + q.end_time) at time zone 'Asia/Kathmandu')
  ) then
    raise exception 'Quiz is not live';
  end if;

  select qp.id, qp.registration_code
    into v_id, v_code
  from public.quiz_participants qp
  where qp.quiz_id = p_quiz_id
    and p_email is not null
    and lower(qp.email) = lower(p_email)
  limit 1;

  if v_id is null then
    v_code := upper('RAC-' || substr(encode(gen_random_bytes(6),'hex'),1,10));
    insert into public.quiz_participants
      (quiz_id, full_name, email, phone, organization, member_type, registration_code)
    values
      (p_quiz_id, trim(p_full_name), nullif(trim(p_email),''), nullif(trim(p_phone),''),
       nullif(trim(p_organization),''), nullif(trim(p_member_type),''), v_code)
    returning id, registration_code into v_id, v_code;
  end if;

  return query select v_id, v_code;
end;
$$;

create or replace function public.quiz_get_participant(p_code text)
returns table(
  id uuid, quiz_id uuid, full_name text, email text, phone text,
  organization text, member_type text, registration_code text
)
language sql
stable
security definer
set search_path = public
as $$
  select id, quiz_id, full_name, email, phone, organization, member_type, registration_code
  from public.quiz_participants
  where registration_code = upper(trim(p_code))
  limit 1;
$$;

create or replace function public.quiz_start_attempt(p_participant_id uuid)
returns table(
  attempt_id uuid,
  server_now timestamptz,
  deadline timestamptz,
  seconds_left integer,
  already_submitted boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.quiz_participants;
  q public.quiz_quizzes;
  a public.quiz_attempts;
  v_end timestamptz;
  v_now timestamptz := now();
begin
  select * into p from public.quiz_participants where id = p_participant_id;
  if p.id is null then raise exception 'Participant not found'; end if;

  select * into q from public.quiz_quizzes where id = p.quiz_id;
  if q.id is null then raise exception 'Quiz not found'; end if;

  v_end := ((q.quiz_date + q.end_time) at time zone 'Asia/Kathmandu');

  if q.status <> 'published' or v_now < ((q.quiz_date + q.start_time) at time zone 'Asia/Kathmandu') or v_now >= v_end then
    raise exception 'Quiz is not live';
  end if;

  select * into a
  from public.quiz_attempts
  where quiz_id = p.quiz_id and participant_id = p.id;

  if a.id is null then
    insert into public.quiz_attempts
      (quiz_id, participant_id, started_at, total_points, result_status)
    select p.quiz_id, p.id, v_now, coalesce(sum(points),0), 'in_progress'
    from public.quiz_questions
    where quiz_id = p.quiz_id
    returning * into a;
  elsif a.result_status in ('submitted','expired') then
    return query select a.id, v_now, v_end,
      greatest(0, floor(extract(epoch from (v_end-v_now)))::int), true;
    return;
  elsif a.started_at is null then
    update public.quiz_attempts
    set started_at=v_now, result_status='in_progress', updated_at=now()
    where id=a.id
    returning * into a;
  end if;

  return query select a.id, v_now, v_end,
    greatest(0, floor(extract(epoch from (v_end-v_now)))::int), false;
end;
$$;

create or replace function public.quiz_submit_attempt(
  p_attempt_id uuid,
  p_answers jsonb
)
returns table(
  attempt_id uuid, score numeric, total_points numeric,
  correct_answers integer, wrong_answers integer, unanswered integer,
  time_taken_seconds integer, rank integer, result_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  a public.quiz_attempts;
  q public.quiz_quizzes;
  v_score numeric := 0;
  v_total numeric := 0;
  v_correct integer := 0;
  v_wrong integer := 0;
  v_unanswered integer := 0;
  v_time integer;
  v_status text;
  v_end timestamptz;
begin
  select * into a from public.quiz_attempts where id=p_attempt_id for update;
  if a.id is null then raise exception 'Attempt not found'; end if;

  select * into q from public.quiz_quizzes where id=a.quiz_id;
  v_end := ((q.quiz_date + q.end_time) at time zone 'Asia/Kathmandu');

  if a.result_status in ('submitted','expired') then
    return query
      select a.id,a.score,a.total_points,a.correct_answers,a.wrong_answers,a.unanswered,
             a.time_taken_seconds,a.rank,a.result_status;
    return;
  end if;

  select coalesce(sum(points),0) into v_total
  from public.quiz_questions where quiz_id=a.quiz_id;

  select
    coalesce(sum(case when upper(coalesce(p_answers ->> qq.question_no::text,'')) = qq.correct_option
                      then qq.points else 0 end),0),
    count(*) filter (where upper(coalesce(p_answers ->> qq.question_no::text,'')) = qq.correct_option),
    count(*) filter (where p_answers ? (qq.question_no::text)
                      and upper(coalesce(p_answers ->> qq.question_no::text,'')) <> qq.correct_option),
    count(*) filter (where not (p_answers ? (qq.question_no::text)))
  into v_score, v_correct, v_wrong, v_unanswered
  from public.quiz_questions qq
  where qq.quiz_id=a.quiz_id;

  v_time := greatest(0, floor(extract(epoch from (least(now(),v_end)-a.started_at)))::int);
  v_status := case when now() >= v_end then 'expired' else 'submitted' end;

  update public.quiz_attempts
  set answers=p_answers, score=v_score, total_points=v_total,
      correct_answers=v_correct, wrong_answers=v_wrong,
      unanswered=v_unanswered, time_taken_seconds=v_time,
      submitted_at=now(), result_status=v_status, updated_at=now()
  where id=a.id
  returning * into a;

  with ranked as (
    select id, row_number() over (
      order by score desc, time_taken_seconds asc, submitted_at asc nulls last, id
    )::int as r
    from public.quiz_attempts
    where quiz_id=a.quiz_id and result_status in ('submitted','expired')
  )
  update public.quiz_attempts x
  set rank=r.r, updated_at=now()
  from ranked r where x.id=r.id;

  select * into a from public.quiz_attempts where id=p_attempt_id;

  return query select a.id,a.score,a.total_points,a.correct_answers,a.wrong_answers,
    a.unanswered,a.time_taken_seconds,a.rank,a.result_status;
end;
$$;

create or replace function public.quiz_leaderboard(p_quiz_id uuid)
returns table(
  rank integer, full_name text, organization text, score numeric,
  total_points numeric, time_taken_seconds integer
)
language sql
stable
security definer
set search_path = public
as $$
  select a.rank, p.full_name, p.organization, a.score, a.total_points, a.time_taken_seconds
  from public.quiz_attempts a
  join public.quiz_participants p on p.id=a.participant_id
  where a.quiz_id=p_quiz_id
    and a.result_status in ('submitted','expired')
  order by a.rank nulls last;
$$;

-- Keep leaderboard automatically synchronized.
create or replace function public.quiz_sync_leaderboard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.quiz_leaderboard where quiz_id = new.quiz_id;
  insert into public.quiz_leaderboard
    (attempt_id, quiz_id, participant_id, full_name, organization, score,
     total_points, time_taken_seconds, rank, updated_at)
  select a.id, a.quiz_id, a.participant_id, p.full_name, p.organization,
         a.score, a.total_points, a.time_taken_seconds, a.rank, now()
  from public.quiz_attempts a
  join public.quiz_participants p on p.id=a.participant_id
  where a.quiz_id=new.quiz_id
    and a.result_status in ('submitted','expired');
  return new;
end;
$$;

create trigger trg_quiz_sync_leaderboard
after insert or update on public.quiz_attempts
for each row execute function public.quiz_sync_leaderboard();

-- RLS
alter table public.quiz_quizzes enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_participants enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.quiz_leaderboard enable row level security;

create policy quiz_quizzes_public_read
on public.quiz_quizzes for select to anon, authenticated
using (status='published');

create policy quiz_quizzes_admin_all
on public.quiz_quizzes for all to authenticated
using (public.quiz_is_admin()) with check (public.quiz_is_admin());

-- IMPORTANT: no direct public select on quiz_questions.
-- Public clients use quiz_questions_public(), which hides correct_option.
create policy quiz_questions_admin_all
on public.quiz_questions for all to authenticated
using (public.quiz_is_admin()) with check (public.quiz_is_admin());

create policy quiz_participants_admin_read
on public.quiz_participants for select to authenticated
using (public.quiz_is_admin());

create policy quiz_participants_admin_write
on public.quiz_participants for all to authenticated
using (public.quiz_is_admin()) with check (public.quiz_is_admin());

create policy quiz_attempts_admin_all
on public.quiz_attempts for all to authenticated
using (public.quiz_is_admin()) with check (public.quiz_is_admin());

create policy quiz_leaderboard_public_read
on public.quiz_leaderboard for select to anon, authenticated
using (true);

create policy quiz_leaderboard_admin_all
on public.quiz_leaderboard for all to authenticated
using (public.quiz_is_admin()) with check (public.quiz_is_admin());

grant execute on function public.quiz_server_time() to anon, authenticated;
grant execute on function public.quiz_public_info(uuid) to anon, authenticated;
grant execute on function public.quiz_questions_public(uuid) to anon, authenticated;
grant execute on function public.quiz_register(uuid,text,text,text,text,text) to anon, authenticated;
grant execute on function public.quiz_get_participant(text) to anon, authenticated;
grant execute on function public.quiz_start_attempt(uuid) to anon, authenticated;
grant execute on function public.quiz_submit_attempt(uuid,jsonb) to anon, authenticated;
grant execute on function public.quiz_leaderboard(uuid) to anon, authenticated;
grant execute on function public.quiz_is_admin() to authenticated;

-- Realtime only for the safe leaderboard table.
do $$
begin
  begin
    alter publication supabase_realtime add table public.quiz_leaderboard;
  exception when duplicate_object then
    null;
  end;
end $$;

-- NOTE:
-- Do NOT attach notify_admin_on_insert() to quiz tables.
-- The existing generic trigger in the user's project assumes NEW.id,
-- but export_table_config has no id column; that caused the reported 42703 error.
