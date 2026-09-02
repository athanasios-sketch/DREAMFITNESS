<script lang="ts">
  import { onMount } from 'svelte';
  import { athensToday, shiftDate, loadDay, toggleMeal, swapMeal, setPortion,
           saveMetrics, addSet, addExtra, deleteRow, isoWeekday, WEEKDAYS,
           sessionKcal } from '../lib/api';

  const TODAY = athensToday();
  let date = $state(TODAY);
  let d    = $state<any>(null);
  let busy = $state(false);
  let err  = $state('');
  let openMovement = $state<string | null>(null);
  let openMeal     = $state<number | null>(null);
  let swapFor      = $state<number | null>(null);
  let showMeasure  = $state(false);

  const load = async () => {
    err = '';
    try { d = await loadDay(date); }
    catch (e: any) { d = null; err = e?.message ?? 'Could not load this day.'; }
  };
  onMount(load);

  async function goto(iso: string) {
    date = iso; d = null; openMeal = null; openMovement = null; showMeasure = false;
    await load();
  }
  const go = (n: number) => goto(shiftDate(date, n));

  const eaten = $derived.by(() => {
    if (!d) return { p: 0, c: 0, f: 0, k: 0 };
    const t = { p: 0, c: 0, f: 0, k: 0 };
    for (const s of d.slots) if (s.log?.completed) {
      const q = Number(s.log.portion ?? 1);
      t.p += +s.meal.protein_g * q; t.c += +s.meal.carbs_g * q;
      t.f += +s.meal.fat_g * q;     t.k += +s.meal.kcal * q;
    }
    for (const x of d.extras) if (x.kind === 'food') {
      t.p += +x.protein_g; t.c += +x.carbs_g; t.f += +x.fat_g; t.k += +x.kcal;
    }
    return t;
  });

  const volume = $derived(d ? d.sets.reduce((a: number, s: any) => a + +s.volume_load, 0) : 0);

  /** Body measurements are a weekly ritual. Daily scale readings are mostly
   *  water and salt, and reading noise as progress is how people quit. */
  const measureDay = $derived(
    isoWeekday(date) === +(d?.profile?.measure_weekday ?? 3));
  const hasMeasurement = $derived(!!d?.log && ['weight_kg','waist_cm','chest_cm','arms_cm']
    .some((f) => d.log[f] != null));
  const measureOpen = $derived(showMeasure || measureDay || hasMeasurement);
  const nextMeasure = $derived(WEEKDAYS[(+(d?.profile?.measure_weekday ?? 3)) - 1]);

  const cups  = $derived(Number(d?.log?.coffee_cups ?? 0));
  const limit = $derived(Number(d?.profile?.coffee_limit_cups ?? 4));

  /** Fraction of the session actually under load: 45s sets against 2min rest
   *  is 27%, which is the whole reason an hour of lifting isn't an hour of work. */
  const duty = (ex: any) => {
    if (ex?.duty_pct != null) return +ex.duty_pct;
    const set = +(d?.profile?.set_seconds ?? 45), rest = +(d?.profile?.rest_seconds ?? 120);
    return set + rest > 0 ? set / (set + rest) : 1;
  };

  /** What the session is worth at the minutes currently logged. Mirrors
   *  public.session_kcal so the number moves as you type. */
  const trainKcal = $derived.by(() => {
    const ex = d?.programDay?.exercise;
    if (!ex) return 0;
    const mins = Number(d.log?.training_minutes ?? 0);
    if (!mins) return 0;
    if (ex.kcal_override != null) {
      return ex.duration_min > 0
        ? Math.round(+ex.kcal_override * (mins / ex.duration_min)) : +ex.kcal_override;
    }
    return Math.round(sessionKcal({
      minutes: mins,
      weightKg: Number(d.score?.detail?.bodyweight_kg ?? d.profile?.start_weight_kg ?? 88),
      workMet: +ex.work_met, recoveryMet: +ex.recovery_met, dutyPct: ex.duty_pct,
      setSeconds: +(d.profile?.set_seconds ?? 45),
      restSeconds: +(d.profile?.rest_seconds ?? 120), epoc: +ex.epoc_factor,
    }));
  });

  async function flip(slot: any) {
    if (busy) return; busy = true;
    try { await toggleMeal(date, slot, !slot.log?.completed); await load(); }
    finally { busy = false; }
  }

  async function doSwap(slot: any, mealId: number) {
    if (busy) return; busy = true;
    try { await swapMeal(date, slot, mealId); swapFor = null; await load(); }
    finally { busy = false; }
  }

  async function doPortion(slot: any, portion: number) {
    if (busy) return; busy = true;
    try { await setPortion(date, slot, portion); await load(); }
    finally { busy = false; }
  }

  /** Swap candidates: same course first, then the rest of the library. */
  function options(slot: any) {
    const all = d.meals ?? [];
    const rank = (m: any) => (m.slot === slot.planned.slot ? 0 : 1);
    return [...all].sort((a, b) => rank(a) - rank(b) || a.slot.localeCompare(b.slot));
  }

  let timers: Record<string, any> = {};
  function metric(field: string, value: any, delay = 600) {
    clearTimeout(timers[field]);
    timers[field] = setTimeout(async () => { await saveMetrics(date, { [field]: value }); await load(); }, delay);
  }
  async function bump(field: string, by: number, max = 99) {
    const next = Math.max(0, Math.min(max, +(Number(d.log?.[field] ?? 0) + by).toFixed(2)));
    await saveMetrics(date, { [field]: next }); await load();
  }

  // A set is reps x kilos, or a bodyweight rep count, or a block of time.
  // One form, three shapes.
  let sReps = $state(''), sWeight = $state(''), sRpe = $state('');
  let sMin  = $state(''), sKm = $state(''), sIncline = $state('');
  const clearSet = () => { sReps = sWeight = sRpe = sMin = sKm = sIncline = ''; };

  async function logSet(mv: any) {
    const time = mv.tracking === 'time';
    if (busy || (time ? !sMin : !sReps)) return;
    busy = true;
    try {
      const n = d.sets.filter((s: any) => s.movement_name === mv.name).length + 1;
      await addSet(date, d.programDay?.exercise?.id ?? null, {
        movement_name: mv.name, movement_id: mv.id, set_no: n,
        reps: time ? 0 : +sReps,
        weight_kg: mv.tracking === 'load' ? (+sWeight || 0) : 0,
        rpe: sRpe ? +sRpe : null,
        duration_sec: time ? Math.round(+sMin * 60) : null,
        distance_km:  time && sKm ? +sKm : null,
        incline_pct:  time && sIncline ? +sIncline : null,
      });
      clearSet();
      await load();
    } finally { busy = false; }
  }

  /** How a logged set reads back, in the units it was entered in. */
  function setLabel(s: any) {
    if (s.duration_sec) {
      const m = Math.round(s.duration_sec / 60);
      return s.distance_km ? `${m}min · ${+s.distance_km}km` : `${m}min`;
    }
    return +s.weight_kg > 0 ? `${s.reps}×${+s.weight_kg}kg` : `${s.reps} reps`;
  }

  // Off-plan food gets the full label, because "I'll paste the numbers from AI"
  // only works if there is somewhere to paste them.
  const BLANK = { name: '', amount: '', kcal: '', protein_g: '', carbs_g: '', fat_g: '',
                  sat_fat_g: '', fiber_g: '', sugar_g: '', sodium_mg: '',
                  minutes: '', kcal_burned: '' };
  let xOpen = $state(false), xKind = $state<'food'|'exercise'>('food');
  let x = $state({ ...BLANK });

  const num = (v: any) => (v === '' || v == null ? null : Number(v));

  async function saveExtra() {
    if (!x.name.trim() || busy) return; busy = true;
    try {
      await addExtra(date, xKind === 'food'
        ? { kind: 'food', name: x.name.trim(), amount: x.amount || null,
            kcal: num(x.kcal) ?? 0, protein_g: num(x.protein_g) ?? 0,
            carbs_g: num(x.carbs_g) ?? 0, fat_g: num(x.fat_g) ?? 0,
            sat_fat_g: num(x.sat_fat_g), fiber_g: num(x.fiber_g),
            sugar_g: num(x.sugar_g), sodium_mg: num(x.sodium_mg) }
        : { kind: 'exercise', name: x.name.trim(), amount: x.amount || null,
            duration_min: num(x.minutes), kcal_burned: num(x.kcal_burned) ?? 0 });
      x = { ...BLANK }; xOpen = false; await load();
    } finally { busy = false; }
  }

  const pct = (a: number, b: number) => Math.min(100, b ? (a / b) * 100 : 0);
  const n0 = (v: any) => Math.round(Number(v ?? 0)).toLocaleString();
  // 0.25 must read as 0.25, not 0.3 - the column now stores two decimals
  const L  = (v: any) => parseFloat(Number(v ?? 0).toFixed(2)).toString();
