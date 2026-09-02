-- water_l was numeric(4,1): one decimal, so a 250ml top-up (0.25) could not be
-- represented and Postgres rounded it to 0.3 = 300ml. Two decimals fixes it.
alter table public.day_logs
  alter column water_l type numeric(5,2);

-- Meal swaps: eating a second dinner in place of lunch is a normal move,
-- especially on fasting days where each slot has only one option. meal_logs
-- already carries meal_id, so a swap is just logging a different meal in the
-- slot. This index keeps the "what did I actually eat" lookup cheap.
create index if not exists meal_logs_slot_idx on public.meal_logs (day_log_id, slot_index);

comment on column public.meal_logs.meal_id is
  'The meal actually eaten. Differs from the planned meal when swapped is true.';
comment on column public.meal_logs.portion is
  'Multiplier on the meal macros. 2.0 = ate it twice.';
