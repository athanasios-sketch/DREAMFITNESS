-- Supplements were implicitly Thanos's.
--
-- Two things went wrong the moment a second person existed.
--
-- First, Today.svelte renders habit-kind rows only when the day is a νηστεία
-- day, because the only habit that existed was the coffee-and-iron rule, which
-- only bites on one. Ntinos has no fasting days at all, so his electrolytes -
-- the single most common reason a ketogenic diet falls over in week one - would
-- have been invisible every day of the plan.
--
-- Second, the previous migration added CREAT-K and VITD-K beside the existing
-- CREATINE and VITD. Creatine is creatine; the reason it matters in a deficit
-- does not change with the diet. That was two rows for one supplement, and both
-- men would have seen both.
--
-- So scope becomes explicit instead of inferred: which diets a row applies to,
-- and which day types. Null means "all", which is what a supplement usually is.

alter table public.supplements
  add column if not exists diet_modes text[],
  add column if not exists day_types  text[];

comment on column public.supplements.diet_modes is
  'Diet modes this applies to. NULL = all. e.g. {keto} for electrolytes.';
comment on column public.supplements.day_types is
  'Day types this applies to. NULL = every day. e.g. {fasting} for the
   coffee-and-iron rule, which is only about non-heme iron on plant days.';

-- the duplicates go; the originals become everyone's
delete from public.supplements where user_id is null and code in ('CREAT-K','VITD-K');

update public.supplements set diet_modes = null, day_types = null
 where user_id is null and code in ('CREATINE','VITD');

-- Thanos only: this is about non-heme iron from chickpeas and lentils, which is
-- a νηστεία-day problem and a balanced-plan one.
update public.supplements set diet_modes = array['balanced'], day_types = array['fasting']
 where user_id is null and code = 'IRONCOF';

-- Ntinos only, but EVERY day - which was the bug.
update public.supplements set diet_modes = array['keto'], day_types = null
 where user_id is null and code in ('ELECTRO','KETOTEST');

-- Creatine's note mentioned Wednesday and Friday plant days, which is now only
-- half the audience.
update public.supplements set
  why = 'The most evidence-backed supplement there is for holding and adding muscle in a deficit, which is the whole ask for both of these plans. On a plant day it also covers a diet carrying essentially no dietary creatine; on a ketogenic cut it matters because training at the end of a long fast is better done on a full phosphocreatine tank.'
 where user_id is null and code = 'CREATINE';
