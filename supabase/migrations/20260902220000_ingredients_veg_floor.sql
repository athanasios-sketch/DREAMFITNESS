-- Every meal, down to the gram.
--
-- `meals.ingredients` was a sentence. You cannot scale a sentence, you cannot
-- sum a sentence, and - as it turns out - you cannot trust one either. Rebuilt
-- from per-100g reference values and the amounts actually cooked, the rotation
-- came out ~120 kcal/day HEAVIER than the hand-set numbers claimed. L1 alone
-- was 88 kcal light, almost exactly the 15g of olive oil nobody had counted.
-- Over 90 days that gap is ~11,000 kcal - about 1.4 kg of the 5.8 the plan was
-- promising. The menus were not wrong; the arithmetic describing them was.
--
-- So ingredients become rows. Each carries its reference values per 100 g/ml
-- and the amount this recipe uses; the contribution is a generated column, and
-- meals.protein_g/carbs_g/fat_g/kcal are now a SUM over those rows rather than
-- a number typed in by hand. Change 240g of chicken to 180g and every total
-- above it follows, which is the point: you rarely have exactly 240g.
--
-- Two other things ride along, because both needed gram-level data to exist:
--
--   Vegetables. There was no vegetable target anywhere and the entire fed
--   rotation contained the words "veggies" and "peppers". 400 g/day of
--   non-starchy veg is ~100 kcal and it is the cheapest satiety there is on a
--   cut. Now an explicit ingredient in every lunch and dinner.
--
--   Fibre. meals had no fibre column at all, so a day's load was unknowable.
--   It is now summed like any other macro - and it immediately shows that
--   Wednesday runs ~60 g against ~32 g on a fed day. See the note at the end.

-- ============================================================ meals
alter table public.meals
  add column if not exists fiber_g numeric(6,2) check (fiber_g >= 0),
  add column if not exists veg_g   numeric(6,1) check (veg_g   >= 0);

comment on column public.meals.veg_g is
  'Non-starchy vegetables in this meal. Fruit and starchy roots do not count -
   they are good food, but they are not what the 400 g/day floor is buying.';

-- ============================================================ ingredients
create table if not exists public.meal_ingredients (
  id           bigint generated always as identity primary key,
  meal_id      bigint not null references public.meals(id) on delete cascade,
  order_index  smallint not null default 0,
  name         text not null,
  amount       numeric(7,1) not null check (amount >= 0),
  unit         text not null default 'g' check (unit in ('g','ml')),
  role         text not null default 'extra'
                 check (role in ('protein','carb','fat','produce','veg','extra')),

  -- Reference values per 100 g / 100 ml. Storing the REFERENCE rather than the
  -- contribution is what makes a portion change exact instead of proportional
  -- guesswork.
  kcal_100     numeric(6,1) not null check (kcal_100    >= 0),
  protein_100  numeric(5,1) not null default 0 check (protein_100 >= 0),
  carbs_100    numeric(5,1) not null default 0 check (carbs_100   >= 0),
  fat_100      numeric(5,1) not null default 0 check (fat_100     >= 0),
  fiber_100    numeric(5,1) not null default 0 check (fiber_100   >= 0),
  is_veg       boolean not null default false,
  note         text,

  -- what THIS amount contributes, maintained by the database
  kcal      numeric(8,2) generated always as (kcal_100    * amount / 100) stored,
  protein_g numeric(8,2) generated always as (protein_100 * amount / 100) stored,
  carbs_g   numeric(8,2) generated always as (carbs_100   * amount / 100) stored,
  fat_g     numeric(8,2) generated always as (fat_100     * amount / 100) stored,
  fiber_g   numeric(8,2) generated always as (fiber_100   * amount / 100) stored
);
create index if not exists meal_ingredients_meal_id_idx
  on public.meal_ingredients (meal_id, order_index);

comment on table public.meal_ingredients is
  'One row per ingredient. meals.* macros are a SUM over these - see
   recompute_meal_macros(). Amounts are RAW/DRY for anything weighed before
   cooking, DRAINED for canned, COOKED where the name says cooked.';

alter table public.meal_ingredients enable row level security;

