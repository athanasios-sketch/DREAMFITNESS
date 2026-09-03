-- Rest days were eating training-day food.
--
-- The generator does the right thing and the verification made it obvious:
-- Ntinos's rest days price out at a 2035 kcal budget against a menu serving
-- 2357. Three days a week, 322 kcal each, over 180 days - about 24,800 kcal, or
-- 3.2 kg of fat that would quietly have failed to come off. menu_kcal existing
-- as a column distinct from kcal_target is what made it visible; it was added
-- for exactly this and this is the first time it has caught anything.
--
-- The fix is not smaller portions of the same plates. On a lower-expenditure
-- day protein must NOT move - it is defending the same lean tissue on less
-- energy, which is when it matters most - so what comes down is fat. These
-- three hold protein at 190 g and take ~35 g of fat out, using leaner sources
-- (breast rather than thigh, turkey rather than pork) with the olive oil
-- measured rather than poured.
--
-- Rest day totals: 2022 kcal, P190 g, net carbs 27.4 g,
-- fat 120 g (1.17 g/kg, well clear of the 0.6 g/kg floor),
-- fibre 27 g, vegetables 700 g.

insert into public.meals
  (user_id, code, name, slot, day_type, protein_g, carbs_g, fat_g, kcal,
   fiber_g, veg_g, instructions)
values
  (null, 'K-R1', 'Airfryer chicken breast, χόρτα and courgette', 'lunch', 'regular', 72.09, 18.13, 47.39, 783, 10.99, 400.0, 'Airfryer 190C, 16-18 min. Chorta boiled and drained hard, courgette in the basket alongside the chicken. The olive oil is measured, not poured - on a rest day it is most of what separates this plate from the training-day version.'),
  (null, 'K-R2', 'Turkey, rocket and chia salad', 'dinner', 'regular', 65.86, 18.41, 41.89, 697, 7.63, 300.0, 'Airfryer or pan, 190C or medium-high, 14-16 min. Turkey rather than thigh meat because protein has to hold at 66 g while the calories come down by a hundred. Everything else raw, oil measured.'),
  (null, 'K-R3', 'Yogurt, whey and chia', 'snack', 'regular', 52.48, 17.52, 30.57, 542, 8.01, 0.0, 'Chia stirred in ten minutes ahead so it swells in the bowl rather than in you. No added oil - the walnuts are the fat, and a spoonful of olive oil in yogurt is a thing nobody does twice.')
on conflict (code) where user_id is null do update set
  name=excluded.name, slot=excluded.slot, day_type=excluded.day_type,
  protein_g=excluded.protein_g, carbs_g=excluded.carbs_g, fat_g=excluded.fat_g,
  kcal=excluded.kcal, fiber_g=excluded.fiber_g, veg_g=excluded.veg_g,
  instructions=excluded.instructions;

delete from public.meal_ingredients mi using public.meals m
  where m.id = mi.meal_id and m.user_id is null and m.code like 'K-R%';

insert into public.meal_ingredients
  (meal_id, order_index, name, amount, unit, role,
   kcal_100, protein_100, carbs_100, fat_100, fiber_100, is_veg)
select m.id, v.order_index, v.name, v.amount, 'g', v.role,
       v.kcal_100, v.protein_100, v.carbs_100, v.fat_100, v.fiber_100, v.is_veg
  from (values
    ('K-R1', 0, 'Χόρτα (wild greens), boiled', 250, 'veg', 25, 2.5, 4.0, 0.3, 2.5, true),
    ('K-R1', 1, 'Zucchini (κολοκυθάκι)', 150, 'veg', 17, 1.2, 3.1, 0.3, 1.0, true),
    ('K-R1', 2, 'Ground flaxseed', 12, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-R1', 3, 'Chicken breast, raw', 275, 'protein', 120, 22.5, 0, 2.6, 0, false),
    ('K-R1', 4, 'Olive oil', 34, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-R2', 0, 'Rocket (ρόκα)', 80, 'veg', 25, 2.6, 3.7, 0.7, 1.6, true),
    ('K-R2', 1, 'Cucumber', 150, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-R2', 2, 'Tomato', 70, 'veg', 18, 0.9, 3.9, 0.2, 1.2, true),
    ('K-R2', 3, 'Feta', 35, 'protein', 264, 14.2, 4.1, 21.3, 0, false),
    ('K-R2', 4, 'Chia seeds', 14, 'extra', 486, 17.0, 42.0, 31.0, 34.0, false),
    ('K-R2', 5, 'Turkey breast, raw', 250, 'protein', 104, 21.9, 0, 1.7, 0, false),
    ('K-R2', 6, 'Olive oil', 25, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-R3', 0, 'Greek yogurt 10% (στραγγιστό)', 120, 'protein', 133, 6.4, 4.0, 10.0, 0, false),
    ('K-R3', 1, 'Chia seeds', 20, 'extra', 486, 17.0, 42.0, 31.0, 34.0, false),
    ('K-R3', 2, 'Walnuts', 18, 'extra', 654, 15.0, 14.0, 65.0, 6.7, false),
    ('K-R3', 3, 'Whey isolate powder', 45, 'protein', 373, 86.0, 4.0, 1.5, 0, false)
  ) as v(code, order_index, name, amount, role,
         kcal_100, protein_100, carbs_100, fat_100, fiber_100, is_veg)
  join public.meals m on m.code = v.code and m.user_id is null;

select public.recompute_meal_macros(m.id) from public.meals m
 where m.user_id is null and m.code like 'K-R%';

-- point every keto rest day at them
update public.program_template_days td
   set meal_codes = array['K-R1','K-R2','K-R3']
  from public.program_templates t, public.profiles p
 where td.template_id = t.id and t.user_id = p.id
   and p.diet_mode = 'keto' and td.exercise_code = 'REST';
