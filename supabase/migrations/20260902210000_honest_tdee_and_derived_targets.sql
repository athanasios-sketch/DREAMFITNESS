-- The energy model was measuring two different things and calling them a plan.
--
-- "Out" was BMR + steps + training. That leaves out the thermic effect of food
-- entirely - on a plan built around 2.3 g/kg of protein, ~300 kcal a day - and
-- all the non-walking movement a day contains. So burn read low.
--
-- "In" was the sum of whatever meals the rotation happened to schedule.
-- Nothing connected it to expenditure. The apparent -112 kcal/day deficit was
-- an artefact of both errors, not a decision: correct the burn and the same
-- menus are actually running a ~500 deficit on training days, and a ~250
-- SURPLUS against target on rest days, when no session is there to pay for the
-- fed-day menu.
--
-- After this migration the target is derived - expenditure minus the deficit
-- you actually chose - and the menu total is stored beside it so the gap is
-- visible instead of implied.

-- ============================================================ profile inputs
alter table public.profiles
  -- non-step NEAT only. See the comment in score_day_inner for why it is small.
  add column if not exists neat_factor numeric(4,2) not null default 1.06
    check (neat_factor between 1.00 and 1.40),
  -- the deficit you are actually aiming for, in kcal/day. 500 is ~0.45 kg/week.
  add column if not exists deficit_kcal integer not null default 500
    check (deficit_kcal between 0 and 1200);

-- activity_multiplier was a whole-day TDEE multiplier, which is the wrong shape
-- for a model that counts steps and training explicitly - applying it would
-- charge for that movement twice. It has never been read by any query. Retired
-- rather than left sitting at 1.6 looking like it does something.
alter table public.profiles alter column activity_multiplier drop not null;
update public.profiles set activity_multiplier = null;
comment on column public.profiles.activity_multiplier is
  'DEPRECATED and unused. Superseded by neat_factor + explicit steps/training.
   A whole-day multiplier double-counts movement this model already prices.';
comment on column public.profiles.neat_factor is
  'Multiplier on BMR for non-exercise movement NOT already counted by steps.';
comment on column public.profiles.deficit_kcal is
  'Intended daily energy deficit. Drives program_days.kcal_target.';
comment on column public.profiles.kcal_target_override is
  'Hard override for the derived daily budget. Null = derive it.';

-- ============================================================ score columns
alter table public.daily_scores
  add column if not exists neat_kcal integer,
  add column if not exists tef_kcal  integer;
comment on column public.daily_scores.tef_kcal is
  'Thermic effect of food, from the macros actually eaten: 25% of protein
   energy, 8% of carbohydrate, 2% of fat.';

-- ============================================================ plan columns
alter table public.program_days
  -- what the scheduled meals actually serve, as distinct from what you should eat
  add column if not exists menu_kcal     integer,
  add column if not exists tdee_est_kcal integer;
comment on column public.program_days.kcal_target is
  'The budget: expected expenditure minus profiles.deficit_kcal. Derived by
   plan_targets(), NOT the sum of the scheduled meals - see menu_kcal.';
comment on column public.program_days.menu_kcal is
  'What the scheduled meals add up to. Differs from kcal_target when the
   rotation over- or under-serves the day.';

