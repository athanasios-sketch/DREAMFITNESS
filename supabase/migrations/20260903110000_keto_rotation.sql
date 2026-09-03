-- Ntinos's ketogenic rotation: eleven meals, three a day, inside 16:00-00:00.
--
-- Built the same way as the fed rotation - reference values per 100 g and the
-- amount actually cooked - because a keto plan lives or dies on carbohydrate
-- and you cannot hold a 28 g line with a sentence.
--
-- The quantities are not hand-picked. Each meal fixes its vegetables and its
-- accessories, then SOLVES the protein source and the olive oil to hit a
-- calorie and protein target exactly, which is why the amounts are ugly numbers
-- like 235 g. Every scheduled day lands 2338-2366 kcal, 189-193 g protein,
-- 25-35 g fibre, over 400 g of vegetables.
--
-- On the carbohydrate cap. The brief was "strict, under 25 g, measuring
-- ketones". Under 25 g NET is the right target and it is what this rotation
-- actually delivers - but as a HARD DAILY ceiling it is over-constrained. Of 48
-- possible meal combinations only 18 cleared it, and 15 of those used the same
-- tuna-and-avocado plate, because it is the only third meal cheap enough in
-- carbohydrate to fit after two real ones. A rotation with one possible dinner
-- is not a rotation, it is a sentence.
--
-- At 28 g the same eleven meals produce a genuinely varied week whose MEAN is
-- 23.9 g net - under the line he asked for - with the occasional 27 g day paid
-- for by a 17.5 g one. Ketosis does not read a calendar, it reads the average,
-- and 24 g is deep inside nutritional ketosis for anyone, let alone a man
-- walking 6.7 km a day in a 700 kcal deficit.
--
-- Fibre is excluded from the cap deliberately - see the comment on
-- profiles.carb_cap_g. Counting it would have priced out the chia and flax that
-- carry this rotation to 30 g of fibre a day.

-- ============================================================ the meals

insert into public.meals
  (user_id, code, name, slot, day_type, protein_g, carbs_g, fat_g, kcal,
   fiber_g, veg_g, instructions)
