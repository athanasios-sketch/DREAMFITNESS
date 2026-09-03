-- Βρώμη, properly, on fasting days.
--
-- Wednesday already ate oats in oat milk; Friday was still the soy-and-tahini
-- bowl from v1. Both fasting breakfasts are now oats in a plant milk, and both
-- get honey - which stays in on a fasting day, because the Wednesday/Friday
-- rule is about meat and dairy and honey has always been the exception.
--
-- The two bowls are deliberately not the same. Almond milk is 38 kcal where oat
-- milk is 108, so Friday buys 60g of oats for the same breakfast that Wednesday
-- buys 45g with. Same calories, more food - that difference is the whole reason
-- to keep two versions rather than picking one milk and moving on.

-- ============================================================ standalone βρώμη
-- Oats and honey as their own rows, the way OATM/ALMM already are: so they can
-- ride alongside any meal in the plan, or be swapped into a slot on their own,
-- without needing a bespoke recipe for every combination.
insert into public.meals
  (user_id, code, name, slot, day_type, version, protein_g, carbs_g, fat_g, kcal,
   ingredients, instructions, prep_min, cook_min, equipment, steps, tips) values

  (null, 'OATS', 'Βρώμη (60g dry)', 'snack', 'any', 1, 8.1, 40.2, 3.9, 227,
   '60g rolled oats', 'Simmer 4-5 min in whatever milk the day allows.', 2, 5, 'Pot',
   array['Bring 250ml of milk or water to a simmer with a pinch of salt.',
         'Stir in 60g oats, cook 4-5 min until it thickens, and take it off the heat.'],
   array['Weigh them dry. 60g looks like nothing in the bag and fills the bowl once cooked - eyeballing it is how a 227 kcal side turns into 400.',
         'Rolled and quick oats have identical macros. Steel-cut need 25 minutes and are not worth the pot on a training morning.',
         'The pinch of salt is what makes oats taste of anything. Leaving it out is why plain oats taste like paste.']),

  (null, 'HONEY', 'Honey (15g)', 'snack', 'any', 1, 0.0, 12.5, 0.0, 46,
   '15g honey', 'A level tablespoon, added off the heat.', 1, 0, 'No cooking',
   array['15g, about a level tablespoon.',
         'Add it once the pot is off the heat and has stopped steaming.'],
   array['Honey stays in on fasting days - the Wednesday/Friday rule is about meat and dairy, and honey is the standing exception.',
         '15g is 46 kcal. Free-pouring from the jar is closer to 40g, which is 125 kcal you never logged.',
         'Stirred into a boiling pot it is just sugar. On a cooled bowl you actually taste it.']),

-- ============================================================ Friday breakfast
  (null, 'BF3', 'Βρώμη, Almond Milk & Honey', 'breakfast', 'fasting', 3, 49.2, 57.1, 15.1, 561,
   '50g vegan protein, 60g oats, 250ml unsweetened almond milk, 15g honey, 10g tahini',
   'Simmer the oats in almond milk, protein off the heat, honey and tahini on top.',
   5, 6, 'Pot',
   array['Bring 250ml unsweetened almond milk to a simmer with a pinch of salt.',
         'Stir in 60g oats and cook 5 min, stirring, until it thickens - almond milk is thin and needs the extra minute.',
         'Off the heat, stir in 50g vegan protein a third at a time.',
         'Honey and tahini on top once it stops steaming.'],
   array['Almond milk is 38 kcal against oat milk''s 108, which is what pays for 60g of oats here instead of Wednesday''s 45g.',
         'Off the heat for the protein is not optional - powder in boiling liquid seizes into lumps you cannot stir out.',
         'Check the carton says unsweetened. The sweetened version triples the carbs and you are already adding honey.']),

-- ============================================================ oats, elsewhere
-- The version for a day you would rather eat something savoury at breakfast, or
-- want the βρώμη after training instead of before it. No pot, so it survives a
-- busy kitchen.
  (null, 'SF4', 'Overnight Βρώμη & Honey', 'snack', 'any', 1, 17.8, 36.9, 5.7, 270,
   '40g oats, 200ml unsweetened almond milk, 15g vegan protein, 10g honey, cinnamon',
   'Soak the oats overnight, protein and honey stirred in cold.', 3, 0, 'No cooking',
   array['Stir 40g oats into 200ml almond milk in a jar, add cinnamon, and leave it in the fridge overnight.',
         'In the morning stir in 15g vegan protein and 10g honey.',
         'Hot version: simmer it 4 min in a pot instead, protein off the heat.'],
   array['This is the slot to move βρώμη to if you would rather have something savoury first thing.',
         'It keeps thickening overnight. A splash more almond milk in the morning brings it back.',
         'Cold protein powder dissolves better than hot - this is the one place you can stir it straight in.'])

