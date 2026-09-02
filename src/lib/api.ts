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

  // the whole library is 19 rows; fetch once so swaps resolve without a round trip
  const { data: library } = await supabase.from('meals').select('*').order('slot');

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

  return { programDay: pd, log, slots, planned, sets, extras, score, meals };
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
    supabase.from('day_logs').select('log_date, weight_kg, waist_cm, chest_cm, arms_cm, steps')
      .order('log_date'),
    supabase.from('profiles').select('*').maybeSingle(),
  ]);
  return { days: days ?? [], scores: scores ?? [], logs: logs ?? [], profile };
}

/** The meal library. Superseded v1 fasting meals are kept in the DB for
 *  comparison but are not something you'd cook from, so they're excluded. */
export async function loadMeals() {
  const { data } = await supabase
    .from('meals')
    .select('*')
    .order('slot').order('day_type').order('code');
  return (data ?? []).filter((m: any) => !(m.day_type === 'fasting' && m.version === 1));
}
