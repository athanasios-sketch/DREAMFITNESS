-- DREAMFITNESS v2 :: real training split, a defensible energy model,
-- coffee, weekly measurements, and full off-plan nutrition.
--
-- Nothing about the IDEA changes: you log minutes, an approximate burn comes
-- out. What changes is that the approximation is now derived from how you
-- actually train (45s sets, 2min rest) instead of a hand-waved constant, and
-- every part of it is editable from the app.

-- ============================================================ profiles
alter table public.profiles
  add column if not exists set_seconds      integer  not null default 45
    check (set_seconds between 5 and 600),
  add column if not exists rest_seconds     integer  not null default 120
    check (rest_seconds between 0 and 900),
  -- measurements are a weekly ritual, not a daily one. Program weeks start on
  -- the program's own start weekday (2026-09-02 is a Wednesday), so week
  -- boundaries and measurement days line up.
  add column if not exists measure_weekday  smallint not null default 3
    check (measure_weekday between 1 and 7),
  add column if not exists coffee_limit_cups numeric(3,1) not null default 4
    check (coffee_limit_cups >= 0);

-- ============================================================ coffee
alter table public.day_logs
  add column if not exists coffee_cups numeric(4,1) check (coffee_cups between 0 and 30);

comment on column public.day_logs.coffee_cups is
  'Cups of coffee. Logged, not scored - it carries no calories worth counting, '
  'but caffeine load and sleep quality are worth being able to correlate later.';

-- ============================================================ off-plan food, in full
-- "I will use AI to fill in the details" - so give those details somewhere to go.
alter table public.extra_items
  add column if not exists amount      text,
  add column if not exists fiber_g     numeric(6,2) check (fiber_g   >= 0),
  add column if not exists sugar_g     numeric(6,2) check (sugar_g   >= 0),
  add column if not exists sat_fat_g   numeric(6,2) check (sat_fat_g >= 0),
  add column if not exists sodium_mg   numeric(7,1) check (sodium_mg >= 0),
  add column if not exists duration_sec integer     check (duration_sec >= 0);

-- ============================================================ the energy model
-- A resistance "hour" is not an hour of work. At 45s of effort against 120s of
-- rest you are working 27% of the time; the rest of it your heart rate is
-- coming down, which costs more than sitting still but far less than a set.
-- Modelling that duty cycle is the difference between an honest number and a
-- flattering one.
alter table public.exercises
  add column if not exists work_met     numeric(4,2) check (work_met     between 1 and 20),
  add column if not exists recovery_met numeric(4,2) check (recovery_met between 1 and 10),
  -- null => derive the duty cycle from the profile's set/rest seconds.
  -- 1.0 => continuous effort (a treadmill block never stops).
  add column if not exists duty_pct     numeric(4,3) check (duty_pct between 0 and 1),
  -- resistance work keeps burning after you rack the bar; steady cardio doesn't
  add column if not exists epoc_factor  numeric(4,3) not null default 1.000
    check (epoc_factor between 1 and 1.5),
  -- set this to bypass the model entirely for one session
  add column if not exists kcal_override integer check (kcal_override >= 0),
  add column if not exists archived     boolean not null default false,
  add column if not exists forked_from  bigint references public.exercises(id) on delete set null,
  add column if not exists updated_at   timestamptz not null default now();

create index if not exists exercises_forked_from_idx on public.exercises (forked_from);
-- a user's own sessions are unique by code, so forking twice is a no-op
create unique index if not exists exercises_user_code_key
  on public.exercises (user_id, code) where user_id is not null;

-- Wednesday and Friday are treadmill + abs + a muscle group. Neither
-- "resistance" nor "cardio" describes them, and grading them on tonnage would
-- punish a session that is doing exactly what it was designed to do.
alter table public.exercises drop constraint if exists exercises_category_check;
alter table public.exercises add constraint exercises_category_check
  check (category in ('resistance','cardio','mixed','rest'));