</script>

<header class="sticky top-0 z-30 border-b border-line bg-ink/90 px-5 pb-4 backdrop-blur
               pt-[calc(env(safe-area-inset-top)+1rem)]">
  <div class="flex items-center justify-between">
    <button onclick={() => go(-1)} aria-label="Previous day"
            class="rounded-lg px-3 py-1 text-muted hover:text-bone">&larr;</button>
    <div class="text-center">
      <p class="eyebrow">{d?.programDay ? `Day ${d.programDay.day_no} of 90` : 'Outside the program'}</p>
      <p class="font-display text-lg font-bold">
        {new Date(date + 'T12:00:00').toLocaleDateString('en-GB',
          { weekday: 'long', day: 'numeric', month: 'short' })}
      </p>
    </div>
    <button onclick={() => go(1)} aria-label="Next day"
            class="rounded-lg px-3 py-1 text-muted hover:text-bone">&rarr;</button>
  </div>
  {#if date !== TODAY}
    <button onclick={() => goto(TODAY)}
      class="mx-auto mt-2 block rounded-full border border-fast/40 px-3 py-1 text-xs text-fast">
      Back to today
    </button>
  {/if}
</header>

{#if err}
  <div class="p-8 text-center">
    <p class="text-sm text-warn">{err}</p>
    <button onclick={load} class="mt-3 rounded-lg border border-line px-4 py-2 text-sm">Try again</button>
  </div>
{:else if !d}
  <p class="p-8 text-center eyebrow animate-pulse">Loading</p>
{:else if !d.programDay}
  <p class="p-8 text-center text-muted">No program day here. Your 90 days run 2 Sep &rarr; 30 Nov.</p>
{:else}
  {@const pd = d.programDay}
  {@const fasting = pd.day_type === 'fasting'}
  {@const isRest = pd.exercise?.category === 'rest'}
  {@const sc = d.score}

  <div class="space-y-5 px-5 pt-5">

    <section class="panel p-5">
      <div class="flex items-start justify-between">
        <div>
          <span class="rounded-full border px-2.5 py-1 font-data text-[11px] uppercase tracking-widest
                       {fasting ? 'border-fast/40 text-fast' : 'border-fed/40 text-fed'}">
            {fasting ? 'Fasting' : 'Fed'}
          </span>
          <p class="mt-3 font-display text-2xl font-bold">{pd.exercise?.name ?? 'Rest'}</p>
          <p class="text-sm text-muted">{pd.exercise?.focus ?? 'Recovery'}</p>
        </div>
        <div class="text-right">
          <!-- a part-finished day always scores low; don't present it as final -->
          <p class="eyebrow">{date === TODAY ? 'So far' : 'Score'}</p>
          <p class="tnum text-4xl font-bold {sc ? 'text-peak' : 'text-muted/40'}">
            {sc ? Math.round(sc.total_score) : '--'}
          </p>
          {#if date === TODAY && sc}
            <p class="mt-0.5 text-[11px] text-muted">still counting</p>
          {/if}
        </div>
      </div>
    </section>

    <!-- energy in / out -->
    <section class="panel p-5">
      <p class="eyebrow">Energy</p>
      {#if sc?.burn_kcal}
        <div class="mt-3 flex items-baseline justify-between">
          <div><p class="text-xs text-muted">In</p>
               <p class="tnum text-2xl font-bold text-fed">{n0(sc.kcal_actual)}</p></div>
          <div class="text-center"><p class="text-xs text-muted">Out</p>
               <p class="tnum text-2xl font-bold text-fast">{n0(sc.burn_kcal)}</p></div>
          <div class="text-right"><p class="text-xs text-muted">Balance</p>
               <p class="tnum text-2xl font-bold {sc.energy_balance < 0 ? 'text-peak' : 'text-warn'}">
                 {sc.energy_balance > 0 ? '+' : ''}{n0(sc.energy_balance)}</p></div>
        </div>
        <p class="tnum mt-3 border-t border-line pt-3 text-xs text-muted">
          Resting {n0(sc.bmr_kcal)} · Walking {n0(sc.steps_kcal)} · Training {n0(sc.training_kcal)}
        </p>
      {:else}
        <p class="mt-2 text-sm text-muted">
          Add your steps and training below and this fills in.
        </p>
      {/if}
    </section>

    <!-- macros -->
    <section class="panel p-5">
      <p class="eyebrow">Intake</p>
      <div class="mt-4 space-y-3">
        {#each [['Protein', eaten.p, +pd.protein_target_g, 'g', true],
                ['Calories', eaten.k, pd.kcal_target, '', false],
                ['Carbs', eaten.c, +pd.carbs_target_g, 'g', false],
                ['Fat', eaten.f, +pd.fat_target_g, 'g', false]] as [label, val, tgt, unit, key]}
          <div>
            <div class="flex justify-between text-sm">
              <span class={key ? 'font-semibold text-bone' : 'text-muted'}>{label}</span>
              <span class="tnum {key ? 'text-bone' : 'text-muted'}">
                {Math.round(val as number)}<span class="text-muted">/{Math.round(tgt as number)}{unit}</span>
              </span>
            </div>
            <div class="mt-1.5 h-1.5 overflow-hidden rounded-full bg-raised">
              <div class="h-full rounded-full transition-all duration-500 {key ? 'bg-peak' : 'bg-muted/40'}"
                   style="width:{pct(val as number, tgt as number)}%"></div>
            </div>
          </div>
        {/each}
      </div>
    </section>

    <!-- meals: tick to eat, tap the name to cook -->
    <section>
      <p class="eyebrow mb-3">The plan &middot; {d.slots.length} meals</p>
      <div class="space-y-2">
        {#each d.slots as s}
          {@const done = !!s.log?.completed}
          {@const shown = openMeal === s.slot_index}
          {@const q = Number(s.log?.portion ?? 1)}
          <div class="panel overflow-hidden {done ? 'border-peak/40 bg-peak/5' : ''}">
            <div class="flex items-center gap-3 p-4">
              <button onclick={() => flip(s)} aria-label="Mark {s.meal.name} eaten"
                class="grid size-7 shrink-0 place-items-center rounded-md border-2 text-ink
                       {done ? 'border-peak bg-peak' : 'border-line'}">
                {#if done}<span class="text-sm font-bold">&check;</span>{/if}
              </button>
              <button onclick={() => (openMeal = shown ? null : s.slot_index)}
                class="min-w-0 flex-1 text-left">
                <span class="flex items-center gap-1.5">
                  <span class="truncate font-semibold">{s.meal.name}</span>
                  {#if q !== 1}<span class="tnum shrink-0 rounded bg-fed/15 px-1.5 text-[10px] text-fed">&times;{q}</span>{/if}
                </span>
                <span class="tnum block text-xs text-muted">
                  {Math.round(+s.meal.protein_g * q)}P &middot; {Math.round(+s.meal.carbs_g * q)}C
                  &middot; {Math.round(+s.meal.fat_g * q)}F &middot; {Math.round(+s.meal.kcal * q)} kcal
                </span>
                {#if s.swapped}
                  <span class="mt-0.5 block truncate text-[11px] text-fast">
                    swapped from {s.planned.name}
                  </span>
                {/if}
              </button>
              <span class="shrink-0 text-muted">{shown ? '−' : '+'}</span>
            </div>

            {#if shown}
              <div class="space-y-4 border-t border-line px-4 py-4">
                <div>
                  <p class="eyebrow">How much</p>
                  <div class="mt-1.5 flex gap-1.5">
                    {#each [0.5, 1, 1.5, 2] as v}
                      <button onclick={() => doPortion(s, v)}
                        class="tnum h-9 flex-1 rounded-md border text-xs transition
                          {q === v ? 'border-fed bg-fed/15 text-fed' : 'border-line text-muted'}"
                        >&times;{v}</button>
                    {/each}
                  </div>
                </div>

                <div>
                  <div class="flex items-center justify-between">
                    <p class="eyebrow">Ate something else?</p>
                    <button onclick={() => (swapFor = swapFor === s.slot_index ? null : s.slot_index)}
                      class="text-sm text-fast">{swapFor === s.slot_index ? 'Close' : 'Swap'}</button>
                  </div>
                  {#if swapFor === s.slot_index}
                    <div class="mt-2 max-h-64 space-y-1 overflow-y-auto rounded-lg border border-line p-1.5">
                      {#each options(s) as o}
                        <button onclick={() => doSwap(s, o.id)}
                          class="flex w-full items-center justify-between gap-2 rounded-md px-2.5 py-2
                                 text-left text-sm transition
                                 {o.id === s.meal.id ? 'bg-fast/15 text-fast' : 'hover:bg-raised'}">
                          <span class="min-w-0">
                            <span class="block truncate">{o.name}</span>
                            <span class="text-[10px] uppercase tracking-wider text-muted">{o.slot}</span>
                          </span>
                          <span class="tnum shrink-0 text-xs text-muted">
                            {+o.protein_g}P &middot; {o.kcal}
                          </span>
                        </button>
                      {/each}
                    </div>
                  {/if}
                </div>

                <div><p class="eyebrow">In it</p>
                     <p class="mt-1 text-sm leading-relaxed">{s.meal.ingredients}</p></div>
                {#if s.meal.steps?.length}
                  <div>
                    <p class="eyebrow">Method</p>
                    <ol class="mt-2 space-y-2">
                      {#each s.meal.steps as step, i}
                        <li class="flex gap-2.5 text-sm leading-relaxed">
                          <span class="tnum mt-0.5 shrink-0 text-xs text-fast">{i + 1}</span>
                          <span>{step}</span>
                        </li>
                      {/each}
                    </ol>
                  </div>
                {/if}
                {#if s.meal.tips?.length}
                  <div class="rounded-lg border-l-2 border-fed bg-fed/5 p-3">
                    <p class="eyebrow text-fed">Worth knowing</p>
                    <ul class="mt-1.5 space-y-1.5">
                      {#each s.meal.tips as tip}
                        <li class="text-sm leading-relaxed text-bone/80">{tip}</li>
                      {/each}
                    </ul>
                  </div>
                {/if}
              </div>
            {/if}
          </div>
        {/each}
      </div>
    </section>

    <!-- training: shown on rest days too, because a Sunday you trained anyway
         is data, and hiding the form is how that data gets lost -->
    {#if pd.exercise}
      {@const mv_list = [...(pd.exercise.movements ?? [])].sort((a, b) => a.order_index - b.order_index)}
      <section class="panel p-5">
        <div class="flex items-baseline justify-between">
          <p class="eyebrow">Training</p>
          {#if volume > 0}
            <p class="tnum text-sm text-peak">{n0(volume)} kg volume</p>
          {/if}
        </div>

        {#if isRest}
          <p class="mt-2 text-sm leading-relaxed text-muted">
            Rest day. Nothing is scheduled and you keep full marks for taking it &mdash;
            but if you trained anyway, put the minutes in and they still count.
          </p>
        {/if}

        <label class="mt-3 block">
          <span class="eyebrow">Minutes trained</span>
          <div class="mt-1.5 flex gap-2">
            <input value={d.log?.training_minutes ?? ''} inputmode="numeric"
              placeholder={String(pd.exercise.duration_min || 45)}
              oninput={(e) => metric('training_minutes', (e.currentTarget as HTMLInputElement).value)}
              class="tnum w-24 rounded-lg border border-line bg-ink px-3 py-2.5 text-bone" />
            {#each [...new Set([pd.exercise.duration_min, 30, 45, 60].filter(Boolean))].sort((a, b) => a - b) as m}
              <button onclick={() => metric('training_minutes', m, 0)}
                class="tnum flex-1 rounded-lg border text-sm
                  {d.log?.training_minutes === m ? 'border-fast text-fast' : 'border-line text-muted'}">
                {m}
              </button>
            {/each}
          </div>
        </label>

        {#if trainKcal > 0}
          <p class="tnum mt-2 text-xs text-muted">
            &asymp; <span class="text-fed">{n0(trainKcal)} kcal</span> at
            {Math.round((duty(pd.exercise)) * 100)}% time under load
          </p>
        {/if}

        {#if mv_list.length}
          <div class="mt-4 space-y-2">
            {#each mv_list as mv}
              {@const logged = d.sets.filter((s: any) => s.movement_name === mv.name)}
              {@const isTime = mv.tracking === 'time'}
              <div class="rounded-xl border border-line">
                <button onclick={() => { openMovement = openMovement === mv.name ? null : mv.name; clearSet(); }}
                        class="flex w-full items-center justify-between p-3 text-left">
                  <span class="min-w-0">
                    <span class="block text-sm font-semibold">{mv.name}</span>
                    <span class="tnum block text-xs text-muted">
                      {#if isTime}
                        {mv.target_sets ?? 1} &times; timed
                      {:else}
                        {mv.target_sets} &times; {mv.rep_low}-{mv.rep_high}
                        {#if mv.tracking === 'bodyweight'}<span> bodyweight</span>{/if}
                      {/if}
                      {#if logged.length}<span class="text-peak"> &middot; {logged.length} logged</span>{/if}
                    </span>
                  </span>
                  <span class="shrink-0 text-muted">{openMovement === mv.name ? '\u2212' : '+'}</span>
                </button>
                {#if logged.length}
                  <div class="flex flex-wrap gap-1.5 px-3 pb-3">
                    {#each logged as s}
                      <button onclick={async () => { await deleteRow('set_logs', s.id); await load(); }}
                        title="Remove set"
                        class="tnum rounded-md bg-raised px-2 py-1 text-xs text-muted hover:text-warn">
                        {setLabel(s)}
                      </button>
                    {/each}
                  </div>
                {/if}
                {#if openMovement === mv.name}
                  <div class="flex gap-2 border-t border-line p-3">
                    {#if isTime}
                      <input bind:value={sMin} inputmode="decimal" placeholder="min"
                        class="tnum w-full rounded-lg border border-line bg-ink px-3 py-2 text-sm" />
                      <input bind:value={sKm} inputmode="decimal" placeholder="km"
                        class="tnum w-full rounded-lg border border-line bg-ink px-3 py-2 text-sm" />
                      <input bind:value={sIncline} inputmode="decimal" placeholder="incl %"
                        class="tnum w-20 rounded-lg border border-line bg-ink px-3 py-2 text-sm" />
                    {:else}
                      <input bind:value={sReps} inputmode="numeric" placeholder="reps"
                        class="tnum w-full rounded-lg border border-line bg-ink px-3 py-2 text-sm" />
                      {#if mv.tracking === 'load'}
                        <input bind:value={sWeight} inputmode="decimal" placeholder="kg"
                          class="tnum w-full rounded-lg border border-line bg-ink px-3 py-2 text-sm" />
                      {/if}
                      <input bind:value={sRpe} inputmode="decimal" placeholder="rpe"
                        class="tnum w-20 rounded-lg border border-line bg-ink px-3 py-2 text-sm" />
                    {/if}
                    <button onclick={() => logSet(mv)}
                      class="shrink-0 rounded-lg bg-bone px-4 text-sm font-bold text-ink">Add</button>
                  </div>
                {/if}
              </div>
            {/each}
          </div>
        {:else if !isRest}
          <p class="mt-3 text-sm text-muted">{pd.exercise.focus}</p>
          <p class="tnum mt-1 text-xs text-muted">
            Target {pd.exercise.duration_min} min. Add the movements you actually do on the Gym tab.
          </p>
        {/if}
      </section>
    {/if}

    <!-- steps, water, coffee: the three you touch most, so they get real controls -->
    <section class="panel p-5">
      <div class="flex items-end justify-between">
        <div>
          <p class="eyebrow">Steps</p>
          <input value={d.log?.steps ?? ''} inputmode="numeric" placeholder="0"
            oninput={(e) => metric('steps', (e.currentTarget as HTMLInputElement).value)}
            class="tnum mt-1 w-32 rounded-lg border border-line bg-ink px-3 py-2.5 text-xl text-bone" />
        </div>
        <p class="tnum pb-3 text-sm text-muted">/ {n0(pd.steps_target)}</p>
      </div>
      <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-raised">
        <div class="h-full rounded-full bg-fast transition-all duration-500"
             style="width:{pct(+(d.log?.steps ?? 0), pd.steps_target)}%"></div>
      </div>

      <div class="mt-5 flex items-end justify-between">
        <div>
          <p class="eyebrow">Water</p>
          <p class="tnum mt-1 text-xl">{L(d.log?.water_l)}
            <span class="text-sm text-muted">/ {L(pd.water_target_l)} L</span></p>
        </div>
        <div class="flex gap-2">
          <button onclick={() => bump('water_l', -0.25)} aria-label="Remove 250ml"
            class="size-10 rounded-lg border border-line text-muted">&minus;</button>
          {#each [0.25, 0.5] as v}
            <button onclick={() => bump('water_l', v)}
              class="tnum h-10 rounded-lg border border-line px-3 text-sm text-bone">+{v * 1000}</button>
          {/each}
        </div>
      </div>
      <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-raised">
        <div class="h-full rounded-full bg-fast transition-all duration-500"
             style="width:{pct(+(d.log?.water_l ?? 0), +pd.water_target_l)}%"></div>
      </div>

      <!-- Coffee carries no calories worth counting. It is here because
           caffeine and sleep are the one pair worth being able to correlate. -->
      <div class="mt-5 flex items-end justify-between">
        <div>
          <p class="eyebrow">Coffee</p>
          <p class="tnum mt-1 text-xl">{L(cups)}
            <span class="text-sm text-muted">/ {L(limit)} cups</span></p>
        </div>
        <div class="flex gap-2">
          <button onclick={() => bump('coffee_cups', -1, 30)} aria-label="Remove a coffee"
            class="size-10 rounded-lg border border-line text-muted">&minus;</button>
          {#each [0.5, 1] as v}
            <button onclick={() => bump('coffee_cups', v, 30)}
              class="tnum h-10 rounded-lg border border-line px-3 text-sm text-bone">+{v}</button>
          {/each}
        </div>
      </div>
      <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-raised">
        <div class="h-full rounded-full transition-all duration-500
                    {cups > limit ? 'bg-warn' : 'bg-fed'}"
             style="width:{pct(cups, limit)}%"></div>
      </div>
      {#if cups > limit}
        <p class="mt-1.5 text-[11px] text-warn">
          Over your limit. Caffeine has a ~6 hour half-life &mdash; this is the sleep score
          you will pay tonight.
        </p>
      {/if}
    </section>

    <!-- recovery: asked every day, because it changes every day -->
    <section class="panel p-5">
      <p class="eyebrow">Recovery</p>
      <div class="mt-4 grid grid-cols-2 gap-4">
        <label class="block">
          <span class="eyebrow">Sleep (h)</span>
          <input value={d.log?.sleep_hours ?? ''} inputmode="decimal"
            oninput={(e) => metric('sleep_hours', (e.currentTarget as HTMLInputElement).value)}
            class="tnum mt-1 w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-bone" />
        </label>
        <div></div>
        {#each [['energy','Energy'], ['soreness','Soreness']] as [f,label]}
          <div>
            <span class="eyebrow">{label}</span>
            <div class="mt-1.5 flex gap-1">
              {#each [1,2,3,4,5] as n}
                <button onclick={() => metric(f as string, n, 0)}
                  class="tnum h-9 flex-1 rounded-md border text-xs transition
                    {d.log?.[f as string] === n ? 'border-fast bg-fast/15 text-fast' : 'border-line text-muted'}"
                  >{n}</button>
              {/each}
            </div>
          </div>
        {/each}
      </div>
      <label class="mt-4 block">
        <span class="eyebrow">Notes</span>
        <textarea rows="2" value={d.log?.notes ?? ''}
          oninput={(e) => metric('notes', (e.currentTarget as HTMLTextAreaElement).value)}
          placeholder="How did it go?"
          class="mt-1 w-full resize-none rounded-lg border border-line bg-ink px-3 py-2.5 text-sm
                 placeholder:text-muted/50"></textarea>
      </label>
    </section>

    <!-- measurements: weekly. A daily scale reading is mostly water and salt,
         and treating that noise as progress is how people talk themselves out
         of a plan that is working. -->
    <section class="panel p-5 {measureDay && !hasMeasurement ? 'border-fast/40' : ''}">
      <div class="flex items-center justify-between">
        <div>
          <p class="eyebrow {measureDay && !hasMeasurement ? 'text-fast' : ''}">Measurements</p>
          <p class="mt-1 text-xs text-muted">
            {#if hasMeasurement}
              Logged for this week.
            {:else if measureDay}
              Due today. First thing, before food or water.
            {:else}
              Weekly, every {nextMeasure}.
            {/if}
          </p>
        </div>
        {#if !measureOpen}
          <button onclick={() => (showMeasure = true)} class="shrink-0 text-sm text-fast">
            Log anyway
          </button>
        {/if}
      </div>

      {#if measureOpen}
        <div class="mt-4 grid grid-cols-2 gap-3">
          {#each [['weight_kg','Weight','kg'], ['waist_cm','Waist','cm'],
                  ['chest_cm','Chest','cm'], ['arms_cm','Arms','cm']] as [f,label,unit]}
            <label class="block">
              <span class="eyebrow">{label} ({unit})</span>
              <input value={d.log?.[f as string] ?? ''} inputmode="decimal"
                oninput={(e) => metric(f as string, (e.currentTarget as HTMLInputElement).value)}
                class="tnum mt-1 w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-bone" />
            </label>
          {/each}
        </div>
        <p class="mt-3 text-[11px] leading-relaxed text-muted">
          Same conditions every week or the number means nothing: same morning, after the
          toilet, before breakfast. Waist at the navel, relaxed, at the end of a normal breath.
        </p>
      {/if}
    </section>

    <!-- off plan: the full label, so pasted numbers have somewhere to land -->
    <section class="panel p-5">
      <div class="flex items-center justify-between">
        <p class="eyebrow">Off plan</p>
        <button onclick={() => (xOpen = !xOpen)} class="text-sm text-fast">
          {xOpen ? 'Cancel' : '+ Add'}
        </button>
      </div>

      {#if d.extras.length}
        <div class="mt-3 space-y-1.5">
          {#each d.extras as item}
            <div class="rounded-lg bg-raised px-3 py-2">
              <div class="flex items-center justify-between gap-2">
                <span class="min-w-0 truncate text-sm">
                  <span class="mr-2 font-data text-[10px] uppercase tracking-wider
                               {item.kind === 'food' ? 'text-fed' : 'text-fast'}">{item.kind}</span>{item.name}
                  {#if item.amount}<span class="text-muted"> · {item.amount}</span>{/if}
                </span>
                <span class="flex shrink-0 items-center gap-3">
                  <span class="tnum text-xs text-muted">
                    {item.kind === 'food' ? `${item.kcal} kcal` : `−${item.kcal_burned} kcal`}</span>
                  <button onclick={async () => { await deleteRow('extra_items', item.id); await load(); }}
                    aria-label="Remove" class="text-muted hover:text-warn">&times;</button>
                </span>
              </div>
              {#if item.kind === 'food'}
                <p class="tnum mt-0.5 text-[11px] text-muted">
                  {Math.round(+item.protein_g)}P &middot; {Math.round(+item.carbs_g)}C
                  &middot; {Math.round(+item.fat_g)}F
                  {#if item.fiber_g != null}&middot; {+item.fiber_g}g fibre{/if}
                  {#if item.sodium_mg != null}&middot; {Math.round(+item.sodium_mg)}mg Na{/if}
                </p>
              {:else if item.duration_min}
                <p class="tnum mt-0.5 text-[11px] text-muted">{item.duration_min} min</p>
              {/if}
            </div>
          {/each}
        </div>
      {/if}

      {#if xOpen}
        <div class="mt-4 space-y-2">
          <div class="flex gap-2">
            {#each ['food','exercise'] as k}
              <button onclick={() => (xKind = k as any)}
                class="flex-1 rounded-lg border py-2 text-sm capitalize
                  {xKind === k ? 'border-fast text-fast' : 'border-line text-muted'}">{k}</button>
            {/each}
          </div>

          <div class="flex gap-2">
            <input bind:value={x.name}
              placeholder={xKind === 'food' ? 'What did you eat?' : 'What did you do?'}
              class="min-w-0 flex-1 rounded-lg border border-line bg-ink px-3 py-2.5 text-sm" />
            <input bind:value={x.amount} placeholder={xKind === 'food' ? '200g' : '30 min'}
              class="w-24 shrink-0 rounded-lg border border-line bg-ink px-3 py-2.5 text-sm" />
          </div>

          {#if xKind === 'food'}
            <div class="grid grid-cols-4 gap-2">
              {#each [['kcal','kcal'], ['protein_g','protein'], ['carbs_g','carbs'], ['fat_g','fat'],
                      ['sat_fat_g','sat fat'], ['fiber_g','fibre'], ['sugar_g','sugar'],
                      ['sodium_mg','sodium']] as [f, label]}
                <label class="block">
                  <span class="eyebrow text-[9px]">{label}</span>
                  <input bind:value={x[f as keyof typeof x]} inputmode="decimal"
                    class="tnum mt-1 w-full rounded-lg border border-line bg-ink px-2 py-2 text-sm" />
                </label>
              {/each}
            </div>
            <p class="text-[11px] leading-relaxed text-muted">
              Only calories, protein, carbs and fat reach the score. The rest is
              logged so the pattern is there to read back later.
            </p>
          {:else}
            <div class="grid grid-cols-2 gap-2">
              <label class="block">
                <span class="eyebrow text-[9px]">minutes</span>
                <input bind:value={x.minutes} inputmode="numeric"
                  class="tnum mt-1 w-full rounded-lg border border-line bg-ink px-2 py-2 text-sm" />
              </label>
              <label class="block">
                <span class="eyebrow text-[9px]">kcal burned</span>
                <input bind:value={x.kcal_burned} inputmode="numeric"
                  class="tnum mt-1 w-full rounded-lg border border-line bg-ink px-2 py-2 text-sm" />
              </label>
            </div>
          {/if}

          <button onclick={saveExtra} disabled={busy || !x.name.trim()}
            class="w-full rounded-lg bg-bone py-3 text-sm font-bold text-ink disabled:opacity-30">
            Save
          </button>
        </div>
      {/if}
    </section>
  </div>
{/if}
