-- Four corrections agreed after reading the plan as a nutritionist rather than
-- as an engineer.
--
-- 1. Protein was `protein_g_per_kg * current bodyweight`, so the target FELL
--    from 204 g to 190 g as the weight came off. That is backwards: in a
--    deficit, protein needs per kilo rise as you get leaner, because you are
--    defending a fixed amount of lean tissue on less and less energy. It is now
--    a flat number.
--
-- 2. Fibre and vegetables had no targets and no columns. Both are now scored.
--
-- 3. The nutrition score was 60/30/10 protein/kcal/fat. Fat at 10% was nearly
--    free - the menus clear the 0.6 g/kg floor every single day - so it was
--    weight spent on a box already ticked. Fibre takes a share of it.
--
-- 4. Creatine and vitamin D3, plus the coffee-and-iron rule for fasting days.
--    They live in a table rather than in prose so they can be ticked daily,
--    like everything else here.

-- ============================================================ profile targets
alter table public.profiles
  add column if not exists protein_target_g numeric(6,2)
    check (protein_target_g between 40 and 400),
  add column if not exists veg_target_g   integer not null default 400
    check (veg_target_g between 0 and 2000),
  add column if not exists fiber_target_g integer not null default 35
    check (fiber_target_g between 0 and 100);

comment on column public.profiles.protein_target_g is
  'Flat daily protein target in grams. Takes precedence over protein_g_per_kg,
   which scales with bodyweight and therefore falls exactly when protein should
   be defended. Null = fall back to the per-kg calculation.';
comment on column public.profiles.protein_g_per_kg is
  'Legacy. Only consulted when protein_target_g is null.';
comment on column public.profiles.veg_target_g is
  'Non-starchy vegetables, grams/day. ~100 kcal for 400 g - the cheapest
   satiety available on a cut.';

-- 2.33 g/kg at 88 kg, held flat as the weight comes down. The rotation averages
-- 204 g/day across the week; fasting days sit near 186 and the fed days carry it.
update public.profiles set protein_target_g = 205 where protein_target_g is null;

-- ============================================================ score columns
alter table public.daily_scores
  add column if not exists fiber_g numeric(6,2),
  add column if not exists veg_g   numeric(6,1);

-- ============================================================ supplements
create table if not exists public.supplements (
  id          bigint generated always as identity primary key,
  user_id     uuid references auth.users(id) on delete cascade,
  code        text not null,
  kind        text not null default 'supplement' check (kind in ('supplement','habit')),
  name        text not null,
  dose        text not null,
  timing      text not null,
  why         text not null,
  notes       text[],
  sort_order  smallint not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create unique index if not exists supplements_system_code_key
  on public.supplements (code) where user_id is null;

create table if not exists public.supplement_logs (
  id            bigint generated always as identity primary key,
  user_id       uuid   not null references auth.users(id) on delete cascade,
  day_log_id    bigint not null references public.day_logs(id) on delete cascade,
  supplement_id bigint not null references public.supplements(id) on delete cascade,
  taken         boolean not null default true,
  created_at    timestamptz not null default now(),
  unique (day_log_id, supplement_id)
);
create index if not exists supplement_logs_day_idx on public.supplement_logs (day_log_id);
create index if not exists supplement_logs_user_idx on public.supplement_logs (user_id);

alter table public.supplements     enable row level security;
alter table public.supplement_logs enable row level security;

create policy supplements_read on public.supplements for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));
create policy supplements_write on public.supplements for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy supplement_logs_own on public.supplement_logs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