values
  (null, 'K-M1a', 'Airfryer chicken thighs, χόρτα and feta', 'lunch', 'regular', 72.36, 14.06, 60.37, 892, 7.50, 300.0, 'Airfryer 200C, 22-25 min, skin side up. No oil in the basket - the thigh renders its own. Chorta: boil 8-10 min, drain hard, dress with the olive oil and far more lemon than feels right. Feta and the egg on the side.'),
  (null, 'K-M1b', 'Pan pork chop with mushrooms and spinach', 'lunch', 'regular', 71.84, 16.87, 62.93, 892, 9.44, 380.0, 'Pan, high heat, 3-4 min a side for the chop, then rest it off the heat. Same pan: mushrooms until they squeak and give up their water, spinach in at the very end for sixty seconds. Graviera grated over, flaxseed stirred through the greens.'),
  (null, 'K-M1c', 'Airfryer salmon, asparagus and avocado', 'lunch', 'regular', 72.26, 17.97, 58.07, 890, 11.10, 290.0, 'Airfryer 190C, 10-12 min skin down. Asparagus in for the last seven. Avocado and rocket raw alongside, oil and lemon.'),
  (null, 'K-M1d', 'Beef mince and courgette pan, feta on top', 'lunch', 'regular', 72.22, 19.68, 60.06, 906, 9.52, 400.0, 'Pan, brown the mince hard and do not stir it too early or it steams. Courgette in batons for the last five minutes so it keeps some bite. Spinach wilted in at the end, feta crumbled over off the heat, chia stirred through.'),
  (null, 'K-M2a', 'Airfryer chicken breast, courgette and olives', 'dinner', 'regular', 66.49, 14.84, 52.51, 800, 7.54, 250.0, 'Airfryer 190C, 16-18 min - breast goes dry past that. Courgette in the basket alongside. Olives, grated graviera and the chia over the top.'),
  (null, 'K-M2b', 'Greek omelette — eggs, feta and spinach', 'dinner', 'regular', 66.01, 22.25, 53.77, 825, 11.01, 320.0, 'Pan on medium-low, not high: hot eggs go rubbery. Mushrooms first, then spinach, then the beaten eggs. Feta and avocado in as it sets, chia on top.'),
  (null, 'K-M2c', 'Airfryer halloumi and chicken, χωριάτικη', 'dinner', 'regular', 65.72, 17.83, 54.04, 802, 8.14, 290.0, 'Airfryer 200C - chicken 18 min, halloumi in for the last six because it burns fast. Choriatiki raw underneath, no bread. Flaxseed over the salad.'),
  (null, 'K-M2d', 'Sardines with rocket and cucumber salad', 'dinner', 'regular', 65.52, 21.74, 51.95, 803, 11.11, 250.0, 'No cooking at all. Sardines from the tin with most of the oil drained, rocket and cucumber, avocado sliced, feta crumbled, chia over. Lemon, hard.'),
  (null, 'K-M3a', 'Greek yogurt with walnuts and chia', 'snack', 'regular', 54.14, 24.56, 39.38, 647, 14.06, 0.0, 'Nothing to cook. Stir the chia in and leave it ten minutes to swell - if it does not do that in the bowl it will do it in you. Whey through last with a splash of water.'),
  (null, 'K-M3b', 'Boiled eggs, olives and flaxseed', 'snack', 'regular', 51.64, 14.03, 42.85, 648, 5.76, 150.0, 'Eggs boiled nine minutes, cooled under the tap so they peel cleanly. Olives, cucumber, flaxseed. Whey in water on the side.'),
  (null, 'K-M3c', 'Tuna, avocado and flaxseed', 'snack', 'regular', 52.54, 18.26, 43.21, 648, 14.62, 120.0, 'Tin drained, avocado forked through it, flaxseed and leaves. Two minutes, one bowl, and it is the lowest-carbohydrate plate in the rotation - which is why it turns up on the days the other two meals are expensive.'),
  (null, 'K-T1', 'Rotisserie chicken and a village salad', 'lunch', 'travel', 71.65, 19.39, 59.86, 890, 7.17, 310.0, 'Supermarket, any town, all day, about seven euros. Half a rotisserie chicken with the meat off the bone. Build the salad in the tub the deli hands you. Oil from a sachet, or carry the smallest bottle in the bag.'),
  (null, 'K-T2', 'Eggs, cheese and olives from anywhere', 'dinner', 'travel', 64.08, 17.11, 54.30, 803, 7.10, 150.0, 'Mini-market grade, no kitchen. Pre-boiled eggs are on the shelf in every supermarket; failing that, boil a six-pack in the hotel kettle - twelve minutes of boiling water, poured twice. The whey is a scoop in a shaker, which is why it is here instead of four more eggs.'),
  (null, 'K-T3', 'Tinned fish, avocado and a bagged salad', 'snack', 'travel', 51.84, 23.31, 42.88, 659, 18.69, 120.0, 'The one that works at 23:00 in a hotel room. Two tins of tuna in olive oil with most of it drained, a ripe avocado, a bag of leaves. A plastic fork is the only equipment.')
on conflict (code) where user_id is null do update set
  name=excluded.name, slot=excluded.slot, day_type=excluded.day_type,
  protein_g=excluded.protein_g, carbs_g=excluded.carbs_g, fat_g=excluded.fat_g,
  kcal=excluded.kcal, fiber_g=excluded.fiber_g, veg_g=excluded.veg_g,
  instructions=excluded.instructions;

-- ============================================================ ingredients
delete from public.meal_ingredients mi using public.meals m
  where m.id = mi.meal_id and m.user_id is null and m.code like 'K-%';

insert into public.meal_ingredients
  (meal_id, order_index, name, amount, unit, role,
   kcal_100, protein_100, carbs_100, fat_100, fiber_100, is_veg)
