-- ROTARACT QUIZ ADDITIVE UPGRADE
-- Run this AFTER the existing quiz.sql has already been installed.
-- This file does NOT drop/recreate tables and does NOT modify user_roles or admin login.

create index if not exists idx_quiz_participants_quiz_email_lower
  on public.quiz_participants (quiz_id, lower(email)) where email is not null;
create index if not exists idx_quiz_participants_quiz_phone
  on public.quiz_participants (quiz_id, phone) where phone is not null;

-- Registration can be completed before the scheduled start time.
-- Same email OR mobile for the same quiz returns the original registration/code;
-- if email and phone point to two different records, registration is rejected.
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
  v_email text := lower(nullif(trim(p_email),''));
  v_phone text := nullif(regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g'),'');
  v_quiz public.quiz_quizzes;
begin
  if nullif(trim(p_full_name),'') is null then raise exception 'Full name is required'; end if;
  if v_email is null or v_phone is null then raise exception 'Email and mobile number are required'; end if;

  -- Serialize registrations for this quiz so two simultaneous requests cannot bypass checks.
  select * into v_quiz from public.quiz_quizzes where id=p_quiz_id for update;
  if v_quiz.id is null then raise exception 'Quiz not found'; end if;
  if v_quiz.status <> 'published' then raise exception 'Registration is available after the quiz is published'; end if;
  if now() >= ((v_quiz.quiz_date + v_quiz.end_time) at time zone 'Asia/Kathmandu') then
    raise exception 'This quiz has ended; registration is closed';
  end if;

  select qp.id, qp.registration_code into v_id, v_code
  from public.quiz_participants qp
  where qp.quiz_id=p_quiz_id
    and (lower(coalesce(qp.email,''))=v_email
      or regexp_replace(coalesce(qp.phone,''), '[^0-9]', '', 'g')=v_phone)
  order by qp.registered_at
  limit 1;

  if v_id is not null then
    if exists (
      select 1 from public.quiz_participants qp
      where qp.quiz_id=p_quiz_id and qp.id<>v_id
        and (lower(coalesce(qp.email,''))=v_email
          or regexp_replace(coalesce(qp.phone,''), '[^0-9]', '', 'g')=v_phone)
    ) then
      raise exception 'This email and mobile number belong to different registrations. Contact the quiz admin.';
    end if;
    return query select v_id, v_code;
    return;
  end if;

  if v_quiz.max_participants is not null and
     (select count(*) from public.quiz_participants where quiz_id=p_quiz_id) >= v_quiz.max_participants then
    raise exception 'Maximum participant limit reached';
  end if;

  v_code := upper('RAC-' || substr(encode(gen_random_bytes(6),'hex'),1,10));
  insert into public.quiz_participants
    (quiz_id, full_name, email, phone, organization, member_type, registration_code)
  values
    (p_quiz_id, trim(p_full_name), v_email, v_phone,
     nullif(trim(p_organization),''), nullif(trim(p_member_type),''), v_code)
  returning id, registration_code into v_id, v_code;

  return query select v_id, v_code;
end;
$$;

grant execute on function public.quiz_register(uuid,text,text,text,text,text) to anon, authenticated;

-- Admin direct deletes already use the existing quiz_is_admin() RLS policies.
-- Existing admin authentication, user_roles checks, tables, and original quiz.sql stay unchanged.

-- Require the participant's registration code when starting an attempt.
create or replace function public.quiz_start_attempt_by_code(
  p_quiz_id uuid,
  p_code text
)
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
  v_participant_id uuid;
begin
  select p.id into v_participant_id
  from public.quiz_participants p
  where p.quiz_id=p_quiz_id
    and p.registration_code=upper(trim(p_code));
  if v_participant_id is null then raise exception 'Invalid registration code for this quiz'; end if;
  return query select * from public.quiz_start_attempt(v_participant_id);
end;
$$;

-- Public clients must use the code-verifying wrapper, not participant UUID directly.
revoke execute on function public.quiz_start_attempt(uuid) from public, anon, authenticated;
grant execute on function public.quiz_start_attempt_by_code(uuid,text) to anon, authenticated;