insert into public.supplements (user_id, code, kind, name, dose, timing, why, notes, sort_order) values
  (null, 'CREATINE', 'supplement', 'Creatine monohydrate', '5 g every day',
   'Any time of day, training or rest. With a meal is marginally better; being consistent matters far more than when.',
   'The most evidence-backed supplement there is for holding and adding muscle in a deficit - which is the whole ask here. Wednesday and Friday are plant days carrying essentially no dietary creatine, so the shortfall is real.',
   array[
     'Monohydrate. Not HCl, not "buffered", not a blend - they cost more and none of them has beaten monohydrate in a trial.',
     'No loading phase. 5 g/day saturates in about three weeks; loading gets you there in one, with more stomach upset and no better endpoint.',
     'It pulls 1-2 kg of water INTO muscle over the first weeks. The scale goes UP before it goes down. That is not fat, and it is exactly why the waist tape is the honest read at the two-week review.',
     'Take it on rest days too. It works by saturating the muscle, not by dosing around a session.'], 1),

  (null, 'VITD', 'supplement', 'Vitamin D3', '1000-2000 IU every day',
   'With the fattiest meal of the day - dinner, most days.',
   'Athens sits at 38 degrees north and this block runs to the end of November. From October you make no meaningful vitamin D from sunlight at this latitude, so the back half of the plan is unsupplied at exactly the point a long deficit is taxing recovery.',
   array[
     'D3 (cholecalciferol), not D2. Better absorbed, better retained.',
     'Fat-soluble, so it needs food with fat alongside it. Swallowed with water on an empty stomach you get a fraction of the dose.',
     'Most D3 is lanolin-derived. If that matters on Wednesday and Friday, lichen-derived vegan D3 exists and works the same.'], 2),

  (null, 'IRONCOF', 'habit', 'Coffee, an hour clear of fasting-day meals',
   'No coffee within about 60 minutes either side of Wednesday and Friday lunch and dinner',
   'Wednesday and Friday only.',
   'On fasting days every milligram of iron you eat is non-heme - chickpeas, edamame, lentils, tofu, oats. That is the form coffee polyphenols suppress hardest, and you average 2.5-4 cups a day. Fed days look after themselves: beef, eggs and salmon carry heme iron, which is far less affected.',
   array[
     'Vitamin C pushes the other way, and hard. The tomatoes, peppers and salad leaves already in the fasting lunch measurably raise absorption from that same plate.',
     'Tea does the same thing coffee does. So does a calcium supplement taken with the meal.',
     'Morning coffee before a fasted treadmill session is not the problem. Coffee with the chickpeas is.'], 3)
on conflict (code) where user_id is null do update set
  kind = excluded.kind, name = excluded.name, dose = excluded.dose,
  timing = excluded.timing, why = excluded.why, notes = excluded.notes,
  sort_order = excluded.sort_order, active = true;

