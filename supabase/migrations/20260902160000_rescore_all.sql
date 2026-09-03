-- Set/rest seconds, session METs and per-day session assignments all feed the
-- training-calorie estimate, and those estimates are already baked into every
-- daily_scores row. Editing them has to reach back through the history that
-- used them, or the dashboard keeps reporting numbers from the old model.
create or replace function public.rescore_all(p_from date default null)
returns integer language plpgsql security invoker set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_d date; v_n integer := 0;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  for v_d in select log_date from public.day_logs
              where user_id = v_user and (p_from is null or log_date >= p_from)
              order by log_date
  loop
    perform public.score_day(v_d);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