-- ============================================================ movements
-- Not every movement is reps x kilos. A treadmill block is minutes, a plank is
-- seconds, a hanging leg raise is just reps.
alter table public.exercise_movements
  add column if not exists tracking text not null default 'load'
    check (tracking in ('load','bodyweight','time')),
  add column if not exists notes text;

alter table public.set_logs
  add column if not exists duration_sec integer      check (duration_sec >= 0),
  add column if not exists distance_km  numeric(5,2) check (distance_km  >= 0),
  add column if not exists incline_pct  numeric(4,1) check (incline_pct between 0 and 40);

-- The movements table shipped with a read policy and no write policy, so
-- editing a session was impossible by construction. Owners can write their own.
drop policy if exists exercise_movements_write on public.exercise_movements;
create policy exercise_movements_write on public.exercise_movements for all to authenticated
  using (exists (select 1 from public.exercises e
                  where e.id = exercise_id and e.user_id = (select auth.uid())))
  with check (exists (select 1 from public.exercises e
                       where e.id = exercise_id and e.user_id = (select auth.uid())));

drop trigger if exists exercises_touch on public.exercises;
create trigger exercises_touch before update on public.exercises
  for each row execute function private.touch_updated_at();

-- ============================================================ session_kcal
-- The whole energy model, in one place, so the app and the scorer can never
-- disagree about what a session cost.
--
--   duty      = fraction of the session actually under load
--   avg MET   = work_met*duty + recovery_met*(1-duty)
--   net MET   = avg - 1   (resting metabolism is already counted as BMR;
--                          counting it twice is the classic overestimate)
--   kcal      = net MET * 3.5 * kg / 200 * minutes * epoc
--
-- At 45s/120s that duty is 27%, which is why an hour of lifting is nearer
-- 280 kcal than the 600 a watch will happily tell you.
create or replace function public.session_kcal(
  p_minutes      numeric,
  p_weight_kg    numeric,
  p_work_met     numeric,
  p_recovery_met numeric,
  p_duty_pct     numeric,
  p_set_seconds  integer,
  p_rest_seconds integer,
  p_epoc         numeric default 1.0
) returns numeric language sql immutable set search_path = '' as $$
  select greatest(0,
    greatest(coalesce(p_work_met, 6.0) * duty
           + coalesce(p_recovery_met, 2.0) * (1 - duty) - 1.0, 0)
    * 3.5 * coalesce(nullif(p_weight_kg, 0), 80) / 200.0
    * greatest(coalesce(p_minutes, 0), 0)
    * coalesce(p_epoc, 1.0))
  from (select coalesce(
                 p_duty_pct,
                 case when coalesce(p_set_seconds,0) + coalesce(p_rest_seconds,0) > 0
                      then p_set_seconds::numeric / (p_set_seconds + p_rest_seconds)
                      else 1.0 end) as duty) d;
$$;

-- ============================================================ the real split
-- Sun rest / Mon chest-or-back / Tue arms / Wed treadmill+abs+delts (fasting)
-- Thu the other of chest-or-back / Fri treadmill+abs+forearms (fasting) / Sat legs
update public.exercises set archived = true
 where user_id is null and code in ('E1','E2','E3','E4','E5','C1');