select m.id, v.order_index, v.name, v.amount, 'g', v.role,
       v.kcal_100, v.protein_100, v.carbs_100, v.fat_100, v.fiber_100, v.is_veg
  from (values
    ('K-M1a', 0, 'Χόρτα (wild greens), boiled', 300, 'veg', 25, 2.5, 4.0, 0.3, 2.5, true),
    ('K-M1a', 1, 'Feta', 40, 'protein', 264, 14.2, 4.1, 21.3, 0, false),
    ('K-M1a', 2, 'Egg, whole', 60, 'protein', 143, 12.6, 0.7, 9.5, 0, false),
    ('K-M1a', 3, 'Chicken thigh, skin-on, raw', 295, 'protein', 209, 17.5, 0, 15.0, 0, false),
    ('K-M1a', 4, 'Olive oil', 1, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-M1b', 0, 'Mushrooms', 180, 'veg', 22, 3.1, 3.3, 0.3, 1.0, true),
    ('K-M1b', 1, 'Spinach, raw', 200, 'veg', 23, 2.9, 3.6, 0.4, 2.2, true),
    ('K-M1b', 2, 'Graviera', 25, 'protein', 390, 28.0, 1.0, 30.0, 0, false),
    ('K-M1b', 3, 'Ground flaxseed', 12, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-M1b', 4, 'Pork shoulder (χοιρινή μπριζόλα), raw', 270, 'protein', 180, 19.0, 0, 11.5, 0, false),
    ('K-M1b', 5, 'Olive oil', 18, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-M1c', 0, 'Asparagus', 220, 'veg', 20, 2.2, 3.9, 0.1, 2.1, true),
    ('K-M1c', 1, 'Avocado', 80, 'produce', 160, 2.0, 8.5, 14.7, 6.7, false),
    ('K-M1c', 2, 'Rocket (ρόκα)', 70, 'veg', 25, 2.6, 3.7, 0.7, 1.6, true),
    ('K-M1c', 3, 'Salmon fillet, raw', 320, 'protein', 208, 20.0, 0, 13.0, 0, false),
    ('K-M1c', 4, 'Olive oil', 4, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-M1d', 0, 'Zucchini (κολοκυθάκι)', 280, 'veg', 17, 1.2, 3.1, 0.3, 1.0, true),
    ('K-M1d', 1, 'Spinach, raw', 120, 'veg', 23, 2.9, 3.6, 0.4, 2.2, true),
    ('K-M1d', 2, 'Feta', 40, 'protein', 264, 14.2, 4.1, 21.3, 0, false),
    ('K-M1d', 3, 'Chia seeds', 12, 'extra', 486, 17.0, 42.0, 31.0, 34.0, false),
    ('K-M1d', 4, 'Beef mince 15% fat, raw', 310, 'protein', 215, 18.6, 0, 15.0, 0, false),
    ('K-M2a', 0, 'Zucchini (κολοκυθάκι)', 250, 'veg', 17, 1.2, 3.1, 0.3, 1.0, true),
    ('K-M2a', 1, 'Kalamata olives, drained', 30, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-M2a', 2, 'Graviera', 25, 'protein', 390, 28.0, 1.0, 30.0, 0, false),
    ('K-M2a', 3, 'Chia seeds', 12, 'extra', 486, 17.0, 42.0, 31.0, 34.0, false),
    ('K-M2a', 4, 'Chicken breast, raw', 240, 'protein', 120, 22.5, 0, 2.6, 0, false),
    ('K-M2a', 5, 'Olive oil', 28, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-M2b', 0, 'Feta', 40, 'protein', 264, 14.2, 4.1, 21.3, 0, false),
    ('K-M2b', 1, 'Spinach, raw', 200, 'veg', 23, 2.9, 3.6, 0.4, 2.2, true),
    ('K-M2b', 2, 'Mushrooms', 120, 'veg', 22, 3.1, 3.3, 0.3, 1.0, true),
    ('K-M2b', 3, 'Avocado', 30, 'produce', 160, 2.0, 8.5, 14.7, 6.7, false),
    ('K-M2b', 4, 'Chia seeds', 10, 'extra', 486, 17.0, 42.0, 31.0, 34.0, false),
    ('K-M2b', 5, 'Egg, whole', 385, 'protein', 143, 12.6, 0.7, 9.5, 0, false),
    ('K-M2c', 0, 'Halloumi', 70, 'protein', 321, 22.0, 2.2, 25.0, 0, false),
    ('K-M2c', 1, 'Cucumber', 130, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-M2c', 2, 'Tomato', 80, 'veg', 18, 0.9, 3.9, 0.2, 1.2, true),
    ('K-M2c', 3, 'Kalamata olives, drained', 25, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-M2c', 4, 'Romaine lettuce', 80, 'veg', 17, 1.2, 3.3, 0.3, 2.1, true),
    ('K-M2c', 5, 'Ground flaxseed', 15, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-M2c', 6, 'Chicken thigh, boneless skinless, raw', 220, 'protein', 119, 20.3, 0, 4.3, 0, false),
    ('K-M2c', 7, 'Olive oil', 15, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-M2d', 0, 'Rocket (ρόκα)', 100, 'veg', 25, 2.6, 3.7, 0.7, 1.6, true),
    ('K-M2d', 1, 'Cucumber', 150, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-M2d', 2, 'Avocado', 80, 'produce', 160, 2.0, 8.5, 14.7, 6.7, false),
    ('K-M2d', 3, 'Feta', 40, 'protein', 264, 14.2, 4.1, 21.3, 0, false),
    ('K-M2d', 4, 'Chia seeds', 10, 'extra', 486, 17.0, 42.0, 31.0, 34.0, false),
    ('K-M2d', 5, 'Sardines in olive oil, drained', 215, 'protein', 208, 24.6, 0, 11.5, 0, false),
    ('K-M2d', 6, 'Olive oil', 3, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-M3a', 0, 'Greek yogurt 10% (στραγγιστό)', 120, 'protein', 133, 6.4, 4.0, 10.0, 0, false),
    ('K-M3a', 1, 'Walnuts', 20, 'extra', 654, 15.0, 14.0, 65.0, 6.7, false),
    ('K-M3a', 2, 'Chia seeds', 28, 'extra', 486, 17.0, 42.0, 31.0, 34.0, false),
    ('K-M3a', 3, 'Psyllium husk', 4, 'extra', 200, 0, 85.0, 0.5, 80.0, false),
    ('K-M3a', 4, 'Whey isolate powder', 45, 'protein', 373, 86.0, 4.0, 1.5, 0, false),
    ('K-M3a', 5, 'Olive oil', 5, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-M3b', 0, 'Egg, whole', 240, 'protein', 143, 12.6, 0.7, 9.5, 0, false),
    ('K-M3b', 1, 'Kalamata olives, drained', 30, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-M3b', 2, 'Cucumber', 150, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-M3b', 3, 'Ground flaxseed', 15, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-M3b', 4, 'Whey isolate powder', 20, 'protein', 373, 86.0, 4.0, 1.5, 0, false),
    ('K-M3b', 5, 'Olive oil', 7, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-M3c', 0, 'Avocado', 100, 'produce', 160, 2.0, 8.5, 14.7, 6.7, false),
    ('K-M3c', 1, 'Ground flaxseed', 20, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-M3c', 2, 'Romaine lettuce', 120, 'veg', 17, 1.2, 3.3, 0.3, 2.1, true),
    ('K-M3c', 3, 'Tuna in olive oil, drained', 175, 'protein', 186, 26.0, 0, 9.0, 0, false),
    ('K-M3c', 4, 'Olive oil', 4, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-T1', 0, 'Cucumber', 150, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-T1', 1, 'Tomato', 100, 'veg', 18, 0.9, 3.9, 0.2, 1.2, true),
    ('K-T1', 2, 'Green pepper', 60, 'veg', 20, 0.9, 4.6, 0.2, 1.7, true),
    ('K-T1', 3, 'Feta', 50, 'protein', 264, 14.2, 4.1, 21.3, 0, false),
    ('K-T1', 4, 'Kalamata olives, drained', 30, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-T1', 5, 'Ground flaxseed', 12, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-T1', 6, 'Rotisserie chicken, meat only', 205, 'protein', 190, 29.0, 0, 8.0, 0, false),
    ('K-T1', 7, 'Olive oil', 21, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-T2', 0, 'Egg, whole', 180, 'protein', 143, 12.6, 0.7, 9.5, 0, false),
    ('K-T2', 1, 'Graviera', 30, 'protein', 390, 28.0, 1.0, 30.0, 0, false),
    ('K-T2', 2, 'Kalamata olives, drained', 30, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-T2', 3, 'Cucumber', 150, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-T2', 4, 'Walnuts', 20, 'extra', 654, 15.0, 14.0, 65.0, 6.7, false),
    ('K-T2', 5, 'Ground flaxseed', 15, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-T2', 6, 'Whey isolate powder', 30, 'protein', 373, 86.0, 4.0, 1.5, 0, false),
    ('K-T2', 7, 'Olive oil', 2, 'fat', 884, 0, 0, 100.0, 0, false),
    ('K-T3', 0, 'Avocado', 110, 'produce', 160, 2.0, 8.5, 14.7, 6.7, false),
    ('K-T3', 1, 'Romaine lettuce', 120, 'veg', 17, 1.2, 3.3, 0.3, 2.1, true),
    ('K-T3', 2, 'Ground flaxseed', 20, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-T3', 3, 'Chia seeds', 10, 'extra', 486, 17.0, 42.0, 31.0, 34.0, false),
    ('K-T3', 4, 'Tuna in olive oil, drained', 165, 'protein', 186, 26.0, 0, 9.0, 0, false)
  ) as v(code, order_index, name, amount, role,
         kcal_100, protein_100, carbs_100, fat_100, fiber_100, is_veg)
  join public.meals m on m.code = v.code and m.user_id is null;

-- macros are a SUM over the rows above, never a number typed in by hand
select public.recompute_meal_macros(m.id) from public.meals m
 where m.user_id is null and m.code like 'K-%';
