-- Ntinos's side of the reference data: the sessions, the supplements a keto cut
-- actually needs, ketone logging, and a nutrition score that knows what a
-- carbohydrate cap is.
--
-- The training split here is a deliberate argument against the thing he said he
-- was about to do, which was lighten the bar and add reps. That is the standard
-- instinct on a cut and it is the one that costs muscle. Bickel (2011) held
-- trained men at their gains for THIRTY-TWO WEEKS on a third of their previous
-- volume, provided the load stayed at 75-80% of 1RM: the retention signal is
-- the weight on the bar, and the thing that outruns recovery in a deficit is
-- the volume around it. So the sets come down and the load does not.
--
-- There is a ketogenic reason on top of the general one. The 2024 meta-analysis
-- on keto and strength found no effect on 1RM squat or bench - heavy low-rep
-- work is phosphocreatine-driven and does not care about muscle glycogen. High
-- rep work does. His 80 kg x 15 squat is the single most glycogen-dependent
-- thing in his week and it is exactly what will fall apart first on 28 g of
-- carbohydrate. Adding reps points the programme straight at the one quality
-- the diet degrades.

-- ============================================================ ketones
alter table public.day_logs
  add column if not exists ketones_mmol numeric(4,2)
    check (ketones_mmol between 0 and 10);

comment on column public.day_logs.ketones_mmol is
  'Blood beta-hydroxybutyrate, mmol/L. Blood, not urine: strips stop reading
   after 2-4 weeks once the kidneys stop dumping what they are no longer wasting.

   TRACKED BUT DELIBERATELY NOT SCORED. Nutritional ketosis is 0.5-3.0 and
   higher is not better - a reading above that range usually means protein came
   in low, which is the one mistake this whole plan exists to prevent. Scoring
   the number would pay him to make it. The score rewards the BEHAVIOUR instead,
   via the carbohydrate cap below.

   Expect a low reading right after training. Gluconeogenesis and lactate both
   suppress BHB, he lifts at 15:00 and tests around 16:00, so the worst number
   of his week will follow his best session. That is physiology, not a failure.';

-- ============================================================ the sessions
-- Four lifting days, three rest. Wednesday sits between the two heavy upper
-- days and Saturday/Sunday carry the travel that happens once a week anyway.
insert into public.exercises
  (user_id, code, name, category, focus, duration_min, work_met, recovery_met,
   duty_pct, epoc_factor, notes)