insert into public.exercises
  (user_id, code, name, category, focus, est_kcal, duration_min, notes,
   work_met, recovery_met, duty_pct, epoc_factor) values
  (null, 'CHEST', 'Chest', 'resistance',
   'Incline press, flat dumbbell, machine press, cable fly, dips',
   0, 60, 'Heavy first, isolation last. Leave 1-2 reps in reserve on the presses.',
   7.0, 2.5, null, 1.10),
  (null, 'BACK', 'Back', 'resistance',
   'Pull-ups, barbell row, cable row, straight-arm pulldown, face pulls',
   0, 60, 'Pull with the elbows, not the hands. Full stretch at the top.',
   7.2, 2.5, null, 1.10),
  (null, 'ARMS', 'Arms', 'resistance',
   'Biceps and triceps - curls, hammers, close-grip, pushdowns',
   0, 50, 'Short day by design. Volume over load; elbows locked in place.',
   5.5, 2.2, null, 1.06),
  (null, 'DELT', 'Treadmill, Abs & Shoulders', 'mixed',
   'Zone 2 treadmill, then delts and core - fasted',
   0, 55, 'Fasting day. Treadmill first while glycogen is low, lifting after.',
   6.5, 2.4, 0.600, 1.05),
  (null, 'FORE', 'Treadmill, Abs & Forearms', 'mixed',
   'Zone 2 treadmill, then core and forearms - fasted',
   0, 45, 'Fasting day. Grip work is cheap on the CNS, which is the point here.',
   6.2, 2.3, 0.650, 1.05),
  (null, 'LEGS', 'Legs', 'resistance',
   'Squat, RDL, leg press, extensions, curls, calves',
   0, 65, 'The biggest burn of the week and the hardest to recover from.',
   8.0, 2.8, null, 1.12),
  (null, 'REST', 'Full Rest', 'rest',
   'Stretching, mobility, or nothing at all',
   0, 0, 'Sunday. Growth happens here, not in the gym.',
   6.0, 2.5, null, 1.05)
on conflict (code) where user_id is null do update set
  name = excluded.name, category = excluded.category, focus = excluded.focus,
  duration_min = excluded.duration_min, notes = excluded.notes,
  work_met = excluded.work_met, recovery_met = excluded.recovery_met,
  duty_pct = excluded.duty_pct, epoc_factor = excluded.epoc_factor,
  archived = false;

-- give the old rest session the same treatment so a Sunday you *do* train
-- still produces a number instead of a silent zero
update public.exercises
   set work_met = 6.0, recovery_met = 2.5, epoc_factor = 1.05, archived = true
 where user_id is null and code = 'R1';

-- ============================================================ movements
delete from public.exercise_movements
 where exercise_id in (select id from public.exercises
                        where user_id is null
                          and code in ('CHEST','BACK','ARMS','DELT','FORE','LEGS'));

insert into public.exercise_movements
  (exercise_id, name, order_index, target_sets, rep_low, rep_high, tracking)
