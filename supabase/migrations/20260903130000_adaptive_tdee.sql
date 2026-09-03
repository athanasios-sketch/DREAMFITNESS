-- The model is a hypothesis. The scale is the experiment.
--
-- Everything upstream of here predicts expenditure: Mifflin for resting, a NEAT
-- multiplier, ACSM for the walking, METs for the session. It is a careful model
-- and it is still a model - it cannot see thyroid downregulation, it cannot see
-- that the 9000 steps are actually 7000 on a desk day, and it cannot see the
-- 300 kcal that never got logged. Published error on this class of prediction
-- is routinely +/-10-15% for an individual, which at 3000 kcal is +/-400: the
-- entire deficit.
--
-- For Thanos that is a tolerable inaccuracy. For Ntinos it is THE problem. His
-- record shows 103.6 kg in December and 102.5 kg in July - seven months, muscle
-- flat, weight flat - and the last ten weeks of it going the wrong way. He has
-- not failed to follow a plan. He has followed plans built on a predicted
-- number that was wrong for him and never got corrected.
--
-- So: measure it. Over a trailing window, what he actually ate and what the
-- scale actually did are enough to solve for expenditure directly.
--
--     intake - TDEE = balance,  balance * days = Δkg * 7700
--  => TDEE = mean_intake - (Δkg / days) * 7700
--
-- and the correction is that number over the model's. Three things keep this
-- honest rather than merely clever:
--
--   * A REGRESSION, not two endpoints. Day-to-day bodyweight is mostly water;
--     a slope through 28 days of it is signal, a difference between two
--     Tuesdays is noise.
--   * A WARM-UP EXCLUSION. Carbohydrate restriction dumps 2-3 kg of water in
--     the first fortnight. Measuring TDEE across that reads as a 1500 kcal/day
--     deficit and would cut his food to nothing.
--   * DAMPING AND CLAMPS. At most 5% of correction per run, never more than 15%
--     from the model in total. A bad fortnight of logging should nudge the
--     plan, not detonate it.

-- ============================================================ the audit trail
-- Stored rather than computed-and-forgotten, because when the budget moves the
-- first question is always "on what evidence".
create table if not exists public.tdee_reconciliations (
  id              bigint generated always as identity primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  computed_for    date not null,
  window_from     date not null,
  window_to       date not null,
  weights_n       integer not null,
  intake_days_n   integer not null,
  trend_kg_week   numeric(5,3),
  mean_intake     numeric(7,1),
  observed_tdee   numeric(7,1),
  model_tdee      numeric(7,1),
  raw_ratio       numeric(5,3),
  prev_adjustment numeric(4,3),
  new_adjustment  numeric(4,3),
  status          text not null
                    check (status in ('applied','insufficient_data','warming_up','clamped')),
  detail          jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  unique (user_id, computed_for)
);
create index if not exists tdee_reconciliations_user_idx
  on public.tdee_reconciliations (user_id, computed_for desc);

alter table public.profiles
  add column if not exists tdee_adjusted_at date;
comment on column public.profiles.tdee_adjustment is
  'Measured correction on predicted expenditure, from reconcile_tdee(). 1.000
   means the model is unchallenged - either it is right or there is not yet
   enough data to say. Applied in plan_targets_user when deriving the budget,
   and deliberately NOT applied to daily_scores.burn_kcal, which stays the raw
   prediction so the two can be compared without the comparison feeding itself.';

alter table public.tdee_reconciliations enable row level security;
create policy tdee_reconciliations_own on public.tdee_reconciliations for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ============================================================ the measurement
create or replace function public.reconcile_tdee_user(
  p_user uuid,
  p_asof date    default null,
  p_window integer default 28
) returns numeric language plpgsql security invoker set search_path = '' as $$
declare
  v_prof   public.profiles%rowtype;
  v_asof   date; v_from date; v_warm date;
  v_wn integer; v_in integer;
  v_slope numeric; v_trend_wk numeric;
  v_intake numeric; v_model numeric;
  v_obs numeric; v_ratio numeric;
  v_prev numeric; v_new numeric;
  v_status text := 'applied';