values
  (null, 'KUA', 'Upper A - heavy press', 'resistance', 'chest, shoulders, triceps',
   65, 6.0, 2.5, 0.28, 1.08,
   'Bench stays at 100 kg. Three working sets of 4-6, not five sets of twelve at
    70 - the load is what tells the tissue to stay. Stop each set with one rep
    in reserve and do not chase a PR in a deficit; holding the number you
    already own IS the win for the next seven months.'),
  (null, 'KLA', 'Lower A - heavy squat', 'resistance', 'quads, glutes',
   65, 6.5, 2.5, 0.26, 1.10,
   'The 80 kg x 15 goes. Squat 4-6 reps at a weight that makes six hard, three
    sets. High-rep squatting is the most glycogen-hungry work in the week and on
    28 g of carbohydrate it will feel dreadful and buy the least - the exact
    combination worth cutting first.'),
  (null, 'KUB', 'Upper B - heavy pull', 'resistance', 'back, biceps, rear delts',
   65, 6.0, 2.5, 0.28, 1.08,
   'Rows and pulldowns/chins in the same 4-8 window. His segmental scan is
    symmetric - 4.4 kg of muscle in each arm - so there is nothing to correct
    here, only something to keep.'),
  (null, 'KLB', 'Lower B - hinge', 'resistance', 'hamstrings, glutes, posterior chain',
   60, 6.5, 2.5, 0.26, 1.10,
   'Romanian deadlift or trap-bar, 4-6 reps, three sets. The hinge is the least
    represented pattern in what he has been doing and the cheapest place left to
    add strength without adding fatigue.')
on conflict (code) where user_id is null do update set
  name=excluded.name, category=excluded.category, focus=excluded.focus,
  duration_min=excluded.duration_min, work_met=excluded.work_met,
  recovery_met=excluded.recovery_met, duty_pct=excluded.duty_pct,
  epoc_factor=excluded.epoc_factor, notes=excluded.notes, archived=false;

insert into public.exercise_movements
  (exercise_id, name, order_index, target_sets, rep_low, rep_high)
select e.id, v.name, v.ord, v.sets, v.lo, v.hi
  from (values
    ('KUA','Barbell bench press',        0, 3, 4, 6),
    ('KUA','Incline dumbbell press',     1, 3, 6, 8),
    ('KUA','Overhead press',             2, 3, 5, 8),
    ('KUA','Dips or close-grip press',   3, 2, 6,10),
    ('KLA','Back squat',                 0, 3, 4, 6),
    ('KLA','Leg press',                  1, 3, 8,10),
    ('KLA','Walking lunge',              2, 2,10,12),
    ('KLA','Standing calf raise',        3, 3,10,12),
    ('KUB','Barbell row',                0, 3, 5, 8),
    ('KUB','Pull-up or lat pulldown',    1, 3, 6,10),
    ('KUB','Chest-supported row',        2, 3, 8,10),
    ('KUB','Face pull',                  3, 3,12,15),
    ('KUB','Barbell or dumbbell curl',   4, 3, 8,10),
    ('KLB','Romanian deadlift',          0, 3, 4, 6),
    ('KLB','Bulgarian split squat',      1, 3, 8,10),
    ('KLB','Leg curl',                   2, 3,10,12),
    ('KLB','Hanging leg raise',          3, 3,10,15)
  ) as v(code, name, ord, sets, lo, hi)
  join public.exercises e on e.code = v.code and e.user_id is null
 where not exists (
   select 1 from public.exercise_movements m
    where m.exercise_id = e.id and m.name = v.name);

-- ==================================================== supplements for a keto cut
insert into public.supplements (user_id, code, kind, name, dose, timing, why, notes, sort_order)
values
  (null, 'ELECTRO', 'habit', 'Sodium, potassium, magnesium',
   '4-5 g sodium (10-12 g salt), 3-4 g potassium, 400 mg magnesium - every day',
   'Sodium split across the day with a deliberate 1-2 g in water before the 15:00 session. Magnesium at night.',
   'This is the single most common reason a ketogenic diet fails in week one, and it is not willpower. Dropping under about 50 g of carbohydrate collapses insulin, and low insulin tells the kidney to dump sodium - most people lose 2000-4000 mg of it inside the first week, taking water with it. What that feels like is crushing fatigue, headache, cramp, a pounding heart on the stairs, and it gets called "keto flu" and blamed on the diet. It is a salt deficiency with a nickname. He is also walking 6.7 km a day in Greece, sweating out more of it.',
   array[
     'Salt food far past what feels correct. The advice to go easy on salt is written for people eating processed carbohydrate, and he is about to eat none.',
     'Potassium comes from the food, not a pill: chorta, spinach, avocado and salmon are in this rotation partly for that reason. Potassium supplements are capped at trivial doses in the EU anyway.',
     'Magnesium citrate or glycinate at night - it helps the sleep and it answers the constipation that a fibre-light fortnight can cause. Oxide is cheap and poorly absorbed.',
     'If a session ever feels inexplicably flat, the first thing to check is salt, not calories.'], 4),

  (null, 'CREAT-K', 'supplement', 'Creatine monohydrate',
   '5 g every day',
   'With the first meal at 16:00, or in the pre-session water. Consistency beats timing.',
   'The best-evidenced supplement for holding strength and muscle in a deficit, which is the entire brief. It matters more than usual here: he trains at the end of a fifteen-hour fast, and a saturated muscle is doing that on a full phosphocreatine tank rather than an empty one.',
   array[
     'Monohydrate. Not HCl, not buffered, not a blend.',
     'No loading phase - 5 g/day saturates in about three weeks.',
     'It pulls 1-2 kg of water INTO muscle over the first weeks. Combined with the 2-3 kg of water he LOSES to carbohydrate restriction in the same fortnight, the scale in month one is telling him almost nothing about fat. The tape and the trend line are the honest read.'], 5),

  (null, 'VITD-K', 'supplement', 'Vitamin D3',
   '1000-2000 IU every day',
   'With the fattiest meal - which on this plan is any of them.',
   'Athens is at 38 degrees north. From October there is no meaningful cutaneous vitamin D synthesis at this latitude, and a long deficit is already taxing recovery.',
   array['D3, not D2.',
         'Fat-soluble, so it needs food with fat. That is not a constraint on a ketogenic plan.'], 6),

  (null, 'KETOTEST', 'habit', 'Blood ketones, twice a week',
   'One reading, twice a week',
   'Morning, fasted, BEFORE the session - not after it.',
   'He asked to measure, so this is how to measure without being misled by it. 0.5-3.0 mmol/L is nutritional ketosis and anywhere in that band is the same answer: it is working. Higher is not better and often means protein came in low.',
   array[
     'Blood, not urine. Urine strips read the ketones being WASTED, so they fade to nothing after 2-4 weeks precisely as fat-adaptation improves.',
     'Never test straight after lifting. Gluconeogenesis and lactate clearance both push BHB down, so the session that went best will produce the lowest number of the week.',
     'A reading that drops while the waist keeps shrinking is not a problem. The tape outranks the meter.'], 7)
on conflict (code) where user_id is null do update set
  kind=excluded.kind, name=excluded.name, dose=excluded.dose, timing=excluded.timing,
  why=excluded.why, notes=excluded.notes, sort_order=excluded.sort_order, active=true;

-- ==================================================== a day becomes a travel day
-- Travel is once a week and never on a predictable weekday, so it cannot live
-- in the template. It is applied to whichever day it lands on.
create or replace function public.set_travel_day(p_date date, p_travel boolean default true)
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
  v_pd   bigint; v_codes text[]; v_dow int; v_variant smallint; v_tpl bigint;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  select id into v_pd from public.program_days
   where user_id = v_user and day_date = p_date;
  if v_pd is null then raise exception 'no program day on %', p_date; end if;

  if p_travel then
    v_codes := array['K-T1','K-T2','K-T3'];
  else
    -- put the templated menu back
    select t.id into v_tpl from public.program_templates t
     where t.user_id = v_user and t.active order by t.id desc limit 1;
    v_dow := extract(isodow from p_date);
    v_variant := (to_char(p_date, 'IW')::int % 2)::smallint;
    select meal_codes into v_codes from public.program_template_days
     where template_id = v_tpl and dow = v_dow
     order by (variant = v_variant) desc, variant limit 1;
  end if;

  delete from public.program_day_meals where program_day_id = v_pd;
  insert into public.program_day_meals (user_id, program_day_id, meal_id, slot_index)
  select v_user, v_pd, m.id, c.ord
    from unnest(v_codes) with ordinality as c(code, ord)
    join public.meals m on m.code = c.code and m.user_id is null;

  update public.program_days
     set day_type = case when p_travel then 'travel' else 'regular' end
   where id = v_pd;

  perform public.plan_targets_user(v_user, p_date);
  return 1;
end $$;
grant execute on function public.set_travel_day(date, boolean) to authenticated;

-- ==================================================== scoring, keto-aware
-- Identical to migration 20260902230000 except that a keto profile is scored
-- against its carbohydrate cap instead of against its fat floor.
--
-- Why swap those two specifically: on a balanced plan fat can genuinely run low
-- and is worth a term. In keto mode fat is the REMAINDER by construction - it
-- is mathematically incapable of being the binding constraint - so scoring it
-- is scoring a box that ticks itself. Net carbohydrate is the term that
-- actually moves on a bad day, and unlike the ketone meter it rewards the
-- behaviour rather than the biomarker.
create or replace function public.score_day_inner(p_date date)
returns numeric language plpgsql security invoker set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
  v_pd   public.program_days%rowtype;
  v_log  public.day_logs%rowtype;
  v_prof public.profiles%rowtype;
  v_bw numeric; v_h numeric; v_age numeric; v_sex text;
  v_prot numeric := 0; v_carb numeric := 0; v_fat numeric := 0; v_kcal numeric := 0;
  v_fib numeric := 0; v_veg numeric := 0; v_net numeric := 0; v_cap numeric;
  v_vol numeric := 0; v_prev_vol numeric;
  v_cat text; v_kover integer; v_dur integer;
  v_wmet numeric; v_rmet numeric; v_duty numeric; v_epoc numeric;
  v_trained boolean; v_min numeric;
  v_bmr numeric; v_stride numeric; v_km numeric;
  v_neatf numeric; v_neat_kcal numeric; v_tef_kcal numeric;
  v_steps_kcal numeric; v_lift_kcal numeric; v_cardio_kcal numeric;
  v_cardio_min numeric; v_cardio_km numeric; v_train_kcal numeric; v_extra_burn numeric;
  s_prot numeric; s_kcal numeric; s_fat numeric; s_fib numeric; s_carb numeric;
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

  select v_prot + coalesce(sum(protein_g),0), v_carb + coalesce(sum(carbs_g),0),
         v_fat  + coalesce(sum(fat_g),0),     v_kcal + coalesce(sum(kcal),0),
         v_fib  + coalesce(sum(fiber_g),0)
    into v_prot, v_carb, v_fat, v_kcal, v_fib
    from public.extra_items where user_id = v_user and kind='food' and day_log_id = v_dlid;

  v_net := greatest(0, v_carb - v_fib);

  s_prot := least(100, 100 * power(least(v_prot / nullif(v_pd.protein_target_g,0), 1.0), 1.5));
  s_kcal := greatest(0, 100 - greatest(0,
              (abs(v_kcal - v_pd.kcal_target) / nullif(v_pd.kcal_target,0)) - 0.10) / 0.30 * 100);
  s_fat  := least(100, 100 * v_fat / nullif(0.6 * v_bw, 0));
  s_fib  := least(100, 100 * v_fib / nullif(coalesce(v_prof.fiber_target_g,35), 0));

  if v_prof.diet_mode = 'keto' then
    -- Full marks at or under the cap, nothing at double it. Linear between, so
    -- one slice of bread costs something and a plate of chips costs a lot.
    v_cap  := coalesce(v_prof.carb_cap_g, 28);
    s_carb := case when v_net <= v_cap then 100
                   else greatest(0, 100 * (2 - v_net / v_cap)) end;
    s_nut  := coalesce(0.45*s_prot + 0.20*s_kcal + 0.20*s_carb + 0.15*s_fib, 0);
  else
    s_nut  := coalesce(0.55*s_prot + 0.25*s_kcal + 0.10*s_fat + 0.10*s_fib, 0);
  end if;

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

  -- ---------------- energy out (unchanged; raw model, no tdee_adjustment here)
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
                        'fibre',round(s_fib,1),'carb',round(coalesce(s_carb,0),1),
                        'sleep',round(s_sleep,1),'water',round(s_water,1),'readiness',round(s_ready,1),
                        'overload',round(coalesce(s_overload,0),1),'carbs_g',round(v_carb,1),
                        'net_carbs_g',round(v_net,1),'carb_cap_g',v_cap,
                        'ketones_mmol',v_log.ketones_mmol,
                        'fiber_g',round(v_fib,1),'veg_g',round(v_veg,0),
                        'bodyweight_kg',v_bw,'km_walked',round(v_km,2),
                        'coffee_cups',coalesce(v_log.coffee_cups,0),
                        'lift_min',round(coalesce(v_min,0),1),
                        'lift_kcal',round(coalesce(v_lift_kcal,0)),
                        'cardio_min',round(coalesce(v_cardio_min,0),1),
                        'cardio_km',round(coalesce(v_cardio_km,0),2),
                        'cardio_kcal',round(coalesce(v_cardio_kcal,0)),
                        'neat_kcal',round(v_neat_kcal),'tef_kcal',round(v_tef_kcal),
                        'menu_kcal',v_pd.menu_kcal,'tdee_est_kcal',v_pd.tdee_est_kcal,
                        'tdee_adjustment',coalesce(v_prof.tdee_adjustment,1.000)),
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
