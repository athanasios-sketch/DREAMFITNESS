-- Neck is the measurement that turns the tape into a body-composition reading.
-- Waist alone says where the mass sits. Waist MINUS neck, against height, is
-- the US Navy circumference estimate of what fraction of that mass is fat -
-- and on a recomp that is the number the scale cannot give you, because the
-- scale cannot tell a kilo of fat lost from a kilo of muscle lost.
--
-- The estimate itself is not stored. It is a pure function of three numbers we
-- already keep, so computing it at read time (lib/api.ts navyBodyFatPct) means
-- there is no cached percentage to go stale when a height is corrected.
alter table public.day_logs
  add column if not exists neck_cm numeric(4,1) check (neck_cm between 20 and 80);

comment on column public.day_logs.neck_cm is
  'Neck circumference in cm, taken below the larynx with the tape level.
   Pairs with waist_cm and profiles.height_cm for the US Navy body-fat estimate.';
