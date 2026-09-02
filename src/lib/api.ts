import { supabase } from './supabase';

/** Today's date as an Athens LOCAL calendar date (YYYY-MM-DD).
 *  en-CA formats as ISO. This is why the Oct 25 DST shift is a non-event. */
export const athensToday = (): string =>
  new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Athens', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date());

export const shiftDate = (iso: string, days: number): string => {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  return dt.toISOString().slice(0, 10);
};

let _library: any[] | null = null;
async function mealLibrary() {
  if (_library) return _library;
  const { data } = await supabase.from('meals').select('*').order('slot');
  _library = data ?? [];
  return _library;
}

let _profile: any = null;
async function profile(force = false) {
  if (_profile && !force) return _profile;
  const { data } = await supabase.from('profiles').select('*').maybeSingle();
  _profile = data;
  return _profile;
}

/** 1 = Monday .. 7 = Sunday, matching Postgres isodow. */
export const isoWeekday = (iso: string): number => {
  const [y, m, d] = iso.split('-').map(Number);
  return ((new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7) + 1;
};

export const WEEKDAYS = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];

/** The energy model, mirrored from public.session_kcal so the editor can show a
 *  live number without a round trip. Both sides must agree - if you change one,
 *  change the other. */
export function sessionKcal(o: {
  minutes: number; weightKg: number; workMet: number; recoveryMet: number;
  dutyPct?: number | null; setSeconds: number; restSeconds: number; epoc?: number;
}): number {
  // Half-typed input ("7." or "") must not render as NaN, so every field falls
  // back to its default the moment it stops being a finite number.
  const n = (v: any, fallback: number) => (Number.isFinite(+v) && v !== null && v !== '' ? +v : fallback);
  const set = n(o.setSeconds, 45), rest = n(o.restSeconds, 120);
  const cycle = set + rest;
  const duty = o.dutyPct == null || !Number.isFinite(+o.dutyPct)
    ? (cycle > 0 ? set / cycle : 1)
    : +o.dutyPct;
  const avg = n(o.workMet, 6) * duty + n(o.recoveryMet, 2) * (1 - duty);
  const net = Math.max(avg - 1, 0);
  return Math.max(0, net * 3.5 * n(o.weightKg, 80) / 200
    * Math.max(n(o.minutes, 0), 0) * n(o.epoc, 1));
}

export type Slot = { slot_index: number; meal: any; planned: any; log: any; swapped: boolean };

/** Everything the Today screen needs, in one round trip per table. */
export async function loadDay(date: string) {
  const { data: pd } = await supabase
    .from('program_days')
    .select('*, exercise:exercises(*, movements:exercise_movements(*)), planned:program_day_meals(slot_index, id, meal:meals(*))')
    .eq('day_date', date)
    .maybeSingle();

  const { data: log } = await supabase
    .from('day_logs').select('*').eq('log_date', date).maybeSingle();

  let mealLogs: any[] = [], sets: any[] = [], extras: any[] = [];
  if (log) {
    const [a, b, c] = await Promise.all([
      supabase.from('meal_logs').select('*').eq('day_log_id', log.id),
      supabase.from('set_logs').select('*').eq('day_log_id', log.id).order('id'),
      supabase.from('extra_items').select('*').eq('day_log_id', log.id).order('id'),
    ]);
    mealLogs = a.data ?? []; sets = b.data ?? []; extras = c.data ?? [];
  }

  const { data: score } = await supabase
    .from('daily_scores').select('*').eq('score_date', date).maybeSingle();

  // Both are static-ish reference data - fetch once per session, not per day view.
  const [library, prof] = await Promise.all([mealLibrary(), profile()]);

  // copy before sorting: this array ends up inside $state and must not be mutated in place
  const planned = [...(pd?.planned ?? [])].sort((x: any, y: any) => x.slot_index - y.slot_index);
  const meals = library ?? [];

  // `meal` is what you ACTUALLY ate; `planned` is what the program asked for.
  const slots: Slot[] = planned.map((p: any) => {
    const log = mealLogs.find((m) => m.slot_index === p.slot_index) ?? null;
    const actual = (log?.meal_id && meals.find((m: any) => m.id === log.meal_id)) || p.meal;
    return { slot_index: p.slot_index, meal: actual, planned: p.meal, log,
             swapped: actual.id !== p.meal.id };
  });

  return { programDay: pd, log, slots, planned, sets, extras, score, meals, profile: prof };
}