-- Visibility follows the parent meal exactly: system rows readable by all,
-- your own rows yours alone.
create policy meal_ingredients_read on public.meal_ingredients for select to authenticated
  using (exists (select 1 from public.meals m
                  where m.id = meal_id
                    and (m.user_id is null or m.user_id = (select auth.uid()))));
create policy meal_ingredients_write on public.meal_ingredients for all to authenticated
  using (exists (select 1 from public.meals m
                  where m.id = meal_id and m.user_id = (select auth.uid())))
  with check (exists (select 1 from public.meals m
                  where m.id = meal_id and m.user_id = (select auth.uid())));

-- ==================================================== macros follow the rows
-- Meals without ingredients (the superseded v1 fasting set) are left alone
-- rather than zeroed - the inner join is doing that work deliberately.
create or replace function public.recompute_meal_macros(p_meal_id bigint default null)
returns integer language plpgsql security invoker set search_path = '' as $$
declare v_n integer;
begin
  update public.meals m set
    protein_g = round(t.p, 2), carbs_g = round(t.c, 2), fat_g = round(t.f, 2),
    kcal      = round(t.k)::int,
    fiber_g   = round(t.fib, 2),
    veg_g     = round(t.veg, 1)
  from (
    select meal_id,
           sum(protein_g) p, sum(carbs_g) c, sum(fat_g) f, sum(kcal) k,
           sum(fiber_g) fib,
           sum(case when is_veg then amount else 0 end) veg
      from public.meal_ingredients group by meal_id
  ) t
  where m.id = t.meal_id and (p_meal_id is null or m.id = p_meal_id);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

grant execute on function public.recompute_meal_macros(bigint) to authenticated;
-- ============================================ ingredient rows
delete from public.meal_ingredients mi using public.meals m
  where m.id = mi.meal_id and m.user_id is null;

insert into public.meal_ingredients
  (meal_id, order_index, name, amount, unit, role,
   kcal_100, protein_100, carbs_100, fat_100, fiber_100, is_veg, note)
select m.id, v.order_index, v.name, v.amount, v.unit, v.role,
       v.kcal_100, v.protein_100, v.carbs_100, v.fat_100, v.fiber_100, v.is_veg, v.note