-- ==================================================== the honest daily burn
create or replace function public.score_day_inner(p_date date)
returns numeric language plpgsql security invoker set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
  v_pd   public.program_days%rowtype;
  v_log  public.day_logs%rowtype;
  v_prof public.profiles%rowtype;
  v_bw numeric; v_h numeric; v_age numeric; v_sex text;
  v_prot numeric := 0; v_carb numeric := 0; v_fat numeric := 0; v_kcal numeric := 0;
  v_vol numeric := 0; v_prev_vol numeric;
  v_cat text; v_kover integer; v_dur integer;
  v_wmet numeric; v_rmet numeric; v_duty numeric; v_epoc numeric;
  v_trained boolean; v_min numeric;
  v_bmr numeric; v_stride numeric; v_km numeric;
  v_neatf numeric; v_neat_kcal numeric; v_tef_kcal numeric;
  v_steps_kcal numeric; v_lift_kcal numeric; v_cardio_kcal numeric;
  v_cardio_min numeric; v_cardio_km numeric; v_train_kcal numeric; v_extra_burn numeric;
  s_prot numeric; s_kcal numeric; s_fat numeric;
  s_nut numeric; s_tr numeric; s_mv numeric; s_rec numeric; s_tot numeric;
  s_sleep numeric; s_water numeric; s_ready numeric; s_overload numeric;
  v_dlid bigint;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  select * into v_pd from public.program_days where user_id = v_user and day_date = p_date;
  if not found then return null; end if;
  select * into v_log  from public.day_logs where user_id = v_user and log_date = p_date;
  v_dlid := v_log.id;
  select * into v_prof from public.profiles where id = v_user;

  select coalesce(
    (select d.weight_kg from public.day_logs d
      where d.user_id = v_user and d.weight_kg is not null and d.log_date <= p_date
      order by d.log_date desc limit 1), v_prof.start_weight_kg, 88) into v_bw;
  v_h   := coalesce(v_prof.height_cm, 178);
  v_sex := coalesce(v_prof.sex, 'male');
  v_age := coalesce(extract(year from age(p_date, v_prof.birth_date)), 22);

  -- ---------------- intake
  select coalesce(sum(m.protein_g * ml.portion),0), coalesce(sum(m.carbs_g * ml.portion),0),
         coalesce(sum(m.fat_g * ml.portion),0),     coalesce(sum(m.kcal * ml.portion),0)
    into v_prot, v_carb, v_fat, v_kcal
    from public.meal_logs ml join public.meals m on m.id = ml.meal_id
   where ml.user_id = v_user and ml.completed and ml.day_log_id = v_dlid;

  select v_prot + coalesce(sum(protein_g),0), v_carb + coalesce(sum(carbs_g),0),
         v_fat  + coalesce(sum(fat_g),0),     v_kcal + coalesce(sum(kcal),0)
    into v_prot, v_carb, v_fat, v_kcal
    from public.extra_items where user_id = v_user and kind='food' and day_log_id = v_dlid;

  s_prot := least(100, 100 * power(least(v_prot / nullif(v_pd.protein_target_g,0), 1.0), 1.5));
  s_kcal := greatest(0, 100 - greatest(0,
              (abs(v_kcal - v_pd.kcal_target) / nullif(v_pd.kcal_target,0)) - 0.10) / 0.30 * 100);
  s_fat  := least(100, 100 * v_fat / nullif(0.6 * v_bw, 0));
  s_nut  := coalesce(0.60*s_prot + 0.30*s_kcal + 0.10*s_fat, 0);

  -- ---------------- training
  select e.category, e.kcal_override, e.duration_min,
         e.work_met, e.recovery_met, e.duty_pct, e.epoc_factor
    into v_cat, v_kover, v_dur, v_wmet, v_rmet, v_duty, v_epoc
    from public.exercises e where e.id = v_pd.exercise_id;

  select coalesce(sum(volume_load),0) into v_vol
    from public.set_logs where user_id = v_user and day_log_id = v_dlid;
  select coalesce(sum(kcal_burned),0) into v_extra_burn
    from public.extra_items where user_id = v_user and kind='exercise' and day_log_id = v_dlid;

  -- Timed movements run continuously (duty 1.0). Where distance and duration
  -- are both present the intensity comes from the pace you actually held;
  -- otherwise it falls back to the movement's own MET.
  select coalesce(sum(sl.duration_sec) / 60.0, 0),
         coalesce(sum(sl.distance_km), 0),
         coalesce(sum(public.session_kcal(
           sl.duration_sec / 60.0, v_bw,
           case when coalesce(sl.distance_km,0) > 0 and sl.duration_sec > 0
                then public.walk_run_met(
                       sl.distance_km / (sl.duration_sec / 3600.0), sl.incline_pct)
                else coalesce(mv.met, 6.0) end,
           case when coalesce(sl.distance_km,0) > 0 and sl.duration_sec > 0
                then public.walk_run_met(
                       sl.distance_km / (sl.duration_sec / 3600.0), sl.incline_pct)
                else coalesce(mv.met, 6.0) end,
           1.0, v_prof.set_seconds, v_prof.rest_seconds, 1.0)), 0)
    into v_cardio_min, v_cardio_km, v_cardio_kcal
    from public.set_logs sl
    join public.exercise_movements mv on mv.id = sl.movement_id
   where sl.user_id = v_user and sl.day_log_id = v_dlid
     and mv.tracking = 'time' and sl.duration_sec is not null;

  v_trained := v_vol > 0
            or coalesce(v_log.training_minutes,0) > 0
            or coalesce(v_cardio_min,0) > 0
            or exists (select 1 from public.extra_items
                        where user_id = v_user and kind='exercise' and day_log_id = v_dlid);

  if v_cat = 'rest' then
    s_tr := 100;
  elsif v_cat in ('cardio','mixed') then
    s_tr := case when v_trained then 100 else 0 end;
  else
    select avg(t.v) into v_prev_vol from (
      select sum(sl.volume_load) as v from public.set_logs sl
        join public.day_logs dl on dl.id = sl.day_log_id
       where sl.user_id = v_user and sl.exercise_id = v_pd.exercise_id and dl.log_date < p_date
       group by dl.log_date order by dl.log_date desc limit 3) t;
    s_overload := case when v_prev_vol is null or v_prev_vol = 0 then 100
                       else least(100, 100 * v_vol / v_prev_vol) end;
    s_tr := case when v_vol > 0 then 70 + 0.30*s_overload
                 when v_trained then 60 else 0 end;
  end if;

  -- ---------------- energy out
  v_bmr    := 10*v_bw + 6.25*v_h - 5*v_age + case when v_sex='female' then -161 else 5 end;

  -- NEAT that the step count does not already contain: standing, cooking,
  -- carrying, fidgeting, posture. Deliberately small (6%), because walking is
  -- the bulk of non-exercise movement and it is counted explicitly below - a
  -- classic 1.2 "sedentary" multiplier would charge for those steps twice.
  -- Understating burn is the safe direction on a cut: it prescribes less food,
  -- never more.
  v_neatf     := coalesce(v_prof.neat_factor, 1.06);
  v_neat_kcal := v_bmr * (v_neatf - 1.0);
  v_stride := (case when v_sex='female' then 0.413 else 0.415 end) * v_h / 100.0;
  v_km     := coalesce(v_log.steps,0) * v_stride / 1000.0;
  v_steps_kcal := 0.5 * v_bw * v_km;

  v_min := coalesce(v_log.training_minutes, case when v_vol > 0 then v_dur else 0 end);
  v_lift_kcal := case
    when coalesce(v_min,0) <= 0 then 0
    when v_kover is not null and coalesce(v_dur,0) > 0 then v_kover * (v_min / v_dur)
    when v_kover is not null then v_kover
    else public.session_kcal(v_min, v_bw, v_wmet, v_rmet, v_duty,
                             v_prof.set_seconds, v_prof.rest_seconds, v_epoc)
  end;
  v_train_kcal := v_lift_kcal + coalesce(v_cardio_kcal,0) + coalesce(v_extra_burn,0);

  -- Thermic effect of food. Digestion is not free and it is not a flat 10%:
  -- protein costs 20-30% of its own energy to process, carbohydrate 5-10%, fat
  -- almost nothing. On a plan built around 2.3 g/kg of protein that difference
  -- is worth ~90 kcal a day over the flat assumption, so it is computed from
  -- the macros actually eaten rather than from the calorie total.
  v_tef_kcal := 0.25 * (4*v_prot) + 0.08 * (4*v_carb) + 0.02 * (9*v_fat);

  s_mv := least(100, 100 * coalesce(v_log.steps,0) / nullif(v_pd.steps_target,0));
  s_sleep := case when v_log.sleep_hours is null then 0
                  when v_log.sleep_hours between 7 and 9 then 100
                  when v_log.sleep_hours < 7 then greatest(0, 100 - (7-v_log.sleep_hours)*25)
                  else greatest(0, 100 - (v_log.sleep_hours-9)*15) end;
  s_water := least(100, 100 * coalesce(v_log.water_l,0) / nullif(v_pd.water_target_l,0));
  s_ready := case when v_log.energy is null and v_log.soreness is null then 0
                  else (coalesce(v_log.energy,3)*20*0.6) + ((6-coalesce(v_log.soreness,3))*20*0.4) end;
  s_rec := 0.50*s_sleep + 0.30*s_water + 0.20*s_ready;

  s_tot := 0.35*s_nut + 0.30*s_tr + 0.15*s_mv + 0.20*s_rec;

  insert into public.daily_scores
    (user_id, score_date, nutrition_score, training_score, movement_score, recovery_score,
     total_score, protein_actual_g, kcal_actual, volume_load,
     bmr_kcal, steps_kcal, training_kcal, burn_kcal, energy_balance,
     neat_kcal, tef_kcal, detail, computed_at)
  values
    (v_user, p_date, round(s_nut,2), round(s_tr,2), round(s_mv,2), round(s_rec,2),
     round(s_tot,2), round(v_prot,2), round(v_kcal)::int, round(v_vol,2),
     round(v_bmr)::int, round(v_steps_kcal)::int, round(v_train_kcal)::int,
     round(v_bmr + v_neat_kcal + v_steps_kcal + v_train_kcal + v_tef_kcal)::int,
     round(v_kcal - (v_bmr + v_neat_kcal + v_steps_kcal + v_train_kcal + v_tef_kcal))::int,
     round(v_neat_kcal)::int, round(v_tef_kcal)::int,
     jsonb_build_object('protein',round(s_prot,1),'kcal',round(s_kcal,1),'fat',round(s_fat,1),
                        'sleep',round(s_sleep,1),'water',round(s_water,1),'readiness',round(s_ready,1),
                        'overload',round(coalesce(s_overload,0),1),'carbs_g',round(v_carb,1),
                        'bodyweight_kg',v_bw,'km_walked',round(v_km,2),
                        'coffee_cups',coalesce(v_log.coffee_cups,0),
                        'lift_min',round(coalesce(v_min,0),1),
                        'lift_kcal',round(coalesce(v_lift_kcal,0)),
                        'cardio_min',round(coalesce(v_cardio_min,0),1),
                        'cardio_km',round(coalesce(v_cardio_km,0),2),
                        'cardio_kcal',round(coalesce(v_cardio_kcal,0)),
                        'neat_kcal',round(v_neat_kcal),'tef_kcal',round(v_tef_kcal),
                        'menu_kcal',v_pd.menu_kcal,'tdee_est_kcal',v_pd.tdee_est_kcal),
     now())
  on conflict (user_id, score_date) do update set
     nutrition_score=excluded.nutrition_score, training_score=excluded.training_score,
     movement_score=excluded.movement_score,   recovery_score=excluded.recovery_score,
     total_score=excluded.total_score,         protein_actual_g=excluded.protein_actual_g,
     kcal_actual=excluded.kcal_actual,         volume_load=excluded.volume_load,
     bmr_kcal=excluded.bmr_kcal,               steps_kcal=excluded.steps_kcal,
     training_kcal=excluded.training_kcal,     burn_kcal=excluded.burn_kcal,
     energy_balance=excluded.energy_balance,   neat_kcal=excluded.neat_kcal,
     tef_kcal=excluded.tef_kcal,               detail=excluded.detail, computed_at=now();

  return round(s_tot,2);
