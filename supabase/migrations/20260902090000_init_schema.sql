-- DREAMFITNESS :: core schema
-- All dates are Europe/Athens LOCAL CALENDAR DATES (type `date`), never timestamptz.
-- Athens shifts UTC+3 -> UTC+2 on 2026-10-25 (day 54); storing instants would corrupt
-- day boundaries on that date.

create schema if not exists private;

-- ============================================================ profiles
create table public.profiles (
  id                      uuid primary key references auth.users(id) on delete cascade,
  email                   text,
  sex                     text check (sex in ('male','female')),
  birth_date              date,
  height_cm               numeric(5,1) check (height_cm between 100 and 250),
  start_weight_kg         numeric(5,2) check (start_weight_kg between 30 and 300),
  timezone                text not null default 'Europe/Athens',
  program_start_date      date not null default '2026-09-02',
  activity_multiplier     numeric(4,3) not null default 1.600
                            check (activity_multiplier between 1.0 and 2.5),
  protein_g_per_kg        numeric(4,2) not null default 2.10,
  steps_target            integer not null default 10000 check (steps_target > 0),
  water_target_l          numeric(3,1) not null default 3.5,
  kcal_target_override    integer check (kcal_target_override between 800 and 6000),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- ============================================================ reference data
-- user_id null => system/global row, readable by every authenticated user.
create table public.meals (
  id            bigint generated always as identity primary key,
  user_id       uuid references auth.users(id) on delete cascade,
  code          text not null,
  name          text not null,
  slot          text not null check (slot in ('breakfast','lunch','snack','dinner')),
  day_type      text not null check (day_type in ('regular','fasting','any')),
  version       integer not null default 1,
  protein_g     numeric(6,2) not null check (protein_g >= 0),
  carbs_g       numeric(6,2) not null check (carbs_g   >= 0),
  fat_g         numeric(6,2) not null check (fat_g     >= 0),
  kcal          integer      not null check (kcal      >= 0),
  ingredients   text,
  instructions  text,
  created_at    timestamptz not null default now()
);
create unique index meals_system_code_key on public.meals (code) where user_id is null;
create index meals_user_id_idx  on public.meals (user_id);
create index meals_slot_type_idx on public.meals (slot, day_type);

create table public.exercises (
  id             bigint generated always as identity primary key,
  user_id        uuid references auth.users(id) on delete cascade,
  code           text not null,
  name           text not null,
  category       text not null check (category in ('resistance','cardio','rest')),
  focus          text,
  est_kcal       integer not null default 0 check (est_kcal >= 0),
  duration_min   integer not null default 0 check (duration_min >= 0),
  notes          text,
  created_at     timestamptz not null default now()
);
create unique index exercises_system_code_key on public.exercises (code) where user_id is null;
create index exercises_user_id_idx on public.exercises (user_id);

-- individual lifts inside a session template (drives progressive-overload scoring)
create table public.exercise_movements (
  id             bigint generated always as identity primary key,
  exercise_id    bigint not null references public.exercises(id) on delete cascade,
  name           text not null,
  order_index    integer not null default 0,
  target_sets    integer check (target_sets > 0),
  rep_low        integer check (rep_low > 0),
  rep_high       integer check (rep_high >= rep_low)
);
create index exercise_movements_exercise_id_idx on public.exercise_movements (exercise_id);

-- ============================================================ the 90-day plan
create table public.program_days (
  id                bigint generated always as identity primary key,
  user_id           uuid not null references auth.users(id) on delete cascade,
  day_no            integer not null check (day_no between 1 and 365),
  day_date          date not null,
  day_type          text not null check (day_type in ('regular','fasting')),
  exercise_id       bigint references public.exercises(id) on delete set null,
  steps_target      integer not null default 10000,
  water_target_l    numeric(3,1) not null default 3.5,
  protein_target_g  numeric(6,2) not null,
  carbs_target_g    numeric(6,2) not null,
  fat_target_g      numeric(6,2) not null,
  kcal_target       integer      not null,
  created_at        timestamptz not null default now(),
  unique (user_id, day_date),
  unique (user_id, day_no)
);
create index program_days_user_date_idx   on public.program_days (user_id, day_date);
create index program_days_exercise_id_idx on public.program_days (exercise_id);

create table public.program_day_meals (
  id              bigint generated always as identity primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  program_day_id  bigint not null references public.program_days(id) on delete cascade,
  meal_id         bigint not null references public.meals(id) on delete restrict,
  slot_index      smallint not null check (slot_index between 1 and 8),
  unique (program_day_id, slot_index)
);
create index program_day_meals_user_id_idx on public.program_day_meals (user_id);
create index program_day_meals_day_idx     on public.program_day_meals (program_day_id);
create index program_day_meals_meal_id_idx on public.program_day_meals (meal_id);

-- ============================================================ daily logging
create table public.day_logs (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users(id) on delete cascade,
  log_date       date not null,
  weight_kg      numeric(5,2) check (weight_kg between 30 and 300),
  waist_cm       numeric(4,1) check (waist_cm between 40 and 200),
  chest_cm       numeric(4,1) check (chest_cm between 40 and 200),
  arms_cm        numeric(4,1) check (arms_cm  between 15 and 80),
  sleep_hours    numeric(3,1) check (sleep_hours between 0 and 24),
  steps          integer check (steps >= 0),
  water_l        numeric(4,1) check (water_l >= 0),
  mood           smallint check (mood     between 1 and 5),
  energy         smallint check (energy   between 1 and 5),
  soreness       smallint check (soreness between 1 and 5),
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (user_id, log_date)
);
create index day_logs_user_date_idx on public.day_logs (user_id, log_date desc);
-- partial index: weight-trend queries only ever touch rows that have a weight
create index day_logs_weight_idx on public.day_logs (user_id, log_date)
  where weight_kg is not null;

create table public.meal_logs (
  id                   bigint generated always as identity primary key,
  user_id              uuid not null references auth.users(id) on delete cascade,
  day_log_id           bigint not null references public.day_logs(id) on delete cascade,
  program_day_meal_id  bigint references public.program_day_meals(id) on delete set null,
  meal_id              bigint references public.meals(id) on delete set null,
  slot_index           smallint not null check (slot_index between 1 and 8),
  completed            boolean not null default false,
  portion              numeric(4,2) not null default 1.00 check (portion >= 0),
  swapped              boolean not null default false,
  created_at           timestamptz not null default now(),
  unique (day_log_id, slot_index)
);
create index meal_logs_user_id_idx    on public.meal_logs (user_id);
create index meal_logs_day_log_id_idx on public.meal_logs (day_log_id);
create index meal_logs_meal_id_idx    on public.meal_logs (meal_id);
create index meal_logs_pdm_idx        on public.meal_logs (program_day_meal_id);

-- off-plan food and exercise
create table public.extra_items (
  id                bigint generated always as identity primary key,
  user_id           uuid not null references auth.users(id) on delete cascade,
  day_log_id        bigint not null references public.day_logs(id) on delete cascade,
  kind              text not null check (kind in ('food','exercise')),
  name              text not null,
  protein_g         numeric(6,2) default 0 check (protein_g >= 0),
  carbs_g           numeric(6,2) default 0 check (carbs_g   >= 0),
  fat_g             numeric(6,2) default 0 check (fat_g     >= 0),
  kcal              integer      default 0,
  duration_min      integer check (duration_min >= 0),
  kcal_burned       integer default 0 check (kcal_burned >= 0),
  created_at        timestamptz not null default now(),
  -- food rows carry macros; exercise rows carry burn
  check (kind = 'exercise' or (protein_g is not null and kcal is not null))
);
create index extra_items_user_id_idx    on public.extra_items (user_id);
create index extra_items_day_log_id_idx on public.extra_items (day_log_id);

-- progressive overload
create table public.set_logs (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users(id) on delete cascade,
  day_log_id     bigint not null references public.day_logs(id) on delete cascade,
  exercise_id    bigint references public.exercises(id) on delete set null,
  movement_id    bigint references public.exercise_movements(id) on delete set null,
  movement_name  text not null,
  set_no         smallint not null check (set_no between 1 and 20),
  reps           smallint not null check (reps between 0 and 100),
  weight_kg      numeric(6,2) not null default 0 check (weight_kg >= 0),
  rpe            numeric(3,1) check (rpe between 1 and 10),
  volume_load    numeric(10,2) generated always as (reps * weight_kg) stored,
  created_at     timestamptz not null default now()
);
create index set_logs_user_id_idx     on public.set_logs (user_id);
create index set_logs_day_log_id_idx  on public.set_logs (day_log_id);
create index set_logs_exercise_id_idx on public.set_logs (exercise_id);
create index set_logs_movement_id_idx on public.set_logs (movement_id);
-- drives "vs your trailing average for this session type"
create index set_logs_user_ex_idx     on public.set_logs (user_id, exercise_id, created_at desc);

-- ============================================================ scoring output
create table public.daily_scores (
  id                bigint generated always as identity primary key,
  user_id           uuid not null references auth.users(id) on delete cascade,
  score_date        date not null,
  nutrition_score   numeric(5,2) not null default 0,
  training_score    numeric(5,2) not null default 0,
  movement_score    numeric(5,2) not null default 0,
  recovery_score    numeric(5,2) not null default 0,
  total_score       numeric(5,2) not null default 0,
  protein_actual_g  numeric(6,2),
  kcal_actual       integer,
  volume_load       numeric(10,2),
  detail            jsonb not null default '{}'::jsonb,
  computed_at       timestamptz not null default now(),
  unique (user_id, score_date)
);
create index daily_scores_user_date_idx on public.daily_scores (user_id, score_date desc);

-- ============================================================ RLS
alter table public.profiles           enable row level security;
alter table public.meals              enable row level security;
alter table public.exercises          enable row level security;
alter table public.exercise_movements enable row level security;
alter table public.program_days       enable row level security;
alter table public.program_day_meals  enable row level security;
alter table public.day_logs           enable row level security;
alter table public.meal_logs          enable row level security;
alter table public.extra_items        enable row level security;
alter table public.set_logs           enable row level security;
alter table public.daily_scores       enable row level security;

create policy profiles_own on public.profiles for all to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- reference tables: system rows readable by all, user rows owner-only
create policy meals_read on public.meals for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));
create policy meals_write on public.meals for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy exercises_read on public.exercises for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));
create policy exercises_write on public.exercises for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy exercise_movements_read on public.exercise_movements for select to authenticated
  using (exists (select 1 from public.exercises e
                 where e.id = exercise_id
                   and (e.user_id is null or e.user_id = (select auth.uid()))));

-- owner-only tables (user_id denormalized onto children so policies stay index-only)
create policy program_days_own      on public.program_days      for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy program_day_meals_own on public.program_day_meals for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy day_logs_own          on public.day_logs          for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy meal_logs_own         on public.meal_logs         for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy extra_items_own       on public.extra_items       for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy set_logs_own          on public.set_logs          for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy daily_scores_own      on public.daily_scores      for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ============================================================ updated_at
create or replace function private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;

create trigger profiles_touch  before update on public.profiles
  for each row execute function private.touch_updated_at();
create trigger day_logs_touch  before update on public.day_logs
  for each row execute function private.touch_updated_at();