from (values
  ('B1', 0, 'Whole eggs (2)', 100, 'g', 'protein', 143, 12.6, 0.7, 9.5, 0.0, false, 'One medium egg is about 50g of edible egg.'),
  ('B1', 1, 'Egg whites', 200, 'g', 'protein', 52, 10.9, 0.7, 0.2, 0.0, false, 'Carton whites, or about 5 eggs worth.'),
  ('B1', 2, 'Rolled oats, dry', 60, 'g', 'carb', 379, 13.2, 67.7, 6.5, 10.1, false, 'Weighed DRY. 60g looks like nothing in the bag and fills the bowl cooked.'),
  ('B2', 0, 'Greek yogurt 2%', 250, 'g', 'protein', 73, 9.9, 3.9, 1.9, 0.0, false, null),
  ('B2', 1, 'Whey protein (1 scoop)', 30, 'g', 'protein', 400, 80.0, 8.0, 5.0, 0.0, false, 'One 30g scoop. Check yours - scoops run 25-35g.'),
  ('B2', 2, 'Banana (1 medium)', 120, 'g', 'produce', 89, 1.1, 22.8, 0.3, 2.6, false, null),
  ('B2', 3, 'Almonds', 10, 'g', 'fat', 579, 21.2, 21.6, 49.9, 12.5, false, 'About 8 almonds per 10g.'),
  ('L1', 0, 'Chicken breast, raw', 240, 'g', 'protein', 120, 22.5, 0.0, 2.6, 0.0, false, 'Weighed raw. Cooked it loses about a quarter of its weight.'),
  ('L1', 1, 'Basmati rice, boiled', 200, 'g', 'carb', 130, 2.7, 28.2, 0.3, 0.4, false, 'Weighed COOKED. Roughly a third of this dry.'),
  ('L1', 2, 'Olive oil', 12, 'g', 'fat', 884, 0.0, 0.0, 100.0, 0.0, false, 'A tablespoon is about 13g. This is the ingredient people misjudge most.'),
  ('L1', 3, 'Broccoli', 120, 'g', 'veg', 34, 2.8, 6.6, 0.4, 2.6, true, null),
  ('L1', 4, 'Peppers', 80, 'g', 'veg', 26, 1.0, 6.0, 0.3, 2.1, true, null),
  ('L2', 0, 'Turkey breast, raw', 220, 'g', 'protein', 111, 23.7, 0.0, 1.2, 0.0, false, 'Weighed raw.'),
  ('L2', 1, 'Sweet potato, raw', 300, 'g', 'carb', 86, 1.6, 20.1, 0.1, 3.0, false, 'Weighed raw.'),
  ('L2', 2, 'Olive oil', 10, 'g', 'fat', 884, 0.0, 0.0, 100.0, 0.0, false, 'A tablespoon is about 13g. This is the ingredient people misjudge most.'),
  ('L2', 3, 'Green beans', 120, 'g', 'veg', 31, 1.8, 7.0, 0.2, 2.7, true, null),
  ('L2', 4, 'Cherry tomatoes', 80, 'g', 'veg', 18, 0.9, 3.9, 0.2, 1.2, true, null),
  ('S1', 0, 'Whey protein (1 scoop)', 30, 'g', 'protein', 400, 80.0, 8.0, 5.0, 0.0, false, 'One 30g scoop. Check yours - scoops run 25-35g.'),
  ('S1', 1, 'Apple (1 medium)', 180, 'g', 'produce', 52, 0.3, 13.8, 0.2, 2.4, false, null),
  ('S2', 0, 'Cottage cheese 2%', 200, 'g', 'protein', 84, 11.1, 4.6, 2.3, 0.0, false, null),
  ('S2', 1, 'Mixed berries', 150, 'g', 'produce', 50, 0.9, 11.6, 0.4, 3.5, false, null),
  ('S2', 2, 'Honey', 15, 'g', 'extra', 304, 0.3, 82.4, 0.0, 0.2, false, 'A level tablespoon is about 15g.'),
  ('S2', 3, 'Almonds', 10, 'g', 'fat', 579, 21.2, 21.6, 49.9, 12.5, false, 'About 8 almonds per 10g.'),
  ('D1', 0, 'Salmon fillet, raw', 190, 'g', 'protein', 208, 20.4, 0.0, 13.4, 0.0, false, 'Weighed raw, skin on.'),
  ('D1', 1, 'Potatoes, raw', 280, 'g', 'carb', 77, 2.0, 17.5, 0.1, 2.2, false, 'Weighed raw.'),
  ('D1', 2, 'Broccoli', 100, 'g', 'veg', 34, 2.8, 6.6, 0.4, 2.6, true, null),
  ('D1', 3, 'Courgette', 100, 'g', 'veg', 17, 1.2, 3.1, 0.3, 1.0, true, null),
  ('D2', 0, 'Lean beef 5%, raw', 240, 'g', 'protein', 137, 21.4, 0.0, 5.0, 0.0, false, 'Weighed raw. 5% fat mince or strips.'),
  ('D2', 1, 'Rice, boiled', 160, 'g', 'carb', 130, 2.7, 28.2, 0.3, 0.4, false, 'Weighed COOKED. Roughly a third of this dry.'),
  ('D2', 2, 'Olive oil', 5, 'g', 'fat', 884, 0.0, 0.0, 100.0, 0.0, false, 'A tablespoon is about 13g. This is the ingredient people misjudge most.'),
  ('D2', 3, 'Peppers', 120, 'g', 'veg', 26, 1.0, 6.0, 0.3, 2.1, true, null),
  ('D2', 4, 'Onion', 40, 'g', 'veg', 40, 1.1, 9.3, 0.1, 1.7, true, null),
  ('D2', 5, 'Mushrooms', 40, 'g', 'veg', 22, 3.1, 3.3, 0.3, 1.0, true, null),
  ('BF2v2', 0, 'Vegan protein', 35, 'g', 'protein', 375, 75.0, 8.0, 5.0, 4.0, false, 'Pea/rice blend. Check the label; plant powders vary more than whey.'),
  ('BF2v2', 1, 'Rolled oats (βρώμη), dry', 45, 'g', 'carb', 379, 13.2, 67.7, 6.5, 10.1, false, 'Weighed DRY. 60g looks like nothing in the bag and fills the bowl cooked.'),
  ('BF2v2', 2, 'Oat milk', 200, 'ml', 'extra', 43, 0.8, 6.6, 1.5, 0.8, false, null),
  ('BF2v2', 3, 'Honey', 15, 'g', 'extra', 304, 0.3, 82.4, 0.0, 0.2, false, 'A level tablespoon is about 15g.'),
  ('BF2v2', 4, 'Tahini', 5, 'g', 'fat', 595, 17.0, 21.2, 53.8, 9.3, false, 'Runny, stirred well before spooning.'),
  ('BF3', 0, 'Vegan protein', 35, 'g', 'protein', 375, 75.0, 8.0, 5.0, 4.0, false, 'Pea/rice blend. Check the label; plant powders vary more than whey.'),
  ('BF3', 1, 'Rolled oats (βρώμη), dry', 60, 'g', 'carb', 379, 13.2, 67.7, 6.5, 10.1, false, 'Weighed DRY. 60g looks like nothing in the bag and fills the bowl cooked.'),
  ('BF3', 2, 'Unsweetened almond milk', 250, 'ml', 'extra', 15, 0.5, 0.6, 1.1, 0.3, false, null),
  ('BF3', 3, 'Honey', 15, 'g', 'extra', 304, 0.3, 82.4, 0.0, 0.2, false, 'A level tablespoon is about 15g.'),
  ('BF3', 4, 'Tahini', 5, 'g', 'fat', 595, 17.0, 21.2, 53.8, 9.3, false, 'Runny, stirred well before spooning.'),
  ('BF1v2', 0, 'Vegan protein', 50, 'g', 'protein', 375, 75.0, 8.0, 5.0, 4.0, false, 'Pea/rice blend. Check the label; plant powders vary more than whey.'),
  ('BF1v2', 1, 'Rolled oats, dry', 45, 'g', 'carb', 379, 13.2, 67.7, 6.5, 10.1, false, 'Weighed DRY. 60g looks like nothing in the bag and fills the bowl cooked.'),
  ('BF1v2', 2, 'Unsweetened soy milk', 250, 'ml', 'extra', 43, 3.3, 1.8, 2.0, 0.5, false, null),
  ('BF1v2', 3, 'Tahini', 15, 'g', 'fat', 595, 17.0, 21.2, 53.8, 9.3, false, 'Runny, stirred well before spooning.'),
  ('LF1v2', 0, 'Chickpeas, canned & drained', 150, 'g', 'protein', 139, 7.1, 22.5, 2.6, 6.4, false, 'Drained weight, not the tin weight.'),
  ('LF1v2', 1, 'Edamame, shelled', 150, 'g', 'protein', 121, 11.9, 8.9, 5.2, 5.2, false, null),
  ('LF1v2', 2, 'Wholewheat bread', 40, 'g', 'carb', 247, 13.4, 41.3, 3.4, 6.8, false, null),
  ('LF1v2', 3, 'Olive oil', 10, 'g', 'fat', 884, 0.0, 0.0, 100.0, 0.0, false, 'A tablespoon is about 13g. This is the ingredient people misjudge most.'),
  ('LF1v2', 4, 'Salad leaves', 60, 'g', 'veg', 17, 1.4, 2.9, 0.2, 1.8, true, null),
  ('LF1v2', 5, 'Cucumber', 70, 'g', 'veg', 15, 0.7, 3.6, 0.1, 0.5, true, null),
  ('LF1v2', 6, 'Cherry tomatoes', 70, 'g', 'veg', 18, 0.9, 3.9, 0.2, 1.2, true, null),
  ('SF1v2', 0, 'Soy yogurt', 200, 'g', 'protein', 54, 3.5, 4.5, 2.4, 0.6, false, null),
  ('SF1v2', 1, 'Vegan protein', 35, 'g', 'protein', 375, 75.0, 8.0, 5.0, 4.0, false, 'Pea/rice blend. Check the label; plant powders vary more than whey.'),
  ('SF1v2', 2, 'Apple (1 medium)', 150, 'g', 'produce', 52, 0.3, 13.8, 0.2, 2.4, false, null),
  ('SF2', 0, 'Vegan protein', 25, 'g', 'protein', 375, 75.0, 8.0, 5.0, 4.0, false, 'Pea/rice blend. Check the label; plant powders vary more than whey.'),
  ('SF2', 1, 'Unsweetened soy milk', 250, 'ml', 'extra', 43, 3.3, 1.8, 2.0, 0.5, false, null),
  ('SF2', 2, 'Banana', 100, 'g', 'produce', 89, 1.1, 22.8, 0.3, 2.6, false, null),
  ('SF3', 0, 'Vegan protein', 25, 'g', 'protein', 375, 75.0, 8.0, 5.0, 4.0, false, 'Pea/rice blend. Check the label; plant powders vary more than whey.'),
  ('SF3', 1, 'Unsweetened almond milk', 300, 'ml', 'extra', 15, 0.5, 0.6, 1.1, 0.3, false, null),
  ('SF3', 2, 'Banana', 100, 'g', 'produce', 89, 1.1, 22.8, 0.3, 2.6, false, null),
  ('SF3', 3, 'Almond butter', 5, 'g', 'fat', 614, 21.0, 18.8, 55.5, 10.3, false, null),
  ('DF1v2', 0, 'Firm tofu', 250, 'g', 'protein', 144, 15.8, 4.3, 8.7, 2.3, false, null),
  ('DF1v2', 1, 'Lentils, cooked', 120, 'g', 'protein', 116, 9.0, 20.1, 0.4, 7.9, false, 'Weighed COOKED, or drained from a tin.'),
  ('DF1v2', 2, 'Olive oil', 5, 'g', 'fat', 884, 0.0, 0.0, 100.0, 0.0, false, 'A tablespoon is about 13g. This is the ingredient people misjudge most.'),
  ('DF1v2', 3, 'Spinach', 100, 'g', 'veg', 23, 2.9, 3.6, 0.4, 2.2, true, null),
  ('DF1v2', 4, 'Mushrooms', 100, 'g', 'veg', 22, 3.1, 3.3, 0.3, 1.0, true, null),
  ('DF2v2', 0, 'Shrimp, raw', 250, 'g', 'protein', 85, 20.1, 0.2, 0.5, 0.0, false, 'Weighed raw, peeled.'),
  ('DF2v2', 1, 'Rice, boiled', 180, 'g', 'carb', 130, 2.7, 28.2, 0.3, 0.4, false, 'Weighed COOKED. Roughly a third of this dry.'),
  ('DF2v2', 2, 'Olive oil', 10, 'g', 'fat', 884, 0.0, 0.0, 100.0, 0.0, false, 'A tablespoon is about 13g. This is the ingredient people misjudge most.'),
  ('DF2v2', 3, 'Courgette', 100, 'g', 'veg', 17, 1.2, 3.1, 0.3, 1.0, true, null),
  ('DF2v2', 4, 'Peppers', 100, 'g', 'veg', 26, 1.0, 6.0, 0.3, 2.1, true, null),
  ('OATS', 0, 'Rolled oats, dry', 60, 'g', 'carb', 379, 13.2, 67.7, 6.5, 10.1, false, 'Weighed DRY. 60g looks like nothing in the bag and fills the bowl cooked.'),
  ('HONEY', 0, 'Honey', 15, 'g', 'extra', 304, 0.3, 82.4, 0.0, 0.2, false, 'A level tablespoon is about 15g.'),
  ('OATM', 0, 'Oat milk', 250, 'ml', 'extra', 43, 0.8, 6.6, 1.5, 0.8, false, null),
  ('ALMM', 0, 'Unsweetened almond milk', 250, 'ml', 'extra', 15, 0.5, 0.6, 1.1, 0.3, false, null),
  ('SF4', 0, 'Rolled oats, dry', 40, 'g', 'carb', 379, 13.2, 67.7, 6.5, 10.1, false, 'Weighed DRY. 60g looks like nothing in the bag and fills the bowl cooked.'),
  ('SF4', 1, 'Unsweetened almond milk', 200, 'ml', 'extra', 15, 0.5, 0.6, 1.1, 0.3, false, null),
  ('SF4', 2, 'Vegan protein', 15, 'g', 'protein', 375, 75.0, 8.0, 5.0, 4.0, false, 'Pea/rice blend. Check the label; plant powders vary more than whey.'),
  ('SF4', 3, 'Honey', 10, 'g', 'extra', 304, 0.3, 82.4, 0.0, 0.2, false, 'A level tablespoon is about 15g.')
) as v(code, order_index, name, amount, unit, role,
       kcal_100, protein_100, carbs_100, fat_100, fiber_100, is_veg, note)