end $$;

-- ==================================================== derived daily targets
-- What you should eat is a consequence of what you spend, not of which meals
-- the rotation happened to pick.
--
-- The circularity is real and worth being careful about: the budget depends on
-- TDEE, TDEE includes TEF, and TEF depends on what you eat. Solving it rather
-- than guessing:
--
--     in - out = -deficit,  out = base + r*in     (r = TEF as a share of intake)
--  => in = (base - deficit) / (1 - r)
--
-- r comes from the menu's macro split, which is scale-invariant, so it holds
-- however far the portions are scaled. base is BMR + non-step NEAT + the steps
-- you are targeting + the session the day is scheduled to do.
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
  v_prot numeric; v_fat numeric; v_carb numeric;
begin
  if v_user is null then raise exception 'no user'; end if;
  select * into v_prof from public.profiles where id = v_user;

  for r in
    select pd.id, pd.day_date, pd.steps_target, pd.exercise_id,
           coalesce(sum(m.kcal),0)      as menu_k,
           coalesce(sum(m.protein_g),0) as menu_p,
           coalesce(sum(m.carbs_g),0)   as menu_c,
           coalesce(sum(m.fat_g),0)     as menu_f
      from public.program_days pd
      left join public.program_day_meals pdm on pdm.program_day_id = pd.id
      left join public.meals m on m.id = pdm.meal_id
     where pd.user_id = v_user
       and (p_from is null or pd.day_date >= p_from)
     group by pd.id, pd.day_date, pd.steps_target, pd.exercise_id
     order by pd.day_date
  loop
    -- Bodyweight AS KNOWN ON THAT DAY, the same lookup score_day uses. A future
    -- day has no weight yet and correctly falls back to the latest one, so the
    -- whole plan re-tightens by itself every time you step on the scale.
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

    -- the session the day is PLANNED to do, priced with the same model that
    -- scores the one you actually did
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

    v_base := v_bmr + v_neat + v_steps_kcal + v_train_kcal;

    -- TEF as a share of intake, from the menu's own macro split. Clamped
    -- because a pathological menu should not be able to move the budget far.
    v_rate := case when r.menu_k > 0
                then (0.25*(4*r.menu_p) + 0.08*(4*r.menu_c) + 0.02*(9*r.menu_f)) / r.menu_k
                else 0.10 end;
    v_rate := least(greatest(v_rate, 0.05), 0.20);

    v_budget := (v_base - coalesce(v_prof.deficit_kcal, 500)) / (1 - v_rate);

    -- Never prescribe below resting metabolism, whatever the arithmetic says.
    -- A rest day with a low step target can otherwise solve to a number no one
    -- should eat for 90 days.
    v_budget := greatest(v_budget, v_bmr);
    v_budget := coalesce(v_prof.kcal_target_override, v_budget);

    -- by construction budget - tdee = -deficit, which is the point
    v_tdee := v_base + v_rate * v_budget;

    -- Protein is set by bodyweight, not by the menu - it is the one target that
    -- should not move when the calorie budget does.
    v_prot := coalesce(v_prof.protein_g_per_kg, 2.10) * v_bw;
    -- Fat keeps the menu's proportion but never drops under 0.6 g/kg, which is
    -- the floor where hormones start to notice a long cut.
    v_fat  := greatest(0.6 * v_bw,
                case when r.menu_k > 0 then r.menu_f * (v_budget / r.menu_k)
                     else v_budget * 0.25 / 9.0 end);
    -- carbohydrate is the remainder: it fuels the session, it is not a target
    v_carb := greatest(0, (v_budget - 4*v_prot - 9*v_fat) / 4.0);

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