on conflict (code) where user_id is null do update set
  name = excluded.name, slot = excluded.slot, day_type = excluded.day_type,
  version = excluded.version,
  protein_g = excluded.protein_g, carbs_g = excluded.carbs_g, fat_g = excluded.fat_g,
  kcal = excluded.kcal, ingredients = excluded.ingredients,
  instructions = excluded.instructions, prep_min = excluded.prep_min,
  cook_min = excluded.cook_min, equipment = excluded.equipment,
  steps = excluded.steps, tips = excluded.tips;

-- ======================================================= Wednesday breakfast
-- Honey in, tahini 15g -> 10g to pay for it. Net +15 kcal, and a bowl you will
-- actually finish on a fasting morning.
update public.meals set
  name        = 'Βρώμη, Oat Milk & Honey',
  protein_g   = 47.9, carbs_g = 62.1, fat_g = 15.1, kcal = 575,
  ingredients = '50g vegan protein, 45g oats, 250ml oat milk, 15g honey, 10g tahini',
  steps = array[
    'Bring 250ml oat milk just to a simmer with a pinch of salt, stir in 45g oats, cook 4 min.',
    'Off the heat, stir in 50g vegan protein a third at a time.',
    'Honey and tahini on top once it stops steaming.'],
  tips = array[
    'Off the heat is not optional - protein powder in boiling liquid seizes into lumps.',
    'Oat milk scorches faster than soy. Keep it moving and keep the heat moderate.',
    'Honey goes on at the end. Boiled into the pot it is just sugar; on top of the bowl you taste it.'],
  instructions = 'Simmer the oats in oat milk, protein off the heat, honey and tahini on top.'
 where code = 'BF2v2' and user_id is null;

-- BF1v2 keeps its place as the soy option, but it is no longer on the plan.
update public.meals
   set tips = array[
     'Protein powder hitting boiling liquid seizes into lumps. Always off the heat.',
     'Tahini on top, not stirred in - it turns bitter with prolonged heat.',
     'The soy version, kept as a swap. Oat milk or almond milk go in one-for-one if you would rather have those.',
     '15g of honey off the heat costs 46 kcal and makes it taste like breakfast.']
 where code = 'BF1v2' and user_id is null;

-- ==================================================== generate_program v3
-- Only the Friday breakfast changes: BF1v2 (soy, tahini) -> BF3 (βρώμη, almond
-- milk, honey). Everything else is migration 20260902170000 verbatim.
create or replace function public.generate_program(p_start date default '2026-09-02')
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_user  uuid := (select auth.uid());
  v_day   integer; v_date date; v_dow integer; v_fast boolean;
  v_pd bigint; v_codes text[]; v_ex text; v_chest_monday boolean;
  v_reg   integer := 0;
  v_p numeric; v_c numeric; v_f numeric; v_k integer; v_n integer := 0;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  delete from public.program_days where user_id = v_user;

  for v_day in 1..90 loop
    v_date := p_start + (v_day - 1);
    v_dow  := extract(isodow from v_date);      -- 1=Mon .. 7=Sun
    v_fast := v_dow in (3, 5);                  -- Wednesday, Friday

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
      -- both fasting breakfasts are βρώμη now; the milk is what alternates.
      -- Wednesday oat milk (creamier, 45g oats), Friday almond (leaner, 60g).
      v_codes := case when v_dow = 3
                   then array['BF2v2','LF1v2','SF1v2','DF1v2','SF2']
                   else array['BF3','LF1v2','SF1v2','DF2v2','SF3'] end;
    else
      v_reg := v_reg + 1;
      v_codes := case when v_reg % 2 = 1
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

-- ============================================================ backfill
-- generate_program is never called from the app - the 90 days already exist, so
-- redefining the function on its own changes nothing you can see. Rewrite the
-- plan in place instead, from today forward. The past is a record of what was
-- eaten, not a plan to be edited.
update public.program_day_meals pdm
   set meal_id = (select id from public.meals where code = 'BF3' and user_id is null)
  from public.program_days pd
 where pdm.program_day_id = pd.id
   and pdm.slot_index = 1
   and pd.day_date >= current_date
   and extract(isodow from pd.day_date) = 5
   and pd.day_type = 'fasting';

-- Daily targets are a sum over the day's meals, so both the Friday swap above
-- and Wednesday's new honey have to be pushed back into program_days.
update public.program_days pd
   set protein_target_g = t.p, carbs_target_g = t.c, fat_target_g = t.f, kcal_target = t.k
  from (select pdm.program_day_id as id,
               sum(m.protein_g) as p, sum(m.carbs_g) as c,
               sum(m.fat_g) as f, round(sum(m.kcal))::int as k
          from public.program_day_meals pdm
          join public.meals m on m.id = pdm.meal_id
         group by pdm.program_day_id) t
 where pd.id = t.id
   and pd.day_date >= current_date;