join public.meals m on m.code = v.code and m.user_id is null;

-- ============================================ ingredient text + steps
update public.meals set ingredients = '100g whole eggs (2), 200g egg whites, 60g rolled oats, dry', steps = array['Boil 250ml water, stir in 60g oats and simmer 4-5 min until thick. Cinnamon off the heat.', 'Whisk 2 whole eggs and 200g egg whites with salt and pepper in an oven-safe dish that fits your basket.', 'Air fry 180C for 8 min, stirring once at the 4 min mark so the centre sets evenly.', 'Turn out onto the plate, oats alongside.']
 where code = 'B1' and user_id is null;
update public.meals set ingredients = '250g greek yogurt 2%, 30g whey protein (1 scoop), 120g banana (1 medium), 10g almonds', steps = array['Stir 1 scoop of whey into 250g Greek yogurt a little at a time.', 'Slice the banana, crush 10g almonds, scatter both on top.']
 where code = 'B2' and user_id is null;
update public.meals set ingredients = '240g chicken breast, raw, 200g basmati rice, boiled, 12g olive oil, 120g broccoli, 80g peppers', steps = array['Rinse 73g dry basmati until the water runs clear, then boil 10-12 min and drain (makes ~200g cooked).', 'Coat 240g chicken in 12g olive oil, paprika, oregano and salt.', 'Air fry 195C for 18 min, flipping at 10 min.', 'Broccoli and peppers into the basket for the last 8 min, or steam them 5 min while the chicken rests.', 'Rest 3 min before slicing.']
 where code = 'L1' and user_id is null;
