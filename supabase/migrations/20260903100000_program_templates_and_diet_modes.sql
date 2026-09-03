-- A second person arrives, and the generator turns out to be a biography.
--
-- generate_program() hardcoded one man's week: CHEST/BACK alternating Monday
-- and Thursday, ARMS Tuesday, νηστεία on Wednesday and Friday, the meal codes
-- B1/L1/S1/D1/S2, a start date of 2026-09-02 baked into the signature, and 90
-- days because 90 was the number at the time. None of that is wrong for Thanos.
-- All of it is wrong for anyone else.
--
-- Ntinos does not fast at all - no νηστεία, no plant days - eats ketogenic
-- inside a 16:00-00:00 window every single day, and trains four times a week.
-- Encoding that as a second hardcoded branch would double the biography rather
-- than remove it. So the week becomes DATA: a template of (weekday, variant) ->
-- session + menu, and the generator becomes a loop that reads it.
--
-- The second change is macro solving. Today carbohydrate is the leftover:
--
--     carbs = (budget - 4*protein - 9*fat) / 4
--
-- which is exactly right for a balanced plan, where fat is set by the menu's
-- own proportion and carbohydrate absorbs whatever remains. It is exactly
-- BACKWARDS for keto, where carbohydrate is the binding constraint and fat is
-- what expands to fill the budget. Same solver, two modes, chosen per profile.

-- ============================================================ diet modes
alter table public.profiles
  add column if not exists diet_mode text not null default 'balanced'
    check (diet_mode in ('balanced','keto')),
  -- NET carbohydrate ceiling: total carbs minus fibre. Only read in keto mode.
  add column if not exists carb_cap_g numeric(5,1)
    check (carb_cap_g between 10 and 200),
  -- The eating window, for guidance and for the app to render. Nothing in the
  -- energy model cares what time food arrives; adherence very much does.
  add column if not exists eat_window_start time,
  add column if not exists eat_window_end   time,
  -- program length belongs to the person, not to a function signature
  add column if not exists program_days integer not null default 90
    check (program_days between 7 and 365),
  -- Declared here because plan_targets_user below reads it. It stays 1.000 and
  -- inert until migration 20260903130000 gives it something to do.
  add column if not exists tdee_adjustment numeric(4,3) not null default 1.000
    check (tdee_adjustment between 0.80 and 1.20);

comment on column public.profiles.diet_mode is
  'balanced => fat follows the menu proportion, carbohydrate is the remainder.
   keto     => carbohydrate is capped at carb_cap_g NET, fat is the remainder.';
comment on column public.profiles.carb_cap_g is
  'NET carbohydrate ceiling in grams (total minus fibre). Fibre is deliberately
   excluded: it is not absorbed, yields no glucose and does not move ketones, so
   charging it against the cap would force a choice between measurable ketosis
   and eating any vegetables at all. 30 g of chia is 12.6 g of "carbohydrate"
   of which 10.2 g is fibre - on a total-carb budget that one spoonful costs
   half the day to deliver nothing the body absorbs.';
comment on column public.profiles.eat_window_end is
  'May be earlier in clock time than eat_window_start when the window crosses
   midnight, which Ntinos 16:00-00:00 does not but a later variant might.';

-- ==================================================== travel as a day type
-- 'fasting' here has always meant νηστεία - a plant day - and NOT time-
-- restricted eating. Ntinos eats in a window every day and fasts on none of
-- them, so he never uses that value. 'travel' is the genuinely new shape: same
-- targets, different provisioning, because once a week the kitchen is a
-- supermarket in another town.
alter table public.program_days  drop constraint if exists program_days_day_type_check;
alter table public.program_days  add  constraint program_days_day_type_check
  check (day_type in ('regular','fasting','travel'));
alter table public.meals         drop constraint if exists meals_day_type_check;
alter table public.meals         add  constraint meals_day_type_check
  check (day_type in ('regular','fasting','travel','any'));

comment on column public.program_days.day_type is
  'regular | fasting (νηστεία - PLANT day, not time-restricted eating) | travel.';

