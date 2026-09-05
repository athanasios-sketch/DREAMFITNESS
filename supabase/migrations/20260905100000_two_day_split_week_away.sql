-- Five days away, and the gym is not one of them.
--
-- The plan was built on four heavy days: Upper A / Lower A / Upper B / Lower B,
-- Monday, Tuesday, Thursday, Friday. All four of those days are now spent in
-- another town with no barbell, and only walking. So the week has two lifting
-- days in it - Saturday and Sunday - and that is the whole training budget.
--
-- Four sessions squeezed into two days is not the answer; two of them would
-- simply never be trained. What two consecutive days ask for is FULL BODY,
-- twice, with different patterns on each. Split upper/lower over Sat + Sun and
-- chest gets trained once a fortnight, which on a 700 kcal deficit is how you
-- arrive at 84 kg with less muscle than you started. Full body twice puts a
-- squat pattern, a press, a pull and a hinge on the week TWICE, and it is the
-- single best-evidenced arrangement for holding lean mass when the number of
-- sessions is fixed and small.
--
-- Saturday is squat-and-press, Sunday is hinge-and-pull, deliberately: back-to-
-- back days work when the second one is not repeating the first one's patterns
-- under the first one's fatigue.
--
-- What does NOT change: the load stays heavy (4-8 reps on the primaries).
-- Intensity is what tells a body in a deficit to keep the tissue; volume is
-- what it cannot afford much of on two days a week. And protein stays at 190 g
-- - with the training stimulus cut in half, the protein is doing more of the
-- work of holding muscle, not less.

insert into public.exercises
  (user_id, code, name, category, focus, duration_min, work_met, recovery_met,
   duty_pct, epoc_factor)
values
  (null, 'KFA', 'Full body A - squat & press', 'resistance',
   'quads, chest, shoulders, back', 70, 7.0, 2.5, null, 1.10),
  (null, 'KFB', 'Full body B - hinge & pull', 'resistance',
   'hamstrings, glutes, back, chest, arms', 70, 7.0, 2.5, null, 1.10)
on conflict (code) where user_id is null do update set
  name=excluded.name, category=excluded.category, focus=excluded.focus,
  duration_min=excluded.duration_min, work_met=excluded.work_met,
  recovery_met=excluded.recovery_met, epoc_factor=excluded.epoc_factor,
  archived=false;

delete from public.exercise_movements mv using public.exercises e
  where e.id = mv.exercise_id and e.user_id is null and e.code in ('KFA','KFB');

insert into public.exercise_movements
  (exercise_id, name, order_index, target_sets, rep_low, rep_high, tracking)
select e.id, v.name, v.order_index, v.sets, v.lo, v.hi, 'load'
  from (values
    ('KFA', 'Back squat',              0, 3, 4, 6),
    ('KFA', 'Barbell bench press',     1, 3, 4, 6),
    ('KFA', 'Barbell row',             2, 3, 6, 8),
    ('KFA', 'Overhead press',          3, 2, 6, 8),
    ('KFA', 'Leg curl',                4, 2, 10, 12),
    ('KFA', 'Standing calf raise',     5, 2, 10, 12),
    ('KFB', 'Romanian deadlift',       0, 3, 5, 6),
    ('KFB', 'Pull-up or lat pulldown', 1, 3, 6, 10),
    ('KFB', 'Incline dumbbell press',  2, 3, 6, 8),
    ('KFB', 'Bulgarian split squat',   3, 2, 8, 10),
    ('KFB', 'Barbell or dumbbell curl',4, 2, 8, 10),
    ('KFB', 'Hanging leg raise',       5, 2, 10, 15)
  ) as v(code, name, order_index, sets, lo, hi)
  join public.exercises e on e.code = v.code and e.user_id is null;

-- ==================================================== the week, rewritten
-- Monday to Friday are rest days carrying the leaner home menu. They are ALSO
-- travel days by default (profiles.travel_weekdays), which the generator swaps
-- to the supermarket menu - but the template still has to say what a Tuesday at
-- home looks like, for the weeks he does not go anywhere.
--
-- Saturday and Sunday take the four menu slots, and they are chosen so that a
-- fortnight cooks all eleven plates of the home rotation rather than the same
-- three every weekend.
do $$
declare u uuid; v_tpl bigint; d int;
begin
  select id into u from public.profiles where email = 'ntinos@dreamfitness.local';
  if u is null then return; end if;

  select id into v_tpl from public.program_templates
   where user_id = u and active order by id desc limit 1;
  if v_tpl is null then return; end if;

  delete from public.program_template_days where template_id = v_tpl;

  for d in 1..5 loop
    insert into public.program_template_days
      (template_id, dow, variant, day_type, exercise_code, meal_codes)
    values (v_tpl, d, 0, 'regular', 'REST', array['K-R1','K-R2','K-R3']),
           (v_tpl, d, 1, 'regular', 'REST', array['K-R1','K-R2','K-R3']);
  end loop;

  insert into public.program_template_days
    (template_id, dow, variant, day_type, exercise_code, meal_codes)
  values
    (v_tpl, 6, 0, 'regular', 'KFA', array['K-M1a','K-M2a','K-M3a']),
    (v_tpl, 6, 1, 'regular', 'KFA', array['K-M1b','K-M2c','K-M3a']),
    (v_tpl, 7, 0, 'regular', 'KFB', array['K-M1c','K-M2b','K-M3b']),
    (v_tpl, 7, 1, 'regular', 'KFB', array['K-M1d','K-M2d','K-M3c']);

  update public.program_templates
     set name = 'Away Mon-Fri, two full-body days at the weekend'
   where id = v_tpl;

  perform public.generate_program_user(u, null, null);
end $$;