update public.meals set ingredients = '220g turkey breast, raw, 300g sweet potato, raw, 10g olive oil, 120g green beans, 80g cherry tomatoes', steps = array['Cube 300g sweet potato to roughly 2cm and toss in half the oil.', 'Air fry 200C for 20 min, shaking the basket at 10 min.', 'Toss the turkey in the rest of the oil with herbs and salt.', 'Air fry 185C for 16 min. If your basket is small, do the potatoes first and let them rest while the turkey cooks.', 'Steam the green beans 5 min; tomatoes raw on the side.']
 where code = 'L2' and user_id is null;
update public.meals set ingredients = '30g whey protein (1 scoop), 180g apple (1 medium)'
 where code = 'S1' and user_id is null;
update public.meals set ingredients = '200g cottage cheese 2%, 150g mixed berries, 15g honey, 10g almonds', steps = array['Stir 15g honey through 200g cottage cheese.', 'Top with 150g berries and 10g crushed almonds.']
 where code = 'S2' and user_id is null;
update public.meals set ingredients = '190g salmon fillet, raw, 280g potatoes, raw, 100g broccoli, 100g courgette', steps = array['Cube 280g potatoes and air fry 200C for 18 min, shaking at 9 min.', 'Pat 190g salmon dry, season, and lay it skin-side down.', 'Air fry 200C for 10 min, adding the broccoli and courgette for the last 6 min.']
 where code = 'D1' and user_id is null;
