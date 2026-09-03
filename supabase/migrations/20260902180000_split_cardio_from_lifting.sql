-- A treadmill block and a lifting block are not the same exercise wearing the
-- same units. The treadmill never stops - it runs at 100% duty. Lifting at 45s
-- on / 2min off runs at 27%. Averaging them into one "mixed" intensity meant a
-- session's estimate moved with the RATIO you happened to do that day, which is
-- exactly the thing an estimate should not do.
--
-- From here: `training_minutes` covers the LIFTING portion. Timed movements
-- (treadmill, plank, farmer holds) are logged as sets and costed separately at
-- their own intensity, continuously.

alter table public.exercise_movements
  add column if not exists met numeric(4,2) check (met between 1 and 20);

comment on column public.exercise_movements.met is
  'Intensity for time-tracked movements, costed continuously (no rest gaps). '
  'Ignored for load and bodyweight movements, which are covered by the session.';

update public.exercise_movements mv set met = v.met
  from (values ('Treadmill - Zone 2', 6.5), ('Plank', 3.0), ('Farmer Hold', 4.5))
       as v(name, met)
 where mv.name = v.name and mv.tracking = 'time';

-- Wednesday and Friday no longer need a fudged duty: their treadmill is now
-- costed on its own, so the session number describes the lifting alone.
update public.exercises set
  duty_pct = null, work_met = 6.0, recovery_met = 2.3, duration_min = 40
 where user_id is null and code = 'DELT';
update public.exercises set
  duty_pct = null, work_met = 6.2, recovery_met = 2.3, duration_min = 30
 where user_id is null and code = 'FORE';

-- ============================================================ score_day_inner v4
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
  v_steps_kcal numeric; v_lift_kcal numeric; v_cardio_kcal numeric;
  v_cardio_min numeric; v_train_kcal numeric; v_extra_burn numeric;
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

  -- ---------------- nutrition (protein 60 / kcal 30 / fat floor 10)
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

  -- timed movements run continuously (duty 1.0) at their own intensity, and
  -- carry no meaningful afterburn the way resistance work does
  select coalesce(sum(sl.duration_sec) / 60.0, 0),
         coalesce(sum(public.session_kcal(
           sl.duration_sec / 60.0, v_bw, coalesce(mv.met, 6.0), coalesce(mv.met, 6.0),
           1.0, v_prof.set_seconds, v_prof.rest_seconds, 1.0)), 0)
    into v_cardio_min, v_cardio_kcal
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
    s_tr := 100;                                  -- resting as prescribed IS compliance
  elsif v_cat in ('cardio','mixed') then
    -- treadmill + abs + delts is doing its job by happening, not by tonnage
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
  v_stride := (case when v_sex='female' then 0.413 else 0.415 end) * v_h / 100.0;
  v_km     := coalesce(v_log.steps,0) * v_stride / 1000.0;
  -- NET walking cost, so the resting energy already inside BMR isn't counted twice
  v_steps_kcal := 0.5 * v_bw * v_km;

  -- Lifting minutes only. Falling back to the planned duration requires actual
  -- evidence of lifting: a treadmill-only day must not be charged for a session
  -- of squats that never happened.
  v_min := coalesce(v_log.training_minutes, case when v_vol > 0 then v_dur else 0 end);
  v_lift_kcal := case
    when coalesce(v_min,0) <= 0 then 0
    when v_kover is not null and coalesce(v_dur,0) > 0 then v_kover * (v_min / v_dur)
    when v_kover is not null then v_kover
    else public.session_kcal(v_min, v_bw, v_wmet, v_rmet, v_duty,
                             v_prof.set_seconds, v_prof.rest_seconds, v_epoc)
  end;
  v_train_kcal := v_lift_kcal + coalesce(v_cardio_kcal,0) + coalesce(v_extra_burn,0);

  -- ---------------- movement + recovery
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
     bmr_kcal, steps_kcal, training_kcal, burn_kcal, energy_balance, detail, computed_at)
  values
    (v_user, p_date, round(s_nut,2), round(s_tr,2), round(s_mv,2), round(s_rec,2),
     round(s_tot,2), round(v_prot,2), round(v_kcal)::int, round(v_vol,2),
     round(v_bmr)::int, round(v_steps_kcal)::int, round(v_train_kcal)::int,
     round(v_bmr + v_steps_kcal + v_train_kcal)::int,
     round(v_kcal - (v_bmr + v_steps_kcal + v_train_kcal))::int,
     jsonb_build_object('protein',round(s_prot,1),'kcal',round(s_kcal,1),'fat',round(s_fat,1),
                        'sleep',round(s_sleep,1),'water',round(s_water,1),'readiness',round(s_ready,1),
                        'overload',round(coalesce(s_overload,0),1),'carbs_g',round(v_carb,1),
                        'bodyweight_kg',v_bw,'km_walked',round(v_km,2),
                        'coffee_cups',coalesce(v_log.coffee_cups,0),
                        'lift_min',round(coalesce(v_min,0),1),
                        'lift_kcal',round(coalesce(v_lift_kcal,0)),
                        'cardio_min',round(coalesce(v_cardio_min,0),1),
                        'cardio_kcal',round(coalesce(v_cardio_kcal,0))),
     now())
  on conflict (user_id, score_date) do update set
     nutrition_score=excluded.nutrition_score, training_score=excluded.training_score,
     movement_score=excluded.movement_score,   recovery_score=excluded.recovery_score,
     total_score=excluded.total_score,         protein_actual_g=excluded.protein_actual_g,
     kcal_actual=excluded.kcal_actual,         volume_load=excluded.volume_load,
     bmr_kcal=excluded.bmr_kcal,               steps_kcal=excluded.steps_kcal,
     training_kcal=excluded.training_kcal,     burn_kcal=excluded.burn_kcal,
     energy_balance=excluded.energy_balance,   detail=excluded.detail, computed_at=now();

  return round(s_tot,2);
end $$;