async function uid() {
  const { data } = await supabase.auth.getUser();
  return data.user!.id;
}

/** day_logs is the parent row for meals/sets/extras, so create it on demand. */
export async function ensureDayLog(date: string) {
  const { data: existing } = await supabase
    .from('day_logs').select('*').eq('log_date', date).maybeSingle();
  if (existing) return existing;
  const { data, error } = await supabase
    .from('day_logs').insert({ user_id: await uid(), log_date: date }).select().single();
  if (error) throw error;
  return data;
}

/** One writer for the slot, so completing / swapping / re-portioning never
 *  clobber each other's fields. */
async function writeSlot(date: string, slot: any, patch: Record<string, any>) {
  const log = await ensureDayLog(date);
  const mealId = patch.meal_id ?? slot.meal.id;
  const { error } = await supabase.from('meal_logs').upsert({
    user_id: log.user_id, day_log_id: log.id, slot_index: slot.slot_index,
    program_day_meal_id: null,
    meal_id: mealId,
    completed: patch.completed ?? slot.log?.completed ?? false,
    portion:   patch.portion   ?? slot.log?.portion   ?? 1,
    swapped:   mealId !== slot.planned.id,
  }, { onConflict: 'day_log_id,slot_index' });
  if (error) throw error;
}

export const toggleMeal = (date: string, slot: any, completed: boolean) =>
  writeSlot(date, slot, { completed });

/** Ate something else in this slot - a second dinner instead of lunch, say. */
export const swapMeal = (date: string, slot: any, mealId: number) =>
  writeSlot(date, slot, { meal_id: mealId });

/** 2 = ate it twice. Macros scale by this. */
export const setPortion = (date: string, slot: any, portion: number) =>
  writeSlot(date, slot, { portion });

export async function saveMetrics(date: string, fields: Record<string, any>) {
  const log = await ensureDayLog(date);
  const clean = Object.fromEntries(
    Object.entries(fields).map(([k, v]) => [k, v === '' || v === undefined ? null : v]));
  const { error } = await supabase.from('day_logs').update(clean).eq('id', log.id);
  if (error) throw error;
}

export async function addSet(date: string, exerciseId: number | null, row: any) {
  const log = await ensureDayLog(date);
  const { error } = await supabase.from('set_logs').insert({
    user_id: log.user_id, day_log_id: log.id, exercise_id: exerciseId,
    movement_id: row.movement_id ?? null, movement_name: row.movement_name,
    set_no: row.set_no, reps: row.reps, weight_kg: row.weight_kg, rpe: row.rpe || null,
    // a treadmill block and a plank are sets too; they just aren't reps x kilos
    duration_sec: row.duration_sec ?? null,
    distance_km:  row.distance_km  ?? null,
    incline_pct:  row.incline_pct  ?? null,
  });
  if (error) throw error;
}

export const deleteRow = (table: string, id: number) =>
  supabase.from(table).delete().eq('id', id);

export async function addExtra(date: string, item: any) {
  const log = await ensureDayLog(date);
  const { error } = await supabase.from('extra_items').insert({
    user_id: log.user_id, day_log_id: log.id, ...item,
  });
  if (error) throw error;
}

/** The 90-cell grid: every program day joined to its score (if any). */
export async function loadProgram() {
  const [{ data: days }, { data: scores }, { data: logs }, { data: profile }] = await Promise.all([
    supabase.from('program_days')
      .select('day_no, day_date, day_type, kcal_target, protein_target_g, exercise:exercises(code, name, category)')
      .order('day_no'),
    supabase.from('daily_scores').select('*').order('score_date'),
    supabase.from('day_logs')
      .select('log_date, weight_kg, waist_cm, chest_cm, arms_cm, steps, coffee_cups, water_l')
      .order('log_date'),
    supabase.from('profiles').select('*').maybeSingle(),
  ]);
  return { days: days ?? [], scores: scores ?? [], logs: logs ?? [], profile };
}

/** The meal library. Superseded v1 fasting meals are kept in the DB for
 *  comparison but are not something you'd cook from, so they're excluded. */
export async function loadMeals() {
  const data = await mealLibrary();
  return data.filter((m: any) => !(m.day_type === 'fasting' && m.version === 1));
}


// ============================================================ the gym program
/** Everything the Gym screen edits: the session library, the next fortnight of
 *  the plan, and the set/rest protocol those calorie estimates are built on. */