-- ==================================================== scoring, with fibre
-- Identical to migration 20260902210000 except for the fibre and vegetable
-- terms and the reweighted nutrition score. Everything about the energy model
-- is unchanged.
create or replace function public.score_day_inner(p_date date)
returns numeric language plpgsql security invoker set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
  v_pd   public.program_days%rowtype;
  v_log  public.day_logs%rowtype;
  v_prof public.profiles%rowtype;
  v_bw numeric; v_h numeric; v_age numeric; v_sex text;
  v_prot numeric := 0; v_carb numeric := 0; v_fat numeric := 0; v_kcal numeric := 0;
  v_fib numeric := 0; v_veg numeric := 0;
  v_vol numeric := 0; v_prev_vol numeric;
  v_cat text; v_kover integer; v_dur integer;
  v_wmet numeric; v_rmet numeric; v_duty numeric; v_epoc numeric;
  v_trained boolean; v_min numeric;
  v_bmr numeric; v_stride numeric; v_km numeric;
  v_neatf numeric; v_neat_kcal numeric; v_tef_kcal numeric;
  v_steps_kcal numeric; v_lift_kcal numeric; v_cardio_kcal numeric;
  v_cardio_min numeric; v_cardio_km numeric; v_train_kcal numeric; v_extra_burn numeric;
  s_prot numeric; s_kcal numeric; s_fat numeric; s_fib numeric;
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
         coalesce(sum(m.fat_g * ml.portion),0),     coalesce(sum(m.kcal * ml.portion),0),
         coalesce(sum(coalesce(m.fiber_g,0) * ml.portion),0),
         coalesce(sum(coalesce(m.veg_g,0)   * ml.portion),0)
    into v_prot, v_carb, v_fat, v_kcal, v_fib, v_veg
    from public.meal_logs ml join public.meals m on m.id = ml.meal_id
   where ml.user_id = v_user and ml.completed and ml.day_log_id = v_dlid;

  -- Off-plan food carries fibre when you fill the label in, but nothing knows
  -- whether it was a vegetable, so veg_g stays a plan-side number.
  select v_prot + coalesce(sum(protein_g),0), v_carb + coalesce(sum(carbs_g),0),
         v_fat  + coalesce(sum(fat_g),0),     v_kcal + coalesce(sum(kcal),0),
         v_fib  + coalesce(sum(fiber_g),0)
    into v_prot, v_carb, v_fat, v_kcal, v_fib
    from public.extra_items where user_id = v_user and kind='food' and day_log_id = v_dlid;

  s_prot := least(100, 100 * power(least(v_prot / nullif(v_pd.protein_target_g,0), 1.0), 1.5));
  s_kcal := greatest(0, 100 - greatest(0,
              (abs(v_kcal - v_pd.kcal_target) / nullif(v_pd.kcal_target,0)) - 0.10) / 0.30 * 100);
  s_fat  := least(100, 100 * v_fat / nullif(0.6 * v_bw, 0));
  s_fib  := least(100, 100 * v_fib / nullif(coalesce(v_prof.fiber_target_g,35), 0));

  -- Fat at 10% was nearly free - the rotation clears 0.6 g/kg every day - so
  -- half of the calorie weight and a slice of protein's now buy fibre instead,
  -- which is the term that actually moves on a bad day.
  s_nut  := coalesce(0.55*s_prot + 0.25*s_kcal + 0.10*s_fat + 0.10*s_fib, 0);

  -- ---------------- training
  select e.category, e.kcal_override, e.duration_min,
         e.work_met, e.recovery_met, e.duty_pct, e.epoc_factor
    into v_cat, v_kover, v_dur, v_wmet, v_rmet, v_duty, v_epoc
    from public.exercises e where e.id = v_pd.exercise_id;

  select coalesce(sum(volume_load),0) into v_vol
    from public.set_logs where user_id = v_user and day_log_id = v_dlid;
  select coalesce(sum(kcal_burned),0) into v_extra_burn
    from public.extra_items where user_id = v_user and kind='exercise' and day_log_id = v_dlid;

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

  -- ---------------- energy out (unchanged)
  v_bmr    := 10*v_bw + 6.25*v_h - 5*v_age + case when v_sex='female' then -161 else 5 end;
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
     neat_kcal, tef_kcal, fiber_g, veg_g, detail, computed_at)
  values
    (v_user, p_date, round(s_nut,2), round(s_tr,2), round(s_mv,2), round(s_rec,2),
     round(s_tot,2), round(v_prot,2), round(v_kcal)::int, round(v_vol,2),
     round(v_bmr)::int, round(v_steps_kcal)::int, round(v_train_kcal)::int,
     round(v_bmr + v_neat_kcal + v_steps_kcal + v_train_kcal + v_tef_kcal)::int,
     round(v_kcal - (v_bmr + v_neat_kcal + v_steps_kcal + v_train_kcal + v_tef_kcal))::int,
     round(v_neat_kcal)::int, round(v_tef_kcal)::int,
     round(v_fib,2), round(v_veg,1),
     jsonb_build_object('protein',round(s_prot,1),'kcal',round(s_kcal,1),'fat',round(s_fat,1),
                        'fibre',round(s_fib,1),
                        'sleep',round(s_sleep,1),'water',round(s_water,1),'readiness',round(s_ready,1),
                        'overload',round(coalesce(s_overload,0),1),'carbs_g',round(v_carb,1),
                        'fiber_g',round(v_fib,1),'veg_g',round(v_veg,0),
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
     tef_kcal=excluded.tef_kcal,               fiber_g=excluded.fiber_g,
     veg_g=excluded.veg_g,                     detail=excluded.detail, computed_at=now();

  return round(s_tot,2);
end $$;

-- ==================================================== flat protein target
-- Identical to migration 20260902210000 except that protein no longer scales
-- with the scale.
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

    v_base := v_bmr + v_neat + v_steps_kcal + v_train_kcal;

    v_rate := case when r.menu_k > 0
                then (0.25*(4*r.menu_p) + 0.08*(4*r.menu_c) + 0.02*(9*r.menu_f)) / r.menu_k
                else 0.10 end;
    v_rate := least(greatest(v_rate, 0.05), 0.20);

    v_budget := (v_base - coalesce(v_prof.deficit_kcal, 500)) / (1 - v_rate);
    v_budget := greatest(v_budget, v_bmr);
    v_budget := coalesce(v_prof.kcal_target_override, v_budget);
    v_tdee   := v_base + v_rate * v_budget;

    -- Flat, not per-kilo. A cut is exactly when a protein target should stop
    -- following the scale down.
    v_prot := coalesce(v_prof.protein_target_g,
                       coalesce(v_prof.protein_g_per_kg, 2.10) * v_bw);
    v_fat  := greatest(0.6 * v_bw,
                case when r.menu_k > 0 then r.menu_f * (v_budget / r.menu_k)
                     else v_budget * 0.25 / 9.0 end);
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

-- ============================================================ backfill
do $$
declare u uuid;
begin
  for u in select id from public.profiles loop
    perform public.plan_targets_user(u, null);
  end loop;
end $$;
