-- DREAMFITNESS :: program generation + daily scoring engine

-- ============================================================ generate_program
-- Builds the 90-day plan for the calling user from the corrected rules:
--   fasting = Wed/Fri (real Athens weekday), heavy resistance never on a fasting day.
create or replace function public.generate_program(p_start date default '2026-09-02')
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_user  uuid := (select auth.uid());
  v_day   integer; v_date date; v_dow integer; v_fast boolean;
  v_reg   integer := 0; v_pd bigint; v_codes text[]; v_ex text;
  v_p numeric; v_c numeric; v_f numeric; v_k integer; v_n integer := 0;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  delete from public.program_days where user_id = v_user;

  for v_day in 1..90 loop
    v_date := p_start + (v_day - 1);
    v_dow  := extract(isodow from v_date);      -- 1=Mon .. 7=Sun
    v_fast := v_dow in (3, 5);                  -- Wednesday, Friday

    -- optimized split: the two fasting days carry cardio + rest, never a heavy lift
    v_ex := case v_dow when 3 then 'C1' when 4 then 'E1' when 5 then 'R1'
                       when 6 then 'E3' when 7 then 'E2'
                       when 1 then 'E4' when 2 then 'E5' end;

    if v_fast then
      v_codes := case when v_dow = 3
                   then array['BF1v2','LF1v2','SF1v2','DF1v2','SF2']
                   else array['BF1v2','LF1v2','SF1v2','DF2v2','SF2'] end;
    else
      v_reg := v_reg + 1;
      v_codes := case when v_reg % 2 = 1
                   then array['B1','L1','S1','D1','S2']
                   else array['B2','L2','S1','D2','S2'] end;
    end if;

    -- unnest (not `= any`) so a repeated meal code is counted once per slot
    select sum(m.protein_g), sum(m.carbs_g), sum(m.fat_g), sum(m.kcal)
      into v_p, v_c, v_f, v_k
      from unnest(v_codes) as c(code)
      join public.meals m on m.code = c.code and m.user_id is null;

    insert into public.program_days
      (user_id, day_no, day_date, day_type, exercise_id,
       protein_target_g, carbs_target_g, fat_target_g, kcal_target)
    values
      (v_user, v_day, v_date, case when v_fast then 'fasting' else 'regular' end,
       (select id from public.exercises where code = v_ex and user_id is null),
       v_p, v_c, v_f, v_k)
    returning id into v_pd;

    insert into public.program_day_meals (user_id, program_day_id, meal_id, slot_index)
    select v_user, v_pd, m.id, c.ord
      from unnest(v_codes) with ordinality as c(code, ord)
      join public.meals m on m.code = c.code and m.user_id is null;

    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ============================================================ score_day
