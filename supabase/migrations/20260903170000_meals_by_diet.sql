-- Everyone could see everyone's food.
--
-- Meals with user_id null are "system" rows, readable by every authenticated
-- user, which was exactly right when there was one authenticated user. Now the
-- library is 44 rows: 27 built around oats, chickpeas and lentils, and 17 built
-- around holding 28 g of net carbohydrate. Thanos opens the Meals page and half
-- of it is food he is not eating; Ntinos opens it and finds βρώμη and ρεβύθια
-- in a plan whose entire premise is that he does not eat them.
--
-- Worse than untidy: the swap picker draws from the same library. One tap and a
-- ketogenic dinner becomes a bowl of oats, and nothing anywhere would object.
--
-- Fixing this in the Meals component would fix one screen. Doing it in the read
-- policy fixes every screen at once - the library, the swap list, any future
-- query - and makes the wrong meal unreachable rather than merely unlisted.

alter table public.meals
  add column if not exists diet_modes text[];

comment on column public.meals.diet_modes is
  'Diet modes this meal belongs to. NULL = shared by all (nothing is, yet).
   Enforced in the read policy, not just filtered in the UI, so a meal from the
   wrong plan cannot be reached by a swap either.';

-- Tag before the policy tightens, while this migration still runs as owner.
update public.meals set diet_modes = array['keto']
 where user_id is null and code like 'K-%';
update public.meals set diet_modes = array['balanced']
 where user_id is null and code not like 'K-%';

-- The viewer's diet, as a scalar. SECURITY DEFINER so the policy does not have
-- to re-enter the profiles policy on every row it tests, and STABLE so it is
-- evaluated once per statement rather than once per meal.
create or replace function public.my_diet_mode()
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select p.diet_mode from public.profiles p where p.id = auth.uid()),
                  'balanced');
$$;
grant execute on function public.my_diet_mode() to authenticated;

drop policy if exists meals_read on public.meals;
create policy meals_read on public.meals for select to authenticated
  using (
    user_id = (select auth.uid())
    or (user_id is null
        and (diet_modes is null or diet_modes @> array[public.my_diet_mode()]))
  );

-- meal_ingredients already gates on a subquery against meals, and RLS applies
-- inside that subquery too, so the gram-level rows follow the parent without a
-- second policy needing to know anything about diets.