update public.meals set ingredients = '240g lean beef 5%, raw, 160g rice, boiled, 5g olive oil, 120g peppers, 40g onion, 40g mushrooms', steps = array['Boil 52g dry rice for 10-12 min (makes ~160g cooked) and drain.', 'Toss 240g beef strips, the peppers, onion and mushrooms in 5g oil with paprika and garlic.', 'Air fry 190C for 10 min, shaking at 5 min. 5% beef needs almost no added fat.']
 where code = 'D2' and user_id is null;
update public.meals set ingredients = '35g vegan protein, 45g rolled oats (βρώμη), dry, 200ml oat milk, 15g honey, 5g tahini', steps = array['Bring 200ml oat milk just to a simmer with a pinch of salt, stir in 45g oats, cook 4 min.', 'Off the heat, stir in 35g vegan protein a third at a time.', 'Honey and 5g tahini on top once it stops steaming.']
 where code = 'BF2v2' and user_id is null;
update public.meals set ingredients = '35g vegan protein, 60g rolled oats (βρώμη), dry, 250ml unsweetened almond milk, 15g honey, 5g tahini', steps = array['Bring 250ml unsweetened almond milk to a simmer with a pinch of salt.', 'Stir in 60g oats and cook 5 min, stirring, until it thickens - almond milk is thin and needs the extra minute.', 'Off the heat, stir in 35g vegan protein a third at a time.', 'Honey and 5g tahini on top once it stops steaming.']
 where code = 'BF3' and user_id is null;