-- Weighted composite: nutrition 35 / training 30 / movement 15 / recovery 20.
-- Unlogged components score 0 by design -- "log it or it didn't happen".
create or replace function public.score_day(p_date date)
returns numeric language plpgsql security invoker set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
  v_pd public.program_days%rowtype;
  v_log public.day_logs%rowtype;
  v_bw numeric;
  v_prot numeric := 0; v_carb numeric := 0; v_fat numeric := 0; v_kcal numeric := 0;
  v_vol numeric := 0; v_prev_vol numeric;
  v_is_rest boolean; v_is_cardio boolean; v_trained boolean;
  s_prot numeric; s_kcal numeric; s_fat numeric;
  s_nut numeric; s_tr numeric; s_mv numeric; s_rec numeric; s_tot numeric;
  s_sleep numeric; s_water numeric; s_ready numeric; s_overload numeric;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select * into v_pd  from public.program_days where user_id = v_user and day_date = p_date;
  if not found then return null; end if;
  select * into v_log from public.day_logs     where user_id = v_user and log_date = p_date;

  -- bodyweight: most recent logged, else profile baseline
  select coalesce(
    (select d.weight_kg from public.day_logs d
      where d.user_id = v_user and d.weight_kg is not null and d.log_date <= p_date
      order by d.log_date desc limit 1),
    (select p.start_weight_kg from public.profiles p where p.id = v_user)
  ) into v_bw;

  -- ---------------- actual intake: completed planned meals (x portion) + extra food
  select coalesce(sum(m.protein_g * ml.portion), 0), coalesce(sum(m.carbs_g * ml.portion), 0),
         coalesce(sum(m.fat_g * ml.portion), 0),     coalesce(sum(m.kcal    * ml.portion), 0)
    into v_prot, v_carb, v_fat, v_kcal
    from public.meal_logs ml
    join public.meals m on m.id = ml.meal_id
   where ml.user_id = v_user and ml.completed
     and ml.day_log_id = (select id from public.day_logs
                           where user_id = v_user and log_date = p_date);

  select v_prot + coalesce(sum(protein_g),0), v_carb + coalesce(sum(carbs_g),0),
         v_fat  + coalesce(sum(fat_g),0),     v_kcal + coalesce(sum(kcal),0)
    into v_prot, v_carb, v_fat, v_kcal
    from public.extra_items
   where user_id = v_user and kind = 'food'
     and day_log_id = (select id from public.day_logs
                        where user_id = v_user and log_date = p_date);

  -- ---------------- nutrition (protein 60 / kcal 30 / fat floor 10)
  -- protein: no reward above target, convex penalty below it
  s_prot := least(100, 100 * power(least(v_prot / nullif(v_pd.protein_target_g,0), 1.0), 1.5));
  -- kcal: scored as a BAND. +/-10% is full marks; undereating is not a win on a recomp.
  s_kcal := greatest(0, 100 - greatest(0,
              (abs(v_kcal - v_pd.kcal_target) / nullif(v_pd.kcal_target,0)) - 0.10) / 0.30 * 100);
  -- fat floor for hormonal health: 0.6 g/kg bodyweight
  s_fat  := least(100, 100 * v_fat / nullif(0.6 * v_bw, 0));
  s_nut  := coalesce(0.60*s_prot + 0.30*s_kcal + 0.10*s_fat, 0);

  -- ---------------- training (attendance 70 / progressive overload 30)
  select e.category = 'rest', e.category = 'cardio'
    into v_is_rest, v_is_cardio
    from public.exercises e where e.id = v_pd.exercise_id;

  select coalesce(sum(sl.volume_load), 0) into v_vol
    from public.set_logs sl
   where sl.user_id = v_user
     and sl.day_log_id = (select id from public.day_logs
                           where user_id = v_user and log_date = p_date);

  v_trained := v_vol > 0 or exists (
    select 1 from public.extra_items
     where user_id = v_user and kind = 'exercise'
       and day_log_id = (select id from public.day_logs
                          where user_id = v_user and log_date = p_date));

  if coalesce(v_is_rest, false) then
    s_tr := 100;                                    -- resting as prescribed IS compliance
  elsif coalesce(v_is_cardio, false) then
    s_tr := case when v_trained then 100 else 0 end;
  else
    -- overload: today's volume load vs the mean of your last 3 sessions of this same type
    select avg(t.v) into v_prev_vol from (
      select sum(sl.volume_load) as v
        from public.set_logs sl
        join public.day_logs dl on dl.id = sl.day_log_id
       where sl.user_id = v_user and sl.exercise_id = v_pd.exercise_id and dl.log_date < p_date
       group by dl.log_date order by dl.log_date desc limit 3) t;
    s_overload := case
      when v_prev_vol is null or v_prev_vol = 0 then 100      -- no history yet: no penalty
      else least(100, 100 * v_vol / v_prev_vol) end;
    s_tr := case when v_vol > 0 then 70 + 0.30 * s_overload
                 when v_trained then 60                        -- logged, but no set data
                 else 0 end;
  end if;

  -- ---------------- movement (capped at target; extra steps don't buy extra score)
  s_mv := least(100, 100 * coalesce(v_log.steps, 0) / nullif(v_pd.steps_target, 0));

  -- ---------------- recovery (sleep 50 / water 30 / readiness 20)
  s_sleep := case when v_log.sleep_hours is null then 0
                  when v_log.sleep_hours between 7 and 9 then 100
                  when v_log.sleep_hours < 7 then greatest(0, 100 - (7 - v_log.sleep_hours) * 25)
                  else greatest(0, 100 - (v_log.sleep_hours - 9) * 15) end;
  s_water := least(100, 100 * coalesce(v_log.water_l, 0) / nullif(v_pd.water_target_l, 0));
  s_ready := case when v_log.energy is null and v_log.soreness is null then 0
                  else (coalesce(v_log.energy, 3) * 20 * 0.6)
                     + ((6 - coalesce(v_log.soreness, 3)) * 20 * 0.4) end;
  s_rec := 0.50*s_sleep + 0.30*s_water + 0.20*s_ready;

  s_tot := 0.35*s_nut + 0.30*s_tr + 0.15*s_mv + 0.20*s_rec;

  insert into public.daily_scores
    (user_id, score_date, nutrition_score, training_score, movement_score,
     recovery_score, total_score, protein_actual_g, kcal_actual, volume_load, detail, computed_at)
  values
    (v_user, p_date, round(s_nut,2), round(s_tr,2), round(s_mv,2),
     round(s_rec,2), round(s_tot,2), round(v_prot,2), round(v_kcal)::int, round(v_vol,2),
     jsonb_build_object('protein',round(s_prot,1), 'kcal',round(s_kcal,1), 'fat',round(s_fat,1),
                        'sleep',round(s_sleep,1), 'water',round(s_water,1), 'readiness',round(s_ready,1),
                        'overload',round(coalesce(s_overload,0),1),
                        'carbs_g',round(v_carb,1), 'bodyweight_kg',v_bw),
     now())
  on conflict (user_id, score_date) do update set
     nutrition_score = excluded.nutrition_score, training_score = excluded.training_score,
     movement_score  = excluded.movement_score,  recovery_score = excluded.recovery_score,
     total_score     = excluded.total_score,     protein_actual_g = excluded.protein_actual_g,
     kcal_actual     = excluded.kcal_actual,     volume_load    = excluded.volume_load,
     detail          = excluded.detail,          computed_at    = now();

  return round(s_tot, 2);
end $$;

-- ============================================================ auto-recompute
create or replace function private.rescore()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_date date;
begin
  if tg_table_name = 'day_logs' then
    v_date := coalesce(new.log_date, old.log_date);
  else
    select log_date into v_date from public.day_logs
     where id = coalesce(new.day_log_id, old.day_log_id);
  end if;
  if v_date is not null then perform public.score_day(v_date); end if;
  return coalesce(new, old);
end $$;

create trigger day_logs_rescore    after insert or update or delete on public.day_logs
  for each row execute function private.rescore();
create trigger meal_logs_rescore   after insert or update or delete on public.meal_logs
  for each row execute function private.rescore();
create trigger set_logs_rescore    after insert or update or delete on public.set_logs
  for each row execute function private.rescore();
create trigger extra_items_rescore after insert or update or delete on public.extra_items
  for each row execute function private.rescore();