export async function loadGym() {
  const today = athensToday();
  const [{ data: exercises }, { data: days }, { data: w }, prof] = await Promise.all([
    supabase.from('exercises')
      .select('*, movements:exercise_movements(*)')
      .eq('archived', false)
      .order('name'),
    supabase.from('program_days')
      .select('day_no, day_date, day_type, exercise_id')
      .gte('day_date', today).order('day_date').limit(14),
    // estimates are per-kilo, so they follow your actual bodyweight down
    supabase.from('day_logs').select('weight_kg')
      .not('weight_kg', 'is', null).order('log_date', { ascending: false }).limit(1),
    profile(true),
  ]);

  // A forked session shares its code with the system row it came from. Yours
  // wins - showing both would let you edit a copy the plan no longer points at.
  const byCode = new Map<string, any>();
  for (const e of exercises ?? []) {
    const prev = byCode.get(e.code);
    if (!prev || (e.user_id && !prev.user_id)) byCode.set(e.code, e);
  }
  const library = [...byCode.values()].map((e) => ({
    ...e,
    movements: [...(e.movements ?? [])].sort((a: any, b: any) => a.order_index - b.order_index),
  }));

  const byId = new Map(library.map((e) => [e.id, e]));
  // ...but a day may still point at the system row we just hid behind a fork
  const rawById = new Map((exercises ?? []).map((e: any) => [e.id, e]));
  const plan = (days ?? []).map((d: any) => ({
    ...d,
    exercise: byId.get(d.exercise_id)
           ?? byCode.get(rawById.get(d.exercise_id)?.code ?? '')
           ?? null,
  }));

  const weightKg = Number(w?.[0]?.weight_kg ?? prof?.start_weight_kg ?? 88);
  return { library, plan, profile: prof, weightKg, today };
}

/** System sessions are shared by every account, so they cannot be edited in
 *  place. This hands back an id you own - forking on the first edit, and a
 *  no-op once you already have your own copy. */
export async function claimExercise(exerciseId: number): Promise<number> {
  const { data, error } = await supabase.rpc('fork_exercise', { p_exercise_id: exerciseId });
  if (error) throw error;
  return data as number;
}

export async function updateExercise(id: number, patch: Record<string, any>) {
  const clean = Object.fromEntries(
    Object.entries(patch).map(([k, v]) => [k, v === '' || v === undefined ? null : v]));
  const { error } = await supabase.from('exercises').update(clean).eq('id', id);
  if (error) throw error;
}

export async function saveMovement(exerciseId: number, row: Record<string, any>) {
  const { error } = await supabase.from('exercise_movements')
    .upsert({ exercise_id: exerciseId, ...row });
  if (error) throw error;
}

export async function createExercise(name: string, prof: any) {
  const { data: u } = await supabase.auth.getUser();
  const code = (name.replace(/[^a-zA-Z0-9]/g, '').toUpperCase().slice(0, 10) || 'CUSTOM')
             + '-' + Math.random().toString(36).slice(2, 6).toUpperCase();
  const { data, error } = await supabase.from('exercises').insert({
    user_id: u.user!.id, code, name, category: 'resistance',
    focus: '', duration_min: 60, work_met: 7.0, recovery_met: 2.5,
    duty_pct: null, epoc_factor: 1.10,
  }).select().single();
  if (error) throw error;
  return data;
}

/** scope: 'day' = just this one, 'weekday' = every future Tuesday (say),
 *  'all' = everything from this date forward. The past is a record, not a plan. */
export async function assignDay(
  date: string, exerciseId: number | null, scope: 'day' | 'weekday' | 'all') {
  const { data, error } = await supabase.rpc('set_day_exercise', {
    p_date: date, p_exercise_id: exerciseId, p_scope: scope });
  if (error) throw error;
  return data as number;
}

export async function saveProfile(patch: Record<string, any>) {
  const { data: u } = await supabase.auth.getUser();
  const { error } = await supabase.from('profiles').update(patch).eq('id', u.user!.id);
  if (error) throw error;
  _profile = null;
}

/** Set/rest seconds and session METs feed every past training estimate, so
 *  changing them has to reach back through the history that used them. */
export async function rescoreAll() {
  const { data, error } = await supabase.rpc('rescore_all');
  if (error) throw error;
  return data as number;
}
