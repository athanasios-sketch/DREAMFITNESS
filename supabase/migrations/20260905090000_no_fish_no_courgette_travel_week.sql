-- No fish, no courgette, and a week that is mostly spent away from the kitchen.
--
-- Three changes arrive together because they are the same change: the rotation
-- was built around plates he will not eat and a travel day he was told was rare.
--
-- 1. FISH IS OUT. Four plates were built on it - salmon, sardines and two tins
--    of tuna - and they are rebuilt on poultry, eggs and yogurt, which is what
--    he asked for and what a supermarket in a strange town actually sells.
--    This costs something real and it is worth naming: fish was the only source
--    of EPA and DHA on the plan. Flaxseed and walnuts carry ALA, of which the
--    body converts perhaps 5% - so an omega-3 supplement is added below rather
--    than pretending the loss did not happen.
--
-- 2. COURGETTE IS OUT ENTIRELY, χόρτα is cut from 300 g to 200 g on the plate
--    it dominated, and spinach and mushrooms carry the volume instead. Every
--    vegetable on this rotation is now raw, wilted, or in the airfryer - the
--    boiled χόρτα is the single exception and it survives on merit: 200 g is
--    potassium, folate and 5 g of fibre for 30 kcal, and nothing else in a
--    Greek supermarket does that.
--
-- 3. TRAVEL IS THE WEEK, NOT THE EXCEPTION. Monday to Friday away means the
--    supermarket menu is now five days in seven, so it stops being a single
--    fallback plate and becomes a rotation: a hotel breakfast, two lunches,
--    two dinners, and a top-up that only appears on days he trains. And on a
--    travel day the eating window is off - there is a buffet at 08:00 and no
--    honest reason to walk past it. 16:8 was adherence scaffolding, never the
--    mechanism; the deficit and the protein are the mechanism, and both hold.
--
-- Every plate was re-solved, not nudged: fix the vegetables and the
-- accessories, then solve the protein source and the olive oil for the
-- calorie and protein target exactly. The generator and the arithmetic live in
-- data/keto_rotation_v2.py - the numbers below are its output.
--
-- All thirteen day-combinations the template can produce were checked: every
-- one lands 2018-2367 kcal, 190-205 g protein, 18.9-27.7 g NET carbohydrate
-- against a 28 g cap, 26-34 g fibre, and 430-850 g of vegetables.

-- ============================================================ the meals
insert into public.meals
  (user_id, code, name, slot, day_type, protein_g, carbs_g, fat_g, kcal,
   fiber_g, veg_g, instructions)