begin
  if p_user is null then raise exception 'no user'; end if;
  select * into v_prof from public.profiles where id = p_user;
  if not found then raise exception 'no profile for %', p_user; end if;

  v_asof := coalesce(p_asof, current_date);
  v_from := v_asof - (greatest(p_window, 14) - 1);
  v_prev := coalesce(v_prof.tdee_adjustment, 1.000);

  -- Nothing before the fortnight mark counts. The water shift at the start of a
  -- carbohydrate restriction is not fat and must not be priced as if it were.
  v_warm := v_prof.program_start_date + 14;
  if v_from < v_warm then v_from := v_warm; end if;

  if v_asof - v_from < 13 then
    insert into public.tdee_reconciliations
      (user_id, computed_for, window_from, window_to, weights_n, intake_days_n,
       prev_adjustment, new_adjustment, status, detail)
    values (p_user, v_asof, v_from, v_asof, 0, 0, v_prev, v_prev, 'warming_up',
            jsonb_build_object('reason',
              'fewer than 14 usable days since program start + 14',
              'earliest_usable', v_warm))
    on conflict (user_id, computed_for) do update set
      window_from=excluded.window_from, status=excluded.status, detail=excluded.detail;
    return v_prev;
  end if;

  -- Slope of bodyweight against day number, in kg/day. regr_slope ignores rows
  -- where either side is null, which is exactly the wanted behaviour on a
  -- weigh-when-you-remember record.
  select count(*), regr_slope(weight_kg, (log_date - v_from))
    into v_wn, v_slope
    from public.day_logs
   where user_id = p_user and weight_kg is not null
     and log_date between v_from and v_asof;

  -- Intake only counts on days something was actually logged. A blank day is
  -- not a zero-calorie day, and averaging it in as one would invent a deficit.
  select count(*), avg(kcal_actual)
    into v_in, v_intake
    from public.daily_scores
   where user_id = p_user and kcal_actual is not null and kcal_actual > 0
     and score_date between v_from and v_asof;

  select avg(burn_kcal) into v_model
    from public.daily_scores
   where user_id = p_user and burn_kcal is not null
     and kcal_actual is not null and kcal_actual > 0
     and score_date between v_from and v_asof;

  -- Thresholds chosen so the correction needs a real record behind it: eight
  -- weigh-ins is roughly twice a week, eighteen logged days is two thirds of a
  -- four-week window.
  if v_wn < 8 or v_in < 18 or v_slope is null or v_intake is null or v_model is null
     or v_model <= 0 then
    insert into public.tdee_reconciliations
      (user_id, computed_for, window_from, window_to, weights_n, intake_days_n,
       trend_kg_week, mean_intake, model_tdee, prev_adjustment, new_adjustment,
       status, detail)
    values (p_user, v_asof, v_from, v_asof, coalesce(v_wn,0), coalesce(v_in,0),
            round(coalesce(v_slope,0)*7, 3), round(v_intake,1), round(v_model,1),
            v_prev, v_prev, 'insufficient_data',
            jsonb_build_object('need_weights', 8, 'need_intake_days', 18))
    on conflict (user_id, computed_for) do update set
      weights_n=excluded.weights_n, intake_days_n=excluded.intake_days_n,
      trend_kg_week=excluded.trend_kg_week, mean_intake=excluded.mean_intake,
      model_tdee=excluded.model_tdee, status=excluded.status, detail=excluded.detail;
    return v_prev;
  end if;

  v_trend_wk := v_slope * 7;
  -- 7700 kcal/kg: the standard energy density of mixed tissue loss. It is an
  -- approximation - early loss is wetter and therefore cheaper - which is the
  -- other reason the first fortnight is excluded.
  v_obs   := v_intake - (v_slope * 7700);
  v_ratio := v_obs / v_model;

  -- Damped: move at most 5 percentage points toward the measurement per run, so
  -- one noisy fortnight cannot swing the budget by 400 kcal.
  v_new := v_prev + greatest(-0.05, least(0.05, v_ratio - v_prev));
  -- And bounded: past 15% away from the model, the likelier explanation is
  -- unlogged food or a broken scale, not a remarkable metabolism.
  if v_new < 0.85 then v_new := 0.85; v_status := 'clamped'; end if;
  if v_new > 1.15 then v_new := 1.15; v_status := 'clamped'; end if;

  insert into public.tdee_reconciliations
    (user_id, computed_for, window_from, window_to, weights_n, intake_days_n,
     trend_kg_week, mean_intake, observed_tdee, model_tdee, raw_ratio,
     prev_adjustment, new_adjustment, status, detail)
  values
    (p_user, v_asof, v_from, v_asof, v_wn, v_in,
     round(v_trend_wk,3), round(v_intake,1), round(v_obs,1), round(v_model,1),
     round(v_ratio,3), v_prev, round(v_new,3), v_status,
     jsonb_build_object(
       'kcal_per_kg', 7700,
       'model_says', round(v_model),
       'scale_says', round(v_obs),
       'gap_kcal',   round(v_obs - v_model),
       'damped_from_raw', round(v_ratio - v_new, 3)))
  on conflict (user_id, computed_for) do update set
    window_from=excluded.window_from, weights_n=excluded.weights_n,
    intake_days_n=excluded.intake_days_n, trend_kg_week=excluded.trend_kg_week,
    mean_intake=excluded.mean_intake, observed_tdee=excluded.observed_tdee,
    model_tdee=excluded.model_tdee, raw_ratio=excluded.raw_ratio,
    prev_adjustment=excluded.prev_adjustment, new_adjustment=excluded.new_adjustment,
    status=excluded.status, detail=excluded.detail;

  update public.profiles
     set tdee_adjustment = round(v_new,3), tdee_adjusted_at = v_asof
   where id = p_user;

  -- Forward only. Rewriting the budget of days already lived would rewrite the
  -- evidence this correction was measured from.
  perform public.plan_targets_user(p_user, v_asof);
  return round(v_new,3);
end $$;

create or replace function public.reconcile_tdee(
  p_asof date default null, p_window integer default 28
) returns numeric language plpgsql security invoker set search_path = '' as $$
declare v_user uuid := (select auth.uid());
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  return public.reconcile_tdee_user(v_user, p_asof, p_window);
end $$;

grant execute on function public.reconcile_tdee_user(uuid, date, integer) to authenticated;
grant execute on function public.reconcile_tdee(date, integer) to authenticated;