update public.meals set ingredients = '50g vegan protein, 45g rolled oats, dry, 250ml unsweetened soy milk, 15g tahini'
 where code = 'BF1v2' and user_id is null;
update public.meals set ingredients = '150g chickpeas, canned & drained, 150g edamame, shelled, 40g wholewheat bread, 10g olive oil, 60g salad leaves, 70g cucumber, 70g cherry tomatoes', steps = array['Drain 150g chickpeas and dry them thoroughly on a towel.', 'Toss in 10g olive oil with cumin, paprika and salt.', 'Air fry 190C for 12 min, shaking twice.', 'Boil 150g edamame for 4 min and salt them. Bread on the side.', 'Leaves, cucumber and tomatoes raw alongside, dressed with lemon.']
 where code = 'LF1v2' and user_id is null;
update public.meals set ingredients = '200g soy yogurt, 35g vegan protein, 150g apple (1 medium)', steps = array['Stir 35g vegan protein into 200g soy yogurt.', 'Eat the apple alongside.']
 where code = 'SF1v2' and user_id is null;
update public.meals set ingredients = '25g vegan protein, 250ml unsweetened soy milk, 100g banana', steps = array['Blend 25g vegan protein, 250ml soy milk and a banana with ice.', 'No blender: shake hard in a bottle and eat the banana on the side.']
 where code = 'SF2' and user_id is null;
update public.meals set ingredients = '25g vegan protein, 300ml unsweetened almond milk, 100g banana, 5g almond butter', steps = array['Blend 25g vegan protein, 300ml almond milk, a banana and 5g almond butter with ice.', 'No blender: shake the powder and milk, eat the banana and nut butter alongside.']
 where code = 'SF3' and user_id is null;
update public.meals set ingredients = '250g firm tofu, 120g lentils, cooked, 5g olive oil, 100g spinach, 100g mushrooms', steps = array['Press 250g firm tofu for 15 min - wrap it in a towel with something heavy on top.', 'Cube it and toss with a spoon of cornflour, soy sauce and 5g oil.', 'Air fry 200C for 15 min, shaking at 8 min.', 'Warm 120g lentils in a pot while it cooks; wilt the spinach and mushrooms in the same pot at the end.']
 where code = 'DF1v2' and user_id is null;
update public.meals set ingredients = '250g shrimp, raw, 180g rice, boiled, 10g olive oil, 100g courgette, 100g peppers', steps = array['Boil 58g dry rice for 10-12 min (makes ~180g cooked) and drain.', 'Pat 250g shrimp dry, toss in 10g oil with garlic powder and paprika.', 'Air fry 200C for 8 min, courgette and peppers alongside for the whole time.']
 where code = 'DF2v2' and user_id is null;
update public.meals set ingredients = '60g rolled oats, dry'
 where code = 'OATS' and user_id is null;
update public.meals set ingredients = '15g honey'
 where code = 'HONEY' and user_id is null;