values
  (null, 'K-M1a', 'Airfryer chicken thighs, χόρτα, σπανάκι and feta', 'lunch', 'regular', 72.03, 15.95, 60.10, 887, 8.24, 380.0, 'Airfryer 200C, 22-25 min, skin side up. No oil in the basket - the thigh renders its own. Χόρτα boiled and drained hard: a side now rather than the whole plate. Spinach and mushrooms go in the pan with the fat that came off the chicken, sixty seconds for the spinach and no more. Feta and the egg on the side, far more lemon than feels right.'),
  (null, 'K-M1c', 'Airfryer turkey fillet with mushrooms, spinach and avocado', 'lunch', 'regular', 72.32, 18.36, 62.78, 887, 10.18, 280.0, 'Airfryer 190C, 16-18 min - turkey is leaner than chicken breast and goes to sawdust past that, so pull it early and rest it. Mushrooms in the basket alongside. Spinach, rocket and avocado raw underneath, walnuts over, oil and lemon. Turkey brings almost no fat of its own, so on this plate the oil is not a dressing, it is the meal: two and a bit tablespoons, measured, or the day comes in 300 kcal light.'),
  (null, 'K-M1d', 'Beef mince, mushroom and spinach pan, feta on top', 'lunch', 'regular', 72.33, 17.12, 62.26, 907, 8.54, 350.0, 'Pan, high heat. Brown the mince hard and do not stir it too early or it steams. Mushrooms in next - they want the fat that came out of the mince, and they will take all of it. Spinach wilted in at the end, feta crumbled over off the heat, flaxseed stirred through.'),
  (null, 'K-M2a', 'Airfryer chicken breast, peppers, mushrooms and olives', 'dinner', 'regular', 66.83, 14.78, 53.42, 802, 7.24, 250.0, 'Airfryer 190C, 16-18 min - breast goes dry past that. Peppers and mushrooms in the basket alongside; mushrooms shrink to nothing, so pile them in. Olives, grated graviera and the flaxseed over the top.'),
  (null, 'K-M2d', 'Chicken thigh with yogurt-cucumber sauce and rocket', 'dinner', 'regular', 65.76, 17.11, 54.63, 804, 6.36, 250.0, 'Pan or airfryer, 200C, 15-18 min. Half the cucumber grated into the yogurt with garlic, dill and salt - tzatziki without the shop version''s sugar. The other half sliced into the salad with the rocket, tomato and olives, flaxseed over. Keep the sauce on the side or the salad goes to soup.'),
  (null, 'K-M3c', 'Cold chicken, avocado and leaves', 'snack', 'regular', 52.04, 18.26, 41.66, 642, 14.62, 120.0, 'Nothing to cook if you plan it: this is the extra breast you put in the airfryer at lunch, kept in the fridge. Two minutes, one bowl. It is the lowest-carbohydrate plate in the rotation, which is why it turns up on the days the other two meals are expensive.'),
  (null, 'K-R1', 'Airfryer chicken breast, χόρτα and mushrooms', 'lunch', 'regular', 72.33, 17.52, 48.15, 781, 10.70, 380.0, 'Airfryer 190C, 16-18 min. Χόρτα boiled and drained hard, mushrooms in the basket alongside the chicken, spinach wilted into them at the end. The olive oil is measured, not poured - on a rest day it is most of what separates this plate from the training-day version.'),
  (null, 'K-T0', 'Hotel breakfast — eggs, yogurt, cheese and olives', 'breakfast', 'travel', 54.70, 16.01, 45.95, 694, 8.69, 0.0, 'The buffet, read correctly. Three or four eggs - boiled, or an omelette from the station if there is one. Yogurt plain, never the fruit ones. A slice of hard yellow cheese, olives, cucumber, a few walnuts. What you walk past: bread, croissants, cereal, juice, honey, jam, fruit, and the milk in the coffee if it is more than a splash. If the eggs are missing, the whey in the shaker covers the protein and you take double cheese. Tomato and cucumber off the buffet are welcome and are not counted here - a plateful costs about 2 g of net carbohydrate, which this day has room for. The flaxseed and psyllium go into the yogurt and are the reason a five-day week away does not end in a fibre drought; drink a full glass of water with them or they do the opposite. Nothing here needs a kitchen or a scale - the grams are the shape of the plate, not a rule.'),
  (null, 'K-T1', 'Rotisserie chicken and a village salad', 'lunch', 'travel', 72.12, 17.52, 48.39, 783, 8.31, 270.0, 'Supermarket or ψητοπωλείο, any town, all day, about seven euros. Half a κοτόπουλο σούβλας with the meat off the bone - skin on is fine, that is where the fat is. Build the salad in the tub the deli hands you. Oil from a sachet, or carry the smallest bottle in the bag. No pita, no potatoes, no bread to mop the plate.'),
  (null, 'K-T4', 'Σουβλάκι off the skewer, no pita, with a salad', 'lunch', 'travel', 72.20, 16.67, 49.53, 782, 8.49, 260.0, 'Three or four καλαμάκια κοτόπουλο or χοιρινό, asked for σε μερίδα - off the skewer, on the plate, no pita and no potatoes. Every grill in Greece does this and nobody blinks. Salad on the side: μαρούλι or χωριάτικη, oil and vinegar poured by you. Tzatziki yes, ketchup and mustard no. The grams are what four skewers weigh; you are not weighing them.'),
  (null, 'K-T2', 'Eggs, cheese and olives from anywhere', 'dinner', 'travel', 63.02, 17.73, 25.68, 541, 10.70, 160.0, 'Mini-market grade, no kitchen. Pre-boiled eggs are on the shelf in every supermarket; failing that, boil a six-pack in the hotel kettle - twelve minutes of boiling water, poured twice. The whey is a scoop in a shaker, which is why it is here instead of four more eggs.'),
  (null, 'K-T6', 'Taverna — grilled meat and χωριάτικη, nothing else', 'dinner', 'travel', 63.23, 17.23, 24.64, 541, 8.92, 260.0, 'The order that works in any taverna: μπριζόλα, μπιφτέκι or κοτόπουλο σχάρας, plus a χωριάτικη, and that is the whole order. Say no to the πατάτες before they arrive - they come by default and eating half of them is the difference between this day working and not. Bread stays in the basket. If the meat comes with a lemon-oil dressing, that is fat you are already counting.'),
  (null, 'K-T3', 'Cheese, walnuts and olives — the training-day top-up', 'snack', 'travel', 14.50, 4.40, 29.20, 331, 1.98, 0.0, 'Only on the days you actually train. A travel day that ends in a hotel room after a session is about 325 kcal short of what it cost you, and this is the difference: a wedge of hard cheese, a handful of walnuts, the olives left over from lunch. Nothing needs a fridge, and all three keep in a bag for a week. On a rest day away it is not on the plan at all - and that is deliberate, not an oversight.')