select e.id, m.name, m.ord, m.sets, m.lo, m.hi, m.tracking
  from (values
    ('CHEST', 'Incline Barbell Press',     0, 4,  6, 10, 'load'),
    ('CHEST', 'Flat Dumbbell Press',       1, 3,  8, 12, 'load'),
    ('CHEST', 'Chest Press Machine',       2, 3, 10, 12, 'load'),
    ('CHEST', 'Cable Fly',                 3, 3, 12, 15, 'load'),
    ('CHEST', 'Dips',                      4, 3,  8, 12, 'bodyweight'),

    ('BACK',  'Pull-ups / Lat Pulldown',   0, 4,  8, 12, 'load'),
    ('BACK',  'Barbell Row',               1, 4,  6, 10, 'load'),
    ('BACK',  'Seated Cable Row',          2, 3, 10, 12, 'load'),
    ('BACK',  'Straight-arm Pulldown',     3, 3, 12, 15, 'load'),
    ('BACK',  'Face Pull',                 4, 3, 15, 20, 'load'),

    ('ARMS',  'Barbell Curl',              0, 4,  8, 12, 'load'),
    ('ARMS',  'Incline Dumbbell Curl',     1, 3, 10, 12, 'load'),
    ('ARMS',  'Hammer Curl',               2, 3, 10, 12, 'load'),
    ('ARMS',  'Close-grip Bench Press',    3, 4,  8, 12, 'load'),
    ('ARMS',  'Rope Pushdown',             4, 3, 12, 15, 'load'),
    ('ARMS',  'Overhead Cable Extension',  5, 3, 12, 15, 'load'),

    ('DELT',  'Treadmill - Zone 2',        0, 1, null, null, 'time'),
    ('DELT',  'Overhead Press',            1, 4,  8, 12, 'load'),
    ('DELT',  'Lateral Raise',             2, 4, 12, 15, 'load'),
    ('DELT',  'Rear Delt Fly',             3, 3, 15, 20, 'load'),
    ('DELT',  'Hanging Leg Raise',         4, 3, 10, 15, 'bodyweight'),
    ('DELT',  'Cable Crunch',              5, 3, 12, 15, 'load'),

    ('FORE',  'Treadmill - Zone 2',        0, 1, null, null, 'time'),
    ('FORE',  'Cable Crunch',              1, 3, 12, 15, 'load'),
    ('FORE',  'Hanging Leg Raise',         2, 3, 10, 15, 'bodyweight'),
    ('FORE',  'Plank',                     3, 3, null, null, 'time'),
    ('FORE',  'Barbell Wrist Curl',        4, 3, 15, 20, 'load'),
    ('FORE',  'Reverse Wrist Curl',        5, 3, 15, 20, 'load'),
    ('FORE',  'Farmer Hold',               6, 3, null, null, 'time'),

    ('LEGS',  'Squat / Hack Squat',        0, 4,  5,  8, 'load'),
    ('LEGS',  'Romanian Deadlift',         1, 4,  6, 10, 'load'),
    ('LEGS',  'Leg Press',                 2, 3, 10, 15, 'load'),
    ('LEGS',  'Leg Extension',             3, 3, 12, 15, 'load'),
    ('LEGS',  'Leg Curl',                  4, 3, 12, 15, 'load'),
    ('LEGS',  'Standing Calf Raise',       5, 4, 12, 20, 'load')
  ) as m(code, name, ord, sets, lo, hi, tracking)
  join public.exercises e on e.code = m.code and e.user_id is null;

-- ============================================================ oat & almond milk
-- Soy was the only milk in the fasting rotation. Oat is creamier and carries
-- oats better; almond is the cheap calorie-free way to loosen anything.
insert into public.meals
  (user_id, code, name, slot, day_type, version, protein_g, carbs_g, fat_g, kcal,
   ingredients, instructions, prep_min, cook_min, equipment, steps, tips) values
  (null, 'OATM', 'Oat Milk (250ml)', 'snack', 'any', 1, 2.0, 16.5, 3.8, 108,
   '250ml oat milk', 'Drink it, or pour it over anything in the plan.', 1, 0, 'No cooking',
   array['Pour 250ml. That is the whole recipe.'],
   array['Barista oat froths and stays smooth in hot coffee; plain oat splits.',
         'Roughly 108 kcal a glass - real calories, so log it rather than assuming it is free.']),
  (null, 'ALMM', 'Almond Milk (250ml)', 'snack', 'any', 1, 1.3, 1.5, 2.8, 38,
   '250ml unsweetened almond milk', 'Drink it, or use it to loosen a thick shake.', 1, 0, 'No cooking',
   array['Pour 250ml. Check the carton says unsweetened.'],
   array['Sweetened almond milk triples the carbs for no benefit. Unsweetened only.',
         'At 38 kcal it is the cheapest way to make a shake drinkable.']),
  (null, 'BF2v2', 'Oat Milk Protein Oats', 'breakfast', 'fasting', 2, 48.5, 50.0, 18.0, 560,
   '50g vegan protein, 45g oats, 250ml oat milk, 15g tahini',
   'Simmer oats in oat milk, protein off the heat, tahini on top.', 5, 6, 'Pot',
   array['Bring 250ml oat milk just to a simmer, stir in 45g oats, cook 4 min.',
         'Off the heat, stir in 50g vegan protein a third at a time.',
         'Top with 15g tahini.'],
   array['Off the heat is not optional - protein powder in boiling liquid seizes into lumps.',
         'Oat milk scorches faster than soy. Keep it moving and keep the heat moderate.']),
  (null, 'SF3', 'Almond Milk Protein Shake', 'snack', 'fasting', 1, 35.0, 34.5, 11.7, 380,
   '40g vegan protein, 300ml unsweetened almond milk, 1 banana, 10g almond butter',
   'Blend everything with ice.', 3, 0, 'Blender or shaker bottle',
   array['Blend 40g vegan protein, 300ml almond milk, a banana and 10g almond butter with ice.',
         'No blender: shake the powder and milk, eat the banana and nut butter alongside.'],
   array['Freeze the banana the night before - it thickens the shake without ice watering it down.',
         'Almond butter is what makes this sit in the stomach on a fasting day.'])