-- The authenticated entry point. Same body, your own rows only.
create or replace function public.plan_targets(p_from date default null)
returns integer language plpgsql security invoker set search_path = '' as $$
declare v_user uuid := (select auth.uid());
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  return public.plan_targets_user(v_user, p_from);
end $$;

grant execute on function public.plan_targets(date) to authenticated;
grant execute on function public.plan_targets_user(uuid, date) to authenticated;

-- ==================================================== keep targets current
-- Targets follow bodyweight, so they go stale the moment you log the scale.
-- rescore_all already exists as the "the model changed, reach back through the
-- history" hook; retargeting belongs in front of it, or the rescore would use
-- yesterday's budget.
create or replace function public.rescore_all(p_from date default null)
returns integer language plpgsql security invoker set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_d date; v_n integer := 0;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  perform public.plan_targets(p_from);
  for v_d in select log_date from public.day_logs
              where user_id = v_user and (p_from is null or log_date >= p_from)
              order by log_date
  loop
    perform public.score_day(v_d);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- generate_program writes the menu sums as a placeholder, then hands over to
-- plan_targets for the numbers that actually matter.
create or replace function public.generate_program(p_start date default '2026-09-02')
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_user  uuid := (select auth.uid());
  v_day   integer; v_date date; v_dow integer; v_fast boolean;
  v_pd bigint; v_codes text[]; v_ex text; v_chest_monday boolean;
  v_reg   integer := 0;
  v_p numeric; v_c numeric; v_f numeric; v_k integer; v_n integer := 0;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  delete from public.program_days where user_id = v_user;

  for v_day in 1..90 loop
    v_date := p_start + (v_day - 1);
    v_dow  := extract(isodow from v_date);
    v_fast := v_dow in (3, 5);

    v_chest_monday := (abs(hashtext(v_user::text || to_char(v_date, 'IYYY-IW'))) % 2) = 0;

    v_ex := case v_dow
              when 1 then case when v_chest_monday then 'CHEST' else 'BACK'  end
              when 2 then 'ARMS'
              when 3 then 'DELT'
              when 4 then case when v_chest_monday then 'BACK'  else 'CHEST' end
              when 5 then 'FORE'
              when 6 then 'LEGS'
              when 7 then 'REST'
            end;

    if v_fast then
      v_codes := case when v_dow = 3
                   then array['BF2v2','LF1v2','SF1v2','DF1v2','SF2']
                   else array['BF3','LF1v2','SF1v2','DF2v2','SF3'] end;
    else
      v_reg := v_reg + 1;
      v_codes := case when v_reg % 2 = 1
                   then array['B1','L1','S1','D1','S2']
                   else array['B2','L2','S1','D2','S2'] end;
    end if;

    select sum(m.protein_g), sum(m.carbs_g), sum(m.fat_g), sum(m.kcal)
      into v_p, v_c, v_f, v_k
      from unnest(v_codes) as c(code)
      join public.meals m on m.code = c.code and m.user_id is null;

    insert into public.program_days
      (user_id, day_no, day_date, day_type, exercise_id,
       protein_target_g, carbs_target_g, fat_target_g, kcal_target, menu_kcal)
    values
      (v_user, v_day, v_date, case when v_fast then 'fasting' else 'regular' end,
       (select id from public.exercises where code = v_ex and user_id is null),
       v_p, v_c, v_f, v_k, v_k)
    returning id into v_pd;

    insert into public.program_day_meals (user_id, program_day_id, meal_id, slot_index)
    select v_user, v_pd, m.id, c.ord
      from unnest(v_codes) with ordinality as c(code, ord)
      join public.meals m on m.code = c.code and m.user_id is null;

    v_n := v_n + 1;
  end loop;

  perform public.plan_targets();
  return v_n;
end $$;

-- ============================================================ backfill
-- auth.uid() is null inside a migration, so the plan is retargeted per user
-- through the explicit-user entry point. Scores are left to the app: score_day
-- is invoker-only and every write path already recomputes the day it touched.
do $$
declare u uuid;
begin
  for u in select id from public.profiles loop
    perform public.plan_targets_user(u, null);
  end loop;
end $$;
