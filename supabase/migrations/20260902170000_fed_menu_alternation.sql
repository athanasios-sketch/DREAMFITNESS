-- Fed-day menus alternate by a COUNTER OF FED DAYS, not by day number.
-- Keying off day_no meant two fed days either side of a fasting day could land
-- on the same parity - Thursday and Saturday both drawing menu B - so the
-- rotation quietly stalled exactly where the variety matters most.
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

    -- Chest and back alternate between Monday and Thursday, and which one
    -- leads is decided per ISO week. Hashing the week (rather than random())
    -- means the answer is stable: regenerating the plan never reshuffles a
    -- week you have already trained. Monday and Thursday always share an ISO
    -- week, so the pair can never collide on the same session.
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
      -- Wednesday takes the oat-milk breakfast, Friday the soy one
      v_codes := case when v_dow = 3
                   then array['BF2v2','LF1v2','SF1v2','DF1v2','SF2']
                   else array['BF1v2','LF1v2','SF1v2','DF2v2','SF3'] end;
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
