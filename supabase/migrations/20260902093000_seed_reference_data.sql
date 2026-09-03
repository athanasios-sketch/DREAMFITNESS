-- DREAMFITNESS :: system reference data (user_id null = global, readable by all)
-- Generated from data/generate_program.py -- do not hand-edit.

insert into public.meals (user_id, code, name, slot, day_type, version,
                          protein_g, carbs_g, fat_g, kcal, ingredients, instructions) values
  (null, 'B1', 'Classic Oats & Eggs', 'breakfast', 'regular', 1, 45, 45, 18, 520, '3 whole eggs, 150g egg whites, 60g oats', 'Whisk eggs & whites in an oven-safe bowl. Airfry 180C/8min. Microwave oats with water/cinnamon.'),
  (null, 'B2', 'Greek Yogurt Bowl', 'breakfast', 'regular', 1, 45, 40, 15, 475, '250g Greek yogurt 2%, 1 scoop whey, 1 banana, 20g almonds', 'Mix whey into yogurt. Top with sliced banana and crushed almonds.'),
  (null, 'L1', 'Airfryer Chicken & Rice', 'lunch', 'regular', 1, 55, 60, 15, 595, '220g chicken breast, 220g boiled basmati, 15g olive oil', 'Marinate chicken (paprika/oregano). Airfry 195C/18min. Boil rice.'),
  (null, 'L2', 'Turkey & Sweet Potato', 'lunch', 'regular', 1, 52, 60, 15, 583, '220g turkey breast, 300g sweet potato cubes, 15g olive oil', 'Airfry turkey 185C/16min. Sweet potatoes 200C/20min.'),
  (null, 'S1', 'Whey & Fruit', 'snack', 'regular', 1, 35, 30, 3, 280, '1 scoop whey protein, 1 medium apple or banana, water', 'Shake whey with water. Eat fruit on the side.'),
  (null, 'D1', 'Airfryer Salmon & Potatoes', 'dinner', 'regular', 1, 50, 60, 22, 638, '220g salmon fillet, 280g potatoes, veggies', 'Airfry salmon 200C/10min. Potatoes 200C/18min.'),
  (null, 'D2', 'Beef Strips & Veggies', 'dinner', 'regular', 1, 55, 50, 18, 582, '220g lean beef (5% fat) strips, 200g rice, peppers', 'Airfry beef strips 190C/10min. Serve with rice and peppers.'),
  (null, 'BF1', 'Vegan Oats & Tahini', 'breakfast', 'fasting', 1, 30, 55, 18, 490, '30g vegan protein, 60g oats, almond milk, 15g tahini', 'Mix protein with almond milk, stir in oats, top with tahini.'),
  (null, 'LF1', 'Crispy Chickpeas & Bread', 'lunch', 'fasting', 1, 25, 75, 20, 580, '250g canned chickpeas, 120g whole wheat bread, 15g olive oil', 'Drain chickpeas, toss in olive oil & spices. Airfry 190C/12min until crispy.'),
  (null, 'SF1', 'Soy Yogurt & Vegan Pro', 'snack', 'fasting', 1, 25, 35, 8, 312, '200g soy yogurt, 20g vegan protein, 1 large apple', 'Mix vegan protein powder into soy yogurt.'),
  (null, 'DF1', 'Crispy Tofu & Lentils', 'dinner', 'fasting', 1, 35, 50, 18, 490, '150g firm tofu, 250g cooked lentils, 10g olive oil', 'Press tofu, cube, toss with olive oil/soy sauce. Airfry 200C/15min.'),
  (null, 'DF2', 'Garlic Shrimp & Rice', 'dinner', 'fasting', 1, 45, 55, 12, 490, '200g shrimp, 200g rice, 10g olive oil', 'Toss shrimp in olive oil & garlic powder. Airfry 200C/8min.'),
  (null, 'BF1v2', 'Vegan Oats & Tahini+', 'breakfast', 'fasting', 2, 44, 47, 18, 513, '50g vegan protein, 45g oats, 250ml soy milk, 15g tahini', '+20g protein powder, oats 60g->45g. Mix protein with soy milk, stir in oats, top with tahini.'),
  (null, 'LF1v2', 'Chickpeas, Edamame & Bread', 'lunch', 'fasting', 2, 35, 57, 21, 555, '250g canned chickpeas, 150g shelled edamame, 60g whole wheat bread, 10g olive oil', '+150g edamame, bread 120g->60g, oil 15g->10g. Airfry chickpeas 190C/12min; steam edamame.'),
  (null, 'SF1v2', 'Soy Yogurt & Vegan Pro+', 'snack', 'fasting', 2, 37, 36, 9, 370, '200g soy yogurt, 35g vegan protein, 1 large apple', '+15g protein powder. Mix into soy yogurt.'),
  (null, 'DF1v2', 'Crispy Tofu & Lentils+', 'dinner', 'fasting', 2, 47, 42, 22, 532, '250g firm tofu, 200g cooked lentils, 5g olive oil', 'Tofu 150g->250g, lentils 250g->200g, oil 10g->5g. Airfry 200C/15min.'),
  (null, 'DF2v2', 'Garlic Shrimp & Rice+', 'dinner', 'fasting', 2, 56, 55, 12, 543, '250g shrimp, 200g rice, 10g olive oil', 'Shrimp 200g->250g. Toss in olive oil & garlic powder. Airfry 200C/8min.'),
  (null, 'S2', 'Cottage Cheese & Berries', 'snack', 'regular', 3, 28, 40, 9, 339, '200g cottage cheese 2%, 150g mixed berries, 15g honey, 10g almonds', 'No cooking. Stir honey through the cottage cheese, top with berries and crushed almonds.'),
  (null, 'SF2', 'Vegan Protein Smoothie', 'snack', 'fasting', 3, 41, 39, 7, 365, '40g vegan protein, 250ml soy milk, 1 banana, ice', 'Blend everything with ice. Drink post-training or mid-afternoon.');