on conflict (code) where user_id is null do update set
  name = excluded.name, slot = excluded.slot, day_type = excluded.day_type,
  protein_g = excluded.protein_g, carbs_g = excluded.carbs_g, fat_g = excluded.fat_g,
  kcal = excluded.kcal, ingredients = excluded.ingredients,
  instructions = excluded.instructions, prep_min = excluded.prep_min,
  cook_min = excluded.cook_min, equipment = excluded.equipment,
  steps = excluded.steps, tips = excluded.tips;

-- oat milk is now an option in the existing fasting breakfast too
update public.meals
   set tips = array['Protein powder hitting boiling liquid seizes into lumps. Always off the heat.',
                    'Tahini on top, not stirred in - it turns bitter with prolonged heat.',
                    'Oat milk swaps in one-for-one and makes it creamier for about 30 kcal more.']
 where code = 'BF1v2' and user_id is null;

-- ============================================================ generate_program v2
create or replace function public.generate_program(p_start date default '2026-09-02')
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_user  uuid := (select auth.uid());
  v_day   integer; v_date date; v_dow integer; v_fast boolean;
  v_pd bigint; v_codes text[]; v_ex text; v_chest_monday boolean;
  v_p numeric; v_c numeric; v_f numeric; v_k integer; v_n integer := 0;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  delete from public.program_days where user_id = v_user;

  for v_day in 1..90 loop
    v_date := p_start + (v_day - 1);
    v_dow  := extract(isodow from v_date);      -- 1=Mon .. 7=Sun
    v_fast := v_dow in (3, 5);                  -- Wednesday, Friday

    -- Chest and back alternate between Monday and Thursday, and which one
    -- leads is decided per ISO week. Hashing the week (rather than random())
    -- means the answer is stable: regenerating the plan never reshuffles a
    -- week you have already trained.
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
      -- Wednesday takes the oat-milk breakfast, Friday the soy one
      v_codes := case when v_dow = 3
                   then array['BF2v2','LF1v2','SF1v2','DF1v2','SF2']
                   else array['BF1v2','LF1v2','SF1v2','DF2v2','SF3'] end;
    else
      -- alternate the fed-day menu by day number so consecutive fed days differ
      v_codes := case when v_day % 2 = 1
                   then array['B1','L1','S1','D1','S2']
                   else array['B2','L2','S1','D2','S2'] end;
    end if;

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