on conflict (code) where user_id is null do update set
  name=excluded.name, slot=excluded.slot, day_type=excluded.day_type,
  protein_g=excluded.protein_g, carbs_g=excluded.carbs_g, fat_g=excluded.fat_g,
  kcal=excluded.kcal, fiber_g=excluded.fiber_g, veg_g=excluded.veg_g,
  instructions=excluded.instructions;

-- The new travel plates are keto rows like the rest of the K- library. Without
-- this they carry a null diet_modes, which the read policy treats as "shared by
-- everyone" - and Thanos would find a hotel breakfast in his swap list.
update public.meals set diet_modes = array['keto']
 where user_id is null and code like 'K-%' and diet_modes is distinct from array['keto'];

-- ============================================================ ingredients
delete from public.meal_ingredients mi using public.meals m
  where m.id = mi.meal_id and m.user_id is null
    and m.code in ('K-M1a','K-M1c','K-M1d','K-M2a','K-M2d','K-M3c','K-R1',
                   'K-T0','K-T1','K-T2','K-T3','K-T4','K-T6');

insert into public.meal_ingredients
  (meal_id, order_index, name, amount, unit, role,
   kcal_100, protein_100, carbs_100, fat_100, fiber_100, is_veg)
select m.id, v.order_index, v.name, v.amount, 'g', v.role,
       v.kcal_100, v.protein_100, v.carbs_100, v.fat_100, v.fiber_100, v.is_veg
  from (values
    ('K-M1a', 0, 'Χόρτα (wild greens), boiled', 200, 'veg', 25, 2.5, 4.0, 0.3, 2.5, true),
    ('K-M1a', 1, 'Spinach, raw', 120, 'veg', 23, 2.9, 3.6, 0.4, 2.2, true),
    ('K-M1a', 2, 'Mushrooms', 60, 'veg', 22, 3.1, 3.3, 0.3, 1.0, true),
    ('K-M1a', 3, 'Feta', 30, 'protein', 264, 14.2, 4.1, 21.3, 0.0, false),
    ('K-M1a', 4, 'Egg, whole', 60, 'protein', 143, 12.6, 0.7, 9.5, 0.0, false),
    ('K-M1a', 5, 'Chicken thigh, skin-on, raw', 285, 'protein', 209, 17.5, 0.0, 15.0, 0.0, false),
    ('K-M1a', 6, 'Olive oil', 4, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-M1c', 0, 'Mushrooms', 120, 'veg', 22, 3.1, 3.3, 0.3, 1.0, true),
    ('K-M1c', 1, 'Spinach, raw', 120, 'veg', 23, 2.9, 3.6, 0.4, 2.2, true),
    ('K-M1c', 2, 'Rocket (ρόκα)', 40, 'veg', 25, 2.6, 3.7, 0.7, 1.6, true),
    ('K-M1c', 3, 'Avocado', 60, 'produce', 160, 2.0, 8.5, 14.7, 6.7, false),
    ('K-M1c', 4, 'Walnuts', 25, 'extra', 654, 15.0, 14.0, 65.0, 6.7, false),
    ('K-M1c', 5, 'Turkey breast, raw', 270, 'protein', 104, 21.9, 0.0, 1.7, 0.0, false),
    ('K-M1c', 6, 'Olive oil', 32, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-M1d', 0, 'Mushrooms', 200, 'veg', 22, 3.1, 3.3, 0.3, 1.0, true),
    ('K-M1d', 1, 'Spinach, raw', 150, 'veg', 23, 2.9, 3.6, 0.4, 2.2, true),
    ('K-M1d', 2, 'Feta', 40, 'protein', 264, 14.2, 4.1, 21.3, 0.0, false),
    ('K-M1d', 3, 'Ground flaxseed', 12, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-M1d', 4, 'Beef mince 15% fat, raw', 290, 'protein', 215, 18.6, 0.0, 15.0, 0.0, false),
    ('K-M1d', 5, 'Olive oil', 4, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-M2a', 0, 'Green pepper', 100, 'veg', 20, 0.9, 4.6, 0.2, 1.7, true),
    ('K-M2a', 1, 'Mushrooms', 150, 'veg', 22, 3.1, 3.3, 0.3, 1.0, true),
    ('K-M2a', 2, 'Kalamata olives, drained', 25, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-M2a', 3, 'Graviera', 25, 'protein', 390, 28.0, 1.0, 30.0, 0.0, false),
    ('K-M2a', 4, 'Ground flaxseed', 12, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-M2a', 5, 'Chicken breast, raw', 230, 'protein', 120, 22.5, 0.0, 2.6, 0.0, false),
    ('K-M2a', 6, 'Olive oil', 29, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-M2d', 0, 'Greek yogurt 10% (στραγγιστό)', 80, 'protein', 133, 6.4, 4.0, 10.0, 0.0, false),
    ('K-M2d', 1, 'Cucumber', 120, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-M2d', 2, 'Rocket (ρόκα)', 80, 'veg', 25, 2.6, 3.7, 0.7, 1.6, true),
    ('K-M2d', 3, 'Tomato', 50, 'veg', 18, 0.9, 3.9, 0.2, 1.2, true),
    ('K-M2d', 4, 'Kalamata olives, drained', 20, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-M2d', 5, 'Ground flaxseed', 12, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-M2d', 6, 'Chicken thigh, boneless skinless, raw', 270, 'protein', 119, 20.3, 0.0, 4.3, 0.0, false),
    ('K-M2d', 7, 'Olive oil', 25, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-M3c', 0, 'Avocado', 100, 'produce', 160, 2.0, 8.5, 14.7, 6.7, false),
    ('K-M3c', 1, 'Romaine lettuce', 120, 'veg', 17, 1.2, 3.3, 0.3, 2.1, true),
    ('K-M3c', 2, 'Ground flaxseed', 20, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-M3c', 3, 'Chicken breast, raw', 200, 'protein', 120, 22.5, 0.0, 2.6, 0.0, false),
    ('K-M3c', 4, 'Olive oil', 13, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-R1', 0, 'Χόρτα (wild greens), boiled', 180, 'veg', 25, 2.5, 4.0, 0.3, 2.5, true),
    ('K-R1', 1, 'Mushrooms', 120, 'veg', 22, 3.1, 3.3, 0.3, 1.0, true),
    ('K-R1', 2, 'Spinach, raw', 80, 'veg', 23, 2.9, 3.6, 0.4, 2.2, true),
    ('K-R1', 3, 'Ground flaxseed', 12, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-R1', 4, 'Chicken breast, raw', 265, 'protein', 120, 22.5, 0.0, 2.6, 0.0, false),
    ('K-R1', 5, 'Olive oil', 35, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-T0', 0, 'Greek yogurt 10% (στραγγιστό)', 100, 'protein', 133, 6.4, 4.0, 10.0, 0.0, false),
    ('K-T0', 1, 'Graviera', 30, 'protein', 390, 28.0, 1.0, 30.0, 0.0, false),
    ('K-T0', 2, 'Kalamata olives, drained', 20, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-T0', 3, 'Ground flaxseed', 15, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-T0', 4, 'Psyllium husk', 5, 'extra', 200, 0.0, 85.0, 0.5, 80.0, false),
    ('K-T0', 5, 'Egg, whole', 170, 'protein', 143, 12.6, 0.7, 9.5, 0.0, false),
    ('K-T0', 6, 'Whey isolate powder', 18, 'protein', 373, 86.0, 4.0, 1.5, 0.0, false),
    ('K-T1', 0, 'Romaine lettuce', 80, 'veg', 17, 1.2, 3.3, 0.3, 2.1, true),
    ('K-T1', 1, 'Cucumber', 100, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-T1', 2, 'Tomato', 50, 'veg', 18, 0.9, 3.9, 0.2, 1.2, true),
    ('K-T1', 3, 'Green pepper', 40, 'veg', 20, 0.9, 4.6, 0.2, 1.7, true),
    ('K-T1', 4, 'Feta', 40, 'protein', 264, 14.2, 4.1, 21.3, 0.0, false),
    ('K-T1', 5, 'Kalamata olives, drained', 25, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-T1', 6, 'Ground flaxseed', 15, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-T1', 7, 'Rotisserie chicken, meat only', 210, 'protein', 190, 29.0, 0.0, 8.0, 0.0, false),
    ('K-T1', 8, 'Olive oil', 11, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-T4', 0, 'Romaine lettuce', 120, 'veg', 17, 1.2, 3.3, 0.3, 2.1, true),
    ('K-T4', 1, 'Cucumber', 80, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-T4', 2, 'Tomato', 60, 'veg', 18, 0.9, 3.9, 0.2, 1.2, true),
    ('K-T4', 3, 'Feta', 40, 'protein', 264, 14.2, 4.1, 21.3, 0.0, false),
    ('K-T4', 4, 'Kalamata olives, drained', 25, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-T4', 5, 'Ground flaxseed', 15, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-T4', 6, 'Chicken thigh, boneless skinless, raw', 300, 'protein', 119, 20.3, 0.0, 4.3, 0.0, false),
    ('K-T4', 7, 'Olive oil', 16, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-T2', 0, 'Graviera', 25, 'protein', 390, 28.0, 1.0, 30.0, 0.0, false),
    ('K-T2', 1, 'Kalamata olives, drained', 25, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-T2', 2, 'Cucumber', 60, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-T2', 3, 'Romaine lettuce', 100, 'veg', 17, 1.2, 3.3, 0.3, 2.1, true),
    ('K-T2', 4, 'Ground flaxseed', 10, 'extra', 534, 18.0, 29.0, 42.0, 27.0, false),
    ('K-T2', 5, 'Psyllium husk', 6, 'extra', 200, 0.0, 85.0, 0.5, 80.0, false),
    ('K-T2', 6, 'Egg, whole', 80, 'protein', 143, 12.6, 0.7, 9.5, 0.0, false),
    ('K-T2', 7, 'Whey isolate powder', 49, 'protein', 373, 86.0, 4.0, 1.5, 0.0, false),
    ('K-T6', 0, 'Cucumber', 80, 'veg', 15, 0.7, 3.6, 0.1, 0.5, true),
    ('K-T6', 1, 'Tomato', 60, 'veg', 18, 0.9, 3.9, 0.2, 1.2, true),
    ('K-T6', 2, 'Green pepper', 40, 'veg', 20, 0.9, 4.6, 0.2, 1.7, true),
    ('K-T6', 3, 'Feta', 30, 'protein', 264, 14.2, 4.1, 21.3, 0.0, false),
    ('K-T6', 4, 'Kalamata olives, drained', 20, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false),
    ('K-T6', 5, 'Romaine lettuce', 80, 'veg', 17, 1.2, 3.3, 0.3, 2.1, true),
    ('K-T6', 6, 'Psyllium husk', 6, 'extra', 200, 0.0, 85.0, 0.5, 80.0, false),
    ('K-T6', 7, 'Chicken breast, raw', 250, 'protein', 120, 22.5, 0.0, 2.6, 0.0, false),
    ('K-T6', 8, 'Olive oil', 7, 'fat', 884, 0.0, 0.0, 100.0, 0.0, false),
    ('K-T3', 0, 'Graviera', 40, 'protein', 390, 28.0, 1.0, 30.0, 0.0, false),
    ('K-T3', 1, 'Walnuts', 20, 'extra', 654, 15.0, 14.0, 65.0, 6.7, false),
    ('K-T3', 2, 'Kalamata olives, drained', 20, 'produce', 220, 1.5, 6.0, 21.0, 3.2, false)
  ) as v(code, order_index, name, amount, role,
         kcal_100, protein_100, carbs_100, fat_100, fiber_100, is_veg)
  join public.meals m on m.code = v.code and m.user_id is null;

-- macros are a SUM over the rows above, never a number typed in by hand
select public.recompute_meal_macros(m.id) from public.meals m
 where m.user_id is null and m.code like 'K-%';

-- ============================================== what leaves with the fish
-- Salmon, sardines and two tins of tuna were carrying something no chicken
-- thigh replaces. Iodine and selenium survive elsewhere on this plan - dairy,
-- eggs, walnuts and the iodised salt he is told to use heavily - but EPA and
-- DHA do not. This is the one nutrient the rebuild genuinely costs him, so it
-- gets bought back rather than quietly dropped.
insert into public.supplements
  (user_id, code, kind, name, dose, timing, why, notes, sort_order, diet_modes, day_types)
values
  (null, 'OMEGA3', 'supplement', 'EPA + DHA (fish oil or algae)',
   '1.5-2 g of combined EPA+DHA a day - read the back of the tub, not the front',
   'With the first meal. It is fat-soluble and it oxidises, so with food and out of the sun.',
   'This is here because the rotation stopped containing fish. Oily fish was the plan''s only source of EPA and DHA; flaxseed, chia and walnuts supply ALA, of which the body converts something like 5% to EPA and almost none to DHA, so "there is flaxseed in it" does not cover the gap. In a long deficit with heavy training, EPA and DHA are doing the work that matters here - blunting the inflammatory side of hard sessions, and there is reasonable evidence they help hold lean mass when calories are low.',
   array[
     'The number on the front of the bottle is fish oil. The number that counts is EPA + DHA on the back - 1000 mg of fish oil is often 300 mg of the thing you are buying.',
     'Algae oil is the same molecule from where the fish got it, and is the answer if fish in any form is off the table.',
     'Keep it in the fridge. If a capsule tastes of fish when you bite it, the batch has oxidised and it is doing nothing for you.'], 8,
   array['keto'], null)
on conflict (code) where user_id is null do update set
  kind=excluded.kind, name=excluded.name, dose=excluded.dose, timing=excluded.timing,
  why=excluded.why, notes=excluded.notes, sort_order=excluded.sort_order,
  diet_modes=excluded.diet_modes, day_types=excluded.day_types, active=true;

-- Salt was already the headline habit; with the fish gone it is also where the
-- iodine comes from, and that is worth one sentence rather than a new pill.
update public.supplements set notes = array[
  'Salt food far past what feels correct. The advice to go easy on salt is written for people eating processed carbohydrate, and he is about to eat none.',
  'Use IODISED salt (ιωδιούχο αλάτι). With fish off the plan, salt and dairy are where iodine now comes from, and on a diet this low in processed food it is easy to end up short of it without noticing.',
  'Potassium comes from the food, not a pill: chorta, spinach, mushrooms and avocado are in this rotation partly for that reason. Potassium supplements are capped at trivial doses in the EU anyway.',
  'Magnesium citrate or glycinate at night - it helps the sleep and it answers the constipation that a fibre-light fortnight can cause. Oxide is cheap and poorly absorbed.',
  'If a session ever feels inexplicably flat, the first thing to check is salt, not calories.']
 where user_id is null and code = 'ELECTRO';

-- ============================================================ travel days
-- Travel used to be "once a week and never on a predictable weekday", so it was
-- applied by hand to whichever day it landed on. It is actually Monday to
-- Friday, most weeks - so it belongs in the profile as a default the generator
-- reads, with the hand-applied override kept for the weeks that differ.
alter table public.profiles
  add column if not exists travel_weekdays smallint[] not null default '{}'::smallint[];

comment on column public.profiles.travel_weekdays is
  'ISO weekdays (1=Mon..7=Sun) that are travel days by default. The generator
   lays them out; set_travel_days() overrides individual dates on top, so a week
   that is different is a few taps rather than a regenerated plan.';

-- Which plates a travel day serves. Two lunches and two dinners alternating by
-- weekday, so a five-day week away is not the same plate five times; the
-- training-day top-up is appended only when the day has a session to pay for
-- it. Breakfast is on EVERY travel day - the eating window does not survive a
-- hotel buffet, and there is no reason it should.
create or replace function public.travel_meal_codes(p_date date, p_rest boolean)
returns text[] language sql immutable set search_path = '' as $$
  select case when p_rest
    then array['K-T0', lunch, dinner]
    else array['K-T0', lunch, dinner, 'K-T3'] end
  from (select case when extract(isodow from p_date)::int % 2 = 1 then 'K-T1' else 'K-T4' end as lunch,
               case when extract(isodow from p_date)::int % 2 = 1 then 'K-T2' else 'K-T6' end as dinner) s;
$$;
grant execute on function public.travel_meal_codes(date, boolean) to authenticated;

comment on function public.travel_meal_codes(date, boolean) is
  'The travel menu for a date. Rest days get three meals and no top-up: a day
   away with no session is budgeted ~325 kcal lower, and serving it the training
   menu is the same 322 kcal-a-day mistake migration 20260903150000 caught on
   rest days at home.';

-- Applying travel to a range of dates, because it arrives as a trip and not as
-- a day. The old single-date function stays as the one-tap case, and both go
-- through the same body - including the two bugs it had:
--
--   * turning travel OFF restored day_type = 'regular' unconditionally, which
--     would have quietly converted one of Thanos's νηστεία days into a fed one.
--     The template knows what the day was; ask it.
--   * the meal codes are keto-only, and RLS means a balanced account resolves
--     none of them - so the old function deleted the day's meals and inserted
--     nothing. A button that empties your day is worse than one that does not
--     work. Now the food stays and only the flag moves.
create or replace function public.set_travel_days(p_dates date[], p_travel boolean default true)
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
  v_tpl  bigint;
  v_date date; v_pd bigint; v_rest boolean; v_codes text[]; v_type text;
  v_dow int; v_variant smallint; v_found int; v_n integer := 0;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if p_dates is null or cardinality(p_dates) = 0 then return 0; end if;

  select t.id into v_tpl from public.program_templates t
   where t.user_id = v_user and t.active order by t.id desc limit 1;

  foreach v_date in array p_dates loop
    select pd.id, coalesce(e.category, 'rest') = 'rest'
      into v_pd, v_rest
      from public.program_days pd
      left join public.exercises e on e.id = pd.exercise_id
     where pd.user_id = v_user and pd.day_date = v_date;
    if v_pd is null then continue; end if;   -- outside the plan: nothing to flag

    v_dow     := extract(isodow from v_date);
    v_variant := (to_char(v_date, 'IW')::int % 2)::smallint;

    if p_travel then
      v_codes := public.travel_meal_codes(v_date, v_rest);
      v_type  := 'travel';
    else
      select meal_codes, day_type into v_codes, v_type
        from public.program_template_days
       where template_id = v_tpl and dow = v_dow
       order by (variant = v_variant) desc, variant limit 1;
      if v_codes is null then
        raise exception 'template % has no row for weekday %', v_tpl, v_dow;
      end if;
    end if;

    select count(*) into v_found from public.meals m
     where m.user_id is null and m.code = any(v_codes);

    if v_found = cardinality(v_codes) then
      delete from public.program_day_meals where program_day_id = v_pd;
      insert into public.program_day_meals (user_id, program_day_id, meal_id, slot_index)
      select v_user, v_pd, m.id, c.ord
        from unnest(v_codes) with ordinality as c(code, ord)
        join public.meals m on m.code = c.code and m.user_id is null;
    end if;

    update public.program_days set day_type = v_type where id = v_pd;
    v_n := v_n + 1;
  end loop;

  -- one re-pricing pass for the whole trip rather than one per day
  perform public.plan_targets_user(v_user, (select min(d) from unnest(p_dates) d));
  return v_n;
end $$;
grant execute on function public.set_travel_days(date[], boolean) to authenticated;

create or replace function public.set_travel_day(p_date date, p_travel boolean default true)
returns integer language sql security invoker set search_path = '' as $$
  select public.set_travel_days(array[p_date], p_travel);
$$;
grant execute on function public.set_travel_day(date, boolean) to authenticated;

-- ==================================================== the generator, with trips
-- Unchanged from migration 20260903100000 except for the travel branch: a
-- weekday listed in profiles.travel_weekdays is laid out as a travel day from
-- the start, so the default week is already right and only the exceptions need
-- touching. Everything else - variants, the template, plan_targets - is as it was.
create or replace function public.generate_program_user(
  p_user  uuid,
  p_start date    default null,
  p_days  integer default null
) returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_prof  public.profiles%rowtype;
  v_tpl   bigint;
  v_start date;
  v_days  integer;
  v_day   integer; v_date date; v_dow integer; v_variant smallint;
  r       record;
  v_pd    bigint;
  v_ex    bigint;
  v_codes text[]; v_type text; v_rest boolean; v_found int;
  v_p numeric; v_c numeric; v_f numeric; v_k integer; v_n integer := 0;
begin
  if p_user is null then raise exception 'no user'; end if;
  select * into v_prof from public.profiles where id = p_user;
  if not found then raise exception 'no profile for %', p_user; end if;

  select id into v_tpl from public.program_templates
   where user_id = p_user and active order by id desc limit 1;
  if v_tpl is null then raise exception 'no active program template for %', p_user; end if;

  v_start := coalesce(p_start, v_prof.program_start_date);
  v_days  := coalesce(p_days, v_prof.program_days, 90);

  delete from public.program_days where user_id = p_user;

  for v_day in 1..v_days loop
    v_date    := v_start + (v_day - 1);
    v_dow     := extract(isodow from v_date);
    v_variant := (to_char(v_date, 'IW')::int % 2)::smallint;

    select * into r from public.program_template_days
     where template_id = v_tpl and dow = v_dow
     order by (variant = v_variant) desc, variant
     limit 1;
    if not found then
      raise exception 'template % has no row for weekday %', v_tpl, v_dow;
    end if;

    select id into v_ex from public.exercises
     where code = r.exercise_code and user_id is null;

    v_codes := r.meal_codes;
    v_type  := r.day_type;

    if v_dow = any(coalesce(v_prof.travel_weekdays, '{}'::smallint[])) then
      v_rest := coalesce((select e.category from public.exercises e where e.id = v_ex), 'rest') = 'rest';
      select count(*) into v_found from public.meals m
       where m.user_id is null and m.code = any(public.travel_meal_codes(v_date, v_rest));
      -- a diet with no travel library keeps its own food and is only flagged
      v_type := 'travel';
      if v_found = cardinality(public.travel_meal_codes(v_date, v_rest)) then
        v_codes := public.travel_meal_codes(v_date, v_rest);
      end if;
    end if;

    select sum(m.protein_g), sum(m.carbs_g), sum(m.fat_g), sum(m.kcal)
      into v_p, v_c, v_f, v_k
      from unnest(v_codes) as c(code)
      join public.meals m on m.code = c.code and m.user_id is null;

    if v_k is null then
      raise exception 'template % weekday % references unknown meal codes %',
        v_tpl, v_dow, v_codes;
    end if;

    insert into public.program_days
      (user_id, day_no, day_date, day_type, exercise_id,
       steps_target, water_target_l,
       protein_target_g, carbs_target_g, fat_target_g, kcal_target, menu_kcal)
    values
      (p_user, v_day, v_date, v_type, v_ex,
       v_prof.steps_target, v_prof.water_target_l,
       v_p, v_c, v_f, v_k, v_k)
    returning id into v_pd;

    insert into public.program_day_meals (user_id, program_day_id, meal_id, slot_index)
    select p_user, v_pd, m.id, c.ord
      from unnest(v_codes) with ordinality as c(code, ord)
      join public.meals m on m.code = c.code and m.user_id is null;

    v_n := v_n + 1;
  end loop;

  perform public.plan_targets_user(p_user, null);
  return v_n;
end $$;
grant execute on function public.generate_program_user(uuid, date, integer) to authenticated;

-- ============================================== Ntinos: Monday start, week away
-- The plan was generated from Friday 4 September because that was the next day
-- when it was written. A 180-day block that starts mid-week has its rest days
-- landing on the wrong side of every weekend, and week 1 is four days long.
-- Monday 7 September is the honest start, and nothing has been logged against
-- the two days being thrown away.
update public.profiles
   set program_start_date = date '2026-09-07',
       travel_weekdays    = array[1,2,3,4,5]::smallint[]
 where email = 'ntinos@dreamfitness.local';

do $$
declare u uuid;
begin
  select id into u from public.profiles where email = 'ntinos@dreamfitness.local';
  if u is not null then
    perform public.generate_program_user(u, null, null);
  end if;
end $$;