update public.meals set ingredients = '250ml oat milk'
 where code = 'OATM' and user_id is null;
update public.meals set ingredients = '250ml unsweetened almond milk'
 where code = 'ALMM' and user_id is null;
update public.meals set ingredients = '40g rolled oats, dry, 200ml unsweetened almond milk, 15g vegan protein, 10g honey'
 where code = 'SF4' and user_id is null;

-- macros are now a consequence of the rows above, not a typed-in number
select public.recompute_meal_macros();

-- ==================================================== menus follow the day
-- The fed rotation alternated on `v_reg % 2` - a running count of regular days.
-- There are five regular days a week, an odd number, so the parity FLIPPED
-- every week: Saturday drew the small menu one week and the big one the next,
-- and Sunday got whichever was left. That is why leg day read -258 one week and
-- -131 the next. It was never a judgement about legs; it was a counter.
--
-- Assigning by weekday instead puts the larger menu (A, 2412) on the three
-- heaviest fed days and the smaller (B, 2306) on arms and rest. Six of the
-- seven days now land within 21 kcal of their budget.
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

    v_codes := case
      when v_dow = 3 then array['BF2v2','LF1v2','SF1v2','DF1v2','SF2']  -- fasting, oat milk
      when v_dow = 5 then array['BF3','LF1v2','SF1v2','DF2v2','SF3']    -- fasting, almond milk
      -- menu A: the bigger fed day. Chest/back Monday, back/chest Thursday, legs Saturday.
      when v_dow in (1, 4, 6) then array['B1','L1','S1','D1','S2']
      -- menu B: arms and the rest day.
      else array['B2','L2','S1','D2','S2']
    end;

    select sum(m.protein_g), sum(m.carbs_g), sum(m.fat_g), sum(m.kcal)
      into v_p, v_c, v_f, v_k
      from unnest(v_codes) as c(code)
      join public.meals m on m.code = c.code and m.user_id is null;

    insert into public.program_days
      (user_id, day_no, day_date, day_type, exercise_id,
       protein_target_g, carbs_target_g, fat_target_g, kcal_target, menu_kcal)
    values
      (v_user, v_day, v_date, case when v_fast then 'fasting' else 'regular' end,
       (select id from public.exercises where code = v_ex and user_id is null),
       v_p, v_c, v_f, v_k, v_k)
    returning id into v_pd;

    insert into public.program_day_meals (user_id, program_day_id, meal_id, slot_index)
    select v_user, v_pd, m.id, c.ord
      from unnest(v_codes) with ordinality as c(code, ord)
      join public.meals m on m.code = c.code and m.user_id is null;

    v_n := v_n + 1;
  end loop;

  perform public.plan_targets();
  return v_n;
end $$;

-- ============================================================ backfill
-- generate_program is never called from the app - the 90 days already exist.
-- Rewrite the fed days in place, from today forward. The past is a record of
-- what was eaten, not a plan to be edited.
update public.program_day_meals pdm
   set meal_id = (select id from public.meals
                   where user_id is null
                     and code = (case
                       when extract(isodow from pd.day_date) in (1,4,6)
                         then (array['B1','L1','S1','D1','S2'])[pdm.slot_index]
                         else (array['B2','L2','S1','D2','S2'])[pdm.slot_index] end))
  from public.program_days pd
 where pdm.program_day_id = pd.id
   and pd.day_type = 'regular'
   and pd.day_date >= current_date;

-- ============================================================ the fibre note
-- Fed days land at ~32 g of fibre, which is where a day should be. Wednesday
-- lands near 60 g and Friday near 46 g, because a plant-protein day is built on
-- chickpeas, edamame, lentils and oats and there is no way to buy 185 g of
-- protein from those without buying their fibre too. Cutting it further means
-- more isolated powder, which is the trade this migration just went the other
-- way on.
--
-- 60 g is not dangerous. It is uncomfortable if you arrive at it cold, and
-- Wednesday is a fasted-treadmill morning. For the first fortnight, halve the
-- chickpeas and the lentils on Wednesday and build back up - the ingredient
-- editor exists precisely so that costs you nothing to work out.