-- ============================================================ editing the plan
-- The seeded sessions are system rows (user_id null) that every account shares,
-- so they cannot be edited in place. Editing one forks it into a private copy
-- and repoints the plan AND the history at the copy, so trailing-average
-- overload comparisons survive the edit instead of resetting to zero.
create or replace function public.fork_exercise(p_exercise_id bigint)
returns bigint language plpgsql security invoker set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
  v_src  public.exercises%rowtype;
  v_new  bigint;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select * into v_src from public.exercises
   where id = p_exercise_id and (user_id is null or user_id = v_user);
  if not found then raise exception 'exercise % not found', p_exercise_id; end if;
  if v_src.user_id = v_user then return v_src.id; end if;   -- already yours

  -- a previous fork of the same system row wins over making a second one
  select id into v_new from public.exercises
   where user_id = v_user and code = v_src.code;
  if found then
    update public.program_days set exercise_id = v_new
     where user_id = v_user and exercise_id = v_src.id;
    return v_new;
  end if;

  insert into public.exercises
    (user_id, code, name, category, focus, est_kcal, duration_min, notes,
     work_met, recovery_met, duty_pct, epoc_factor, kcal_override, forked_from)
  values
    (v_user, v_src.code, v_src.name, v_src.category, v_src.focus, v_src.est_kcal,
     v_src.duration_min, v_src.notes, v_src.work_met, v_src.recovery_met,
     v_src.duty_pct, v_src.epoc_factor, v_src.kcal_override, v_src.id)
  returning id into v_new;

  insert into public.exercise_movements
    (exercise_id, name, order_index, target_sets, rep_low, rep_high, tracking, notes)
  select v_new, name, order_index, target_sets, rep_low, rep_high, tracking, notes
    from public.exercise_movements where exercise_id = v_src.id;

  update public.program_days set exercise_id = v_new
   where user_id = v_user and exercise_id = v_src.id;

  -- carry history across, or every fork would look like a fresh start
  update public.set_logs set exercise_id = v_new
   where user_id = v_user and exercise_id = v_src.id;

  update public.set_logs sl set movement_id = nm.id
    from public.exercise_movements om
    join public.exercise_movements nm
      on nm.exercise_id = v_new and nm.name = om.name
   where om.exercise_id = v_src.id
     and sl.movement_id = om.id
     and sl.user_id = v_user;

  return v_new;
end $$;

-- Put a session on a day. Scope 'day' is a one-off; 'weekday' rewrites every
-- future occurrence of that weekday; 'all' rewrites everything from here on.
-- Past days are never touched - they are a record, not a plan.
create or replace function public.set_day_exercise(
  p_date date, p_exercise_id bigint, p_scope text default 'day')
returns integer language plpgsql security invoker set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_dow integer; v_n integer;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if p_scope not in ('day','weekday','all') then
    raise exception 'scope must be day, weekday or all';
  end if;
  if p_exercise_id is not null and not exists (
       select 1 from public.exercises
        where id = p_exercise_id and (user_id is null or user_id = v_user)) then
    raise exception 'exercise % not found', p_exercise_id;
  end if;

  v_dow := extract(isodow from p_date);

  update public.program_days
     set exercise_id = p_exercise_id
   where user_id = v_user
     and case p_scope
           when 'day'     then day_date = p_date
           when 'weekday' then day_date >= p_date and extract(isodow from day_date) = v_dow
           else                day_date >= p_date
         end;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ============================================================ score_day_inner v3
-- Same weights, same philosophy. What changed: training calories now come from
-- session_kcal (duty cycle + bodyweight + minutes) instead of a flat constant,
-- 'mixed' sessions are graded on showing up rather than on tonnage, and coffee
-- rides along in the detail blob so it can be correlated with sleep later.
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
  v_steps_kcal numeric; v_train_kcal numeric; v_extra_burn numeric;
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

  v_trained := v_vol > 0
            or coalesce(v_log.training_minutes,0) > 0
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

  -- minutes logged win; otherwise assume the session ran as prescribed
  v_min := coalesce(v_log.training_minutes, case when v_trained then v_dur else 0 end);
  v_train_kcal := case
    when not v_trained or coalesce(v_min,0) <= 0 then 0
    when v_kover is not null and coalesce(v_dur,0) > 0 then v_kover * (v_min / v_dur)
    when v_kover is not null then v_kover
    else public.session_kcal(v_min, v_bw, v_wmet, v_rmet, v_duty,
                             v_prof.set_seconds, v_prof.rest_seconds, v_epoc)
  end + coalesce(v_extra_burn,0);

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
                        'training_min',coalesce(v_min,0)),
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