-- ============================================================ the template
create table if not exists public.program_templates (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
-- one active template per person; older ones stay for history
create unique index if not exists program_templates_one_active
  on public.program_templates (user_id) where active;

create table if not exists public.program_template_days (
  id            bigint generated always as identity primary key,
  template_id   bigint not null references public.program_templates(id) on delete cascade,
  dow           smallint not null check (dow between 1 and 7),   -- 1=Mon..7=Sun
  -- Alternating weeks. variant 0 is also the fallback when 1 is absent, so a
  -- week that does not alternate simply omits it.
  variant       smallint not null default 0 check (variant in (0,1)),
  day_type      text not null default 'regular'
                  check (day_type in ('regular','fasting','travel')),
  exercise_code text,
  meal_codes    text[] not null check (cardinality(meal_codes) between 1 and 8),
  unique (template_id, dow, variant)
);
create index if not exists program_template_days_lookup
  on public.program_template_days (template_id, dow, variant);

comment on column public.program_template_days.variant is
  'Selected by ISO-week parity, so a week alternates against the one before it.
   The old generator did this with hashtext(user || isoweek) % 2, which was
   stable but arbitrary; week parity is the same alternation and can be read
   off a calendar.';

alter table public.program_templates     enable row level security;
alter table public.program_template_days enable row level security;

create policy program_templates_own on public.program_templates for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy program_template_days_own on public.program_template_days for all to authenticated
  using (exists (select 1 from public.program_templates t
                  where t.id = template_id and t.user_id = (select auth.uid())))
  with check (exists (select 1 from public.program_templates t
                  where t.id = template_id and t.user_id = (select auth.uid())));

-- ==================================================== generator, generalised
-- Same contract as before - wipe the plan, lay out N days, hand over to
-- plan_targets - but the week comes out of the template instead of out of a
-- CASE statement, the start date defaults to the profile's own, and the length
-- is an argument because 90 was never a law.
create or replace function public.generate_program_user(
  p_user  uuid,
  p_start date    default null,
  p_days  integer default null
) returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_prof  public.profiles%rowtype;
  v_tpl   bigint;
  v_start date;
  v_days  integer;
  v_day   integer; v_date date; v_dow integer; v_variant smallint;
  r       record;
  v_pd    bigint;
  v_ex    bigint;
  v_p numeric; v_c numeric; v_f numeric; v_k integer; v_n integer := 0;
begin
  if p_user is null then raise exception 'no user'; end if;
  select * into v_prof from public.profiles where id = p_user;
  if not found then raise exception 'no profile for %', p_user; end if;

  select id into v_tpl from public.program_templates
   where user_id = p_user and active order by id desc limit 1;
  if v_tpl is null then raise exception 'no active program template for %', p_user; end if;

  v_start := coalesce(p_start, v_prof.program_start_date);
  v_days  := coalesce(p_days, v_prof.program_days, 90);

  delete from public.program_days where user_id = p_user;

  for v_day in 1..v_days loop
    v_date    := v_start + (v_day - 1);
    v_dow     := extract(isodow from v_date);
    v_variant := (to_char(v_date, 'IW')::int % 2)::smallint;

    -- variant 1 where it exists, variant 0 otherwise: a non-alternating week
    -- just omits the second row.
    select * into r from public.program_template_days
     where template_id = v_tpl and dow = v_dow
     order by (variant = v_variant) desc, variant
     limit 1;
    if not found then
      raise exception 'template % has no row for weekday %', v_tpl, v_dow;
    end if;

    select id into v_ex from public.exercises
     where code = r.exercise_code and user_id is null;

    select sum(m.protein_g), sum(m.carbs_g), sum(m.fat_g), sum(m.kcal)
      into v_p, v_c, v_f, v_k
      from unnest(r.meal_codes) as c(code)
      join public.meals m on m.code = c.code and m.user_id is null;

    if v_k is null then
      raise exception 'template % weekday % references unknown meal codes %',
        v_tpl, v_dow, r.meal_codes;
    end if;

    insert into public.program_days
      (user_id, day_no, day_date, day_type, exercise_id,
       steps_target, water_target_l,
       protein_target_g, carbs_target_g, fat_target_g, kcal_target, menu_kcal)
    values
      (p_user, v_day, v_date, r.day_type, v_ex,
       v_prof.steps_target, v_prof.water_target_l,
       v_p, v_c, v_f, v_k, v_k)
    returning id into v_pd;

    insert into public.program_day_meals (user_id, program_day_id, meal_id, slot_index)
    select p_user, v_pd, m.id, c.ord
      from unnest(r.meal_codes) with ordinality as c(code, ord)
      join public.meals m on m.code = c.code and m.user_id is null;

    v_n := v_n + 1;
  end loop;

  perform public.plan_targets_user(p_user, null);
  return v_n;
end $$;

create or replace function public.generate_program(
  p_start date default null, p_days integer default null
) returns integer language plpgsql security invoker set search_path = '' as $$
declare v_user uuid := (select auth.uid());
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  return public.generate_program_user(v_user, p_start, p_days);
end $$;

grant execute on function public.generate_program_user(uuid, date, integer) to authenticated;
grant execute on function public.generate_program(date, integer) to authenticated;

-- ==================================================== targets, two diet modes
-- Everything about the energy model is unchanged. The only difference is which
-- macro is solved for and which is fixed.
create or replace function public.plan_targets_user(p_user uuid, p_from date default null)
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_user  uuid := p_user;
  v_prof  public.profiles%rowtype;
  r       record;
  v_n     integer := 0;
  v_bw numeric; v_age numeric; v_bmr numeric; v_neat numeric; v_stride numeric;
  v_steps_kcal numeric; v_train_kcal numeric; v_base numeric;
  v_rate numeric; v_budget numeric; v_tdee numeric;
  v_prot numeric; v_fat numeric; v_carb numeric; v_fat_floor numeric;
begin
  if v_user is null then raise exception 'no user'; end if;
  select * into v_prof from public.profiles where id = v_user;

  for r in
    select pd.id, pd.day_date, pd.steps_target, pd.exercise_id,
           coalesce(sum(m.kcal),0)               as menu_k,
           coalesce(sum(m.protein_g),0)          as menu_p,
           coalesce(sum(m.carbs_g),0)            as menu_c,
           coalesce(sum(m.fat_g),0)              as menu_f,
           coalesce(sum(coalesce(m.fiber_g,0)),0) as menu_fib
      from public.program_days pd
      left join public.program_day_meals pdm on pdm.program_day_id = pd.id
      left join public.meals m on m.id = pdm.meal_id
     where pd.user_id = v_user
       and (p_from is null or pd.day_date >= p_from)
     group by pd.id, pd.day_date, pd.steps_target, pd.exercise_id
     order by pd.day_date
  loop
    select coalesce(
      (select d.weight_kg from public.day_logs d
        where d.user_id = v_user and d.weight_kg is not null and d.log_date <= r.day_date
        order by d.log_date desc limit 1), v_prof.start_weight_kg, 88) into v_bw;

    v_age := coalesce(extract(year from age(r.day_date, v_prof.birth_date)), 22);
    v_bmr := 10*v_bw + 6.25*coalesce(v_prof.height_cm,178) - 5*v_age
             + case when coalesce(v_prof.sex,'male')='female' then -161 else 5 end;
    v_neat := v_bmr * (coalesce(v_prof.neat_factor,1.06) - 1.0);

    v_stride := (case when coalesce(v_prof.sex,'male')='female' then 0.413 else 0.415 end)
                * coalesce(v_prof.height_cm,178) / 100.0;
    v_steps_kcal := 0.5 * v_bw * (coalesce(r.steps_target, 10000) * v_stride / 1000.0);

    select case
             when e.category = 'rest' then 0
             when e.kcal_override is not null then e.kcal_override
             else public.session_kcal(e.duration_min, v_bw, e.work_met, e.recovery_met,
                                      e.duty_pct, v_prof.set_seconds, v_prof.rest_seconds,
                                      e.epoc_factor)
           end
      into v_train_kcal
      from public.exercises e where e.id = r.exercise_id;
    v_train_kcal := coalesce(v_train_kcal, 0);

    -- The measured correction. 1.000 until reconcile_tdee has enough honest
    -- days to say otherwise; see migration 20260903130000 for why a model that
    -- cannot be corrected by the scale is the wrong tool for a man who has
    -- already spent seven months proving one wrong.
    v_base := (v_bmr + v_neat + v_steps_kcal + v_train_kcal)
              * coalesce(v_prof.tdee_adjustment, 1.000);

    v_rate := case when r.menu_k > 0
                then (0.25*(4*r.menu_p) + 0.08*(4*r.menu_c) + 0.02*(9*r.menu_f)) / r.menu_k
                -- no menu yet: a keto day's protein share makes TEF ~15%, a
                -- balanced one ~10%. Guessing 10% for keto understates the
                -- budget by ~120 kcal/day.
                else case when v_prof.diet_mode = 'keto' then 0.15 else 0.10 end end;
    v_rate := least(greatest(v_rate, 0.05), 0.20);

    v_budget := (v_base - coalesce(v_prof.deficit_kcal, 500)) / (1 - v_rate);
    v_budget := greatest(v_budget, v_bmr);
    v_budget := coalesce(v_prof.kcal_target_override, v_budget);
    v_tdee   := v_base + v_rate * v_budget;

    v_prot := coalesce(v_prof.protein_target_g,
                       coalesce(v_prof.protein_g_per_kg, 2.10) * v_bw);
    v_fat_floor := 0.6 * v_bw;

    if v_prof.diet_mode = 'keto' then
      -- Carbohydrate is the constraint, fat is the remainder. carbs_target_g is
      -- stored as TOTAL (net cap plus whatever fibre the menu carries) so that
      -- it stays comparable with the carbs the scorer actually sums.
      v_carb := coalesce(v_prof.carb_cap_g, 25)
                + case when r.menu_k > 0 then r.menu_fib else 0 end;
      v_fat  := greatest(v_fat_floor, (v_budget - 4*v_prot - 4*v_carb) / 9.0);
    else
      v_fat  := greatest(v_fat_floor,
                  case when r.menu_k > 0 then r.menu_f * (v_budget / r.menu_k)
                       else v_budget * 0.25 / 9.0 end);
      v_carb := greatest(0, (v_budget - 4*v_prot - 9*v_fat) / 4.0);
    end if;

    update public.program_days set
      kcal_target      = round(v_budget)::int,
      protein_target_g = round(v_prot, 2),
      fat_target_g     = round(v_fat, 2),
      carbs_target_g   = round(v_carb, 2),
      menu_kcal        = round(r.menu_k)::int,
      tdee_est_kcal    = round(v_tdee)::int
    where id = r.id;

    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ==================================================== Thanos's week, as data
-- Lifted verbatim out of the old CASE statement so his plan regenerates
-- identically. Sun rest / Mon chest-or-back / Tue arms / Wed νηστεία treadmill
-- / Thu the other of chest-or-back / Fri νηστεία treadmill / Sat legs.
--
-- The one deliberate difference: menu A/B alternation used to be driven by a
-- running count of fed days, so it drifted across weekday boundaries. Here it
-- is pinned to the weekday and flipped by week parity, which produces the same
-- variety and can actually be read off the calendar.
do $$
declare u uuid; v_tpl bigint;
begin
  for u in select id from public.profiles loop
    if exists (select 1 from public.program_templates where user_id = u) then
      continue;
    end if;

    insert into public.program_templates (user_id, name, active)
    values (u, 'Six-day split, νηστεία Wed + Fri', true)
    returning id into v_tpl;

    insert into public.program_template_days
      (template_id, dow, variant, day_type, exercise_code, meal_codes)
    values
      (v_tpl, 1, 0, 'regular', 'CHEST', array['B1','L1','S1','D1','S2']),
      (v_tpl, 1, 1, 'regular', 'BACK',  array['B2','L2','S1','D2','S2']),
      (v_tpl, 2, 0, 'regular', 'ARMS',  array['B2','L2','S1','D2','S2']),
      (v_tpl, 2, 1, 'regular', 'ARMS',  array['B1','L1','S1','D1','S2']),
      (v_tpl, 3, 0, 'fasting', 'DELT',  array['BF2v2','LF1v2','SF1v2','DF1v2','SF2']),
      (v_tpl, 4, 0, 'regular', 'BACK',  array['B1','L1','S1','D1','S2']),
      (v_tpl, 4, 1, 'regular', 'CHEST', array['B2','L2','S1','D2','S2']),
      (v_tpl, 5, 0, 'fasting', 'FORE',  array['BF3','LF1v2','SF1v2','DF2v2','SF3']),
      (v_tpl, 6, 0, 'regular', 'LEGS',  array['B2','L2','S1','D2','S2']),
      (v_tpl, 6, 1, 'regular', 'LEGS',  array['B1','L1','S1','D1','S2']),
      (v_tpl, 7, 0, 'regular', 'REST',  array['B1','L1','S1','D1','S2']),
      (v_tpl, 7, 1, 'regular', 'REST',  array['B2','L2','S1','D2','S2']);
  end loop;
end $$;

-- Existing profiles keep the balanced solver and their current window.
update public.profiles set diet_mode = 'balanced' where diet_mode is null;