insert into public.exercises (user_id, code, name, category, focus, est_kcal, duration_min, notes) values
  (null, 'E1', 'Push (Chest/Shoulders/Triceps)', 'resistance', 'Incline Press, Overhead Press, Dips, Lateral Raises', 300, 60, 'Progressive overload. RPE 7-8.'),
  (null, 'E2', 'Pull (Back/Biceps/Rear Delts)', 'resistance', 'Pull-ups/Lat Pulldown, Rows, Face Pulls, Bicep Curls', 300, 60, 'Control the eccentric. Squeeze the back.'),
  (null, 'E3', 'Legs (Quads/Hams/Glutes/Calves)', 'resistance', 'Squats/Hack Squats, RDLs, Leg Extensions, Leg Curls', 375, 68, 'Heavy compound day. Tough on the CNS.'),
  (null, 'E4', 'Upper Body (All Round)', 'resistance', 'Chest Press, Row, Shoulder Press, Pulldown, Arms', 320, 60, 'Shorter rest periods (60-90s).'),
  (null, 'E5', 'Lower Body (All Round)', 'resistance', 'Leg Press, Lunges, Glute Ham Raises, Calves', 350, 60, 'Higher rep ranges (10-15) vs E3.'),
  (null, 'C1', 'Active Recovery / Zone 2', 'cardio', 'Brisk walking, light cycling, or stairmaster', 250, 40, 'HR 110-130bpm. Boosts recovery.'),
  (null, 'R1', 'Full Rest', 'rest', 'Stretching, mobility work, or complete rest', 0, 0, 'Crucial for CNS recovery and muscle growth.');

insert into public.exercise_movements (exercise_id, name, order_index, target_sets, rep_low, rep_high)
  select id, 'Incline Press', 0, 4, 6, 10 from public.exercises where code = 'E1' and user_id is null
  union all
  select id, 'Overhead Press', 1, 3, 8, 12 from public.exercises where code = 'E1' and user_id is null
  union all
  select id, 'Dips', 2, 3, 8, 12 from public.exercises where code = 'E1' and user_id is null
  union all
  select id, 'Lateral Raises', 3, 3, 12, 15 from public.exercises where code = 'E1' and user_id is null
  union all
  select id, 'Lat Pulldown / Pull-ups', 0, 4, 8, 12 from public.exercises where code = 'E2' and user_id is null
  union all
  select id, 'Barbell Row', 1, 4, 6, 10 from public.exercises where code = 'E2' and user_id is null
  union all
  select id, 'Face Pulls', 2, 3, 12, 15 from public.exercises where code = 'E2' and user_id is null
  union all
  select id, 'Bicep Curls', 3, 3, 10, 12 from public.exercises where code = 'E2' and user_id is null
  union all
  select id, 'Squat / Hack Squat', 0, 4, 5, 8 from public.exercises where code = 'E3' and user_id is null
  union all
  select id, 'Romanian Deadlift', 1, 3, 6, 10 from public.exercises where code = 'E3' and user_id is null
  union all
  select id, 'Leg Extension', 2, 3, 10, 15 from public.exercises where code = 'E3' and user_id is null
  union all
  select id, 'Leg Curl', 3, 3, 10, 15 from public.exercises where code = 'E3' and user_id is null
  union all
  select id, 'Calf Raise', 4, 3, 12, 15 from public.exercises where code = 'E3' and user_id is null
  union all
  select id, 'Chest Press', 0, 3, 10, 12 from public.exercises where code = 'E4' and user_id is null
  union all
  select id, 'Seated Row', 1, 3, 10, 12 from public.exercises where code = 'E4' and user_id is null
  union all
  select id, 'Shoulder Press', 2, 3, 10, 12 from public.exercises where code = 'E4' and user_id is null
  union all
  select id, 'Lat Pulldown', 3, 3, 10, 12 from public.exercises where code = 'E4' and user_id is null
  union all
  select id, 'Arms Superset', 4, 3, 12, 15 from public.exercises where code = 'E4' and user_id is null
  union all
  select id, 'Leg Press', 0, 4, 10, 15 from public.exercises where code = 'E5' and user_id is null
  union all
  select id, 'Walking Lunges', 1, 3, 10, 12 from public.exercises where code = 'E5' and user_id is null
  union all
  select id, 'Glute Ham Raise', 2, 3, 10, 15 from public.exercises where code = 'E5' and user_id is null
  union all
  select id, 'Calf Raise', 3, 4, 12, 15 from public.exercises where code = 'E5' and user_id is null;
