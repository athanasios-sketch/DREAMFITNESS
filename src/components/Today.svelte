<script lang="ts">
  import { onMount } from 'svelte';
  import { athensToday, shiftDate, loadDay, toggleMeal, saveMetrics,
           addSet, addExtra, deleteRow } from '../lib/api';

  let date  = $state(athensToday());
  let d     = $state<any>(null);
  let busy  = $state(false);
  let openMovement = $state<string | null>(null);

  const load = async () => { d = await loadDay(date); };
  onMount(load);

  const go = async (n: number) => { date = shiftDate(date, n); d = null; await load(); };

  // eaten so far = completed planned meals + off-plan food
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

  async function flip(slot: any) {
    if (busy) return; busy = true;
    try { await toggleMeal(date, slot, !slot.log?.completed); await load(); }
    finally { busy = false; }
  }

  let metricTimer: any;
  function metric(field: string, value: any) {
    clearTimeout(metricTimer);
    metricTimer = setTimeout(async () => { await saveMetrics(date, { [field]: value }); await load(); }, 600);
  }

  // set logger
  let sReps = $state(''), sWeight = $state(''), sRpe = $state('');
  async function logSet(movementName: string, movementId: number | null) {
    if (!sReps || busy) return; busy = true;
    try {
      const n = d.sets.filter((s: any) => s.movement_name === movementName).length + 1;
      await addSet(date, d.programDay?.exercise?.id ?? null, {
        movement_name: movementName, movement_id: movementId, set_no: n,
        reps: +sReps, weight_kg: +sWeight || 0, rpe: sRpe ? +sRpe : null,
      });
      sReps = ''; sWeight = ''; sRpe = ''; await load();
    } finally { busy = false; }
  }

  // extras
  let xOpen = $state(false), xKind = $state<'food'|'exercise'>('food');
  let xName = $state(''), xKcal = $state(''), xProt = $state(''), xBurn = $state('');
  async function saveExtra() {
    if (!xName.trim() || busy) return; busy = true;
    try {
      await addExtra(date, xKind === 'food'
        ? { kind: 'food', name: xName, kcal: +xKcal || 0, protein_g: +xProt || 0, carbs_g: 0, fat_g: 0 }
        : { kind: 'exercise', name: xName, kcal_burned: +xBurn || 0 });
      xName = ''; xKcal = ''; xProt = ''; xBurn = ''; xOpen = false; await load();
    } finally { busy = false; }
  }

  const pct = (a: number, b: number) => Math.min(100, b ? (a / b) * 100 : 0);
</script>

<header class="sticky top-0 z-30 border-b border-line bg-ink/90 px-5 py-4 backdrop-blur">
  <div class="flex items-center justify-between">
    <button onclick={() => go(-1)} aria-label="Previous day"
            class="rounded-lg px-3 py-1 text-muted hover:text-bone">&larr;</button>
    <div class="text-center">
      {#if d?.programDay}
        <p class="eyebrow">Day {d.programDay.day_no} of 90</p>
        <p class="font-display text-lg font-bold">
          {new Date(date + 'T12:00:00').toLocaleDateString('en-GB',
            { weekday: 'long', day: 'numeric', month: 'short' })}
        </p>
      {:else}
        <p class="eyebrow">Outside the program</p>
        <p class="font-display text-lg font-bold">{date}</p>
      {/if}
    </div>
    <button onclick={() => go(1)} aria-label="Next day"
            class="rounded-lg px-3 py-1 text-muted hover:text-bone">&rarr;</button>
  </div>
</header>

{#if !d}
  <p class="p-8 text-center eyebrow animate-pulse">Loading</p>
{:else if !d.programDay}
  <p class="p-8 text-center text-muted">No program day here. Your 90 days run 2 Sep &rarr; 30 Nov.</p>
{:else}
  {@const pd = d.programDay}
  {@const fasting = pd.day_type === 'fasting'}
  {@const tone = fasting ? 'fast' : 'fed'}

  <div class="space-y-5 px-5 pt-5">

    <!-- day type + score -->
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
          <p class="eyebrow">Score</p>
          <p class="tnum text-4xl font-bold {d.score ? 'text-peak' : 'text-muted/40'}">
            {d.score ? Math.round(d.score.total_score) : '--'}
          </p>
        </div>
      </div>
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
              <div class="h-full rounded-full transition-all duration-500
                          {key ? 'bg-peak' : `bg-${tone}/60`}"
                   style="width:{pct(val as number, tgt as number)}%"></div>
            </div>
          </div>
        {/each}
      </div>
    </section>

    <!-- meals -->
    <section>
      <p class="eyebrow mb-3">The plan &middot; {d.slots.length} meals</p>
      <div class="space-y-2">
        {#each d.slots as s}
          {@const done = !!s.log?.completed}
          <button onclick={() => flip(s)}
            class="panel flex w-full items-center gap-3 p-4 text-left transition
                   {done ? 'border-peak/40 bg-peak/5' : 'hover:border-muted/40'}">
            <span class="grid size-6 shrink-0 place-items-center rounded-md border-2 text-ink
                         {done ? 'border-peak bg-peak' : 'border-line'}">
              {#if done}<span class="text-xs font-bold">&check;</span>{/if}
            </span>
            <span class="min-w-0 flex-1">
              <span class="block truncate font-semibold {done ? 'text-bone' : 'text-bone/90'}">
                {s.meal.name}
              </span>
              <span class="tnum block text-xs text-muted">
                {s.meal.protein_g}P &middot; {s.meal.carbs_g}C &middot; {s.meal.fat_g}F &middot; {s.meal.kcal} kcal
              </span>
            </span>
          </button>
        {/each}
      </div>
    </section>

    <!-- training -->
    {#if pd.exercise && pd.exercise.category !== 'rest'}
      <section class="panel p-5">
        <div class="flex items-baseline justify-between">
          <p class="eyebrow">Training</p>
          {#if volume > 0}
            <p class="tnum text-sm text-peak">{Math.round(volume).toLocaleString()} kg volume</p>
          {/if}
        </div>

        {#if pd.exercise.movements?.length}
          <div class="mt-4 space-y-2">
            {#each pd.exercise.movements.sort((a: any, b: any) => a.order_index - b.order_index) as mv}
              {@const logged = d.sets.filter((s: any) => s.movement_name === mv.name)}
              <div class="rounded-xl border border-line">
                <button onclick={() => openMovement = openMovement === mv.name ? null : mv.name}
                        class="flex w-full items-center justify-between p-3 text-left">
                  <span>
                    <span class="block text-sm font-semibold">{mv.name}</span>
                    <span class="tnum block text-xs text-muted">
                      {mv.target_sets} &times; {mv.rep_low}-{mv.rep_high}
                      {#if logged.length}<span class="text-peak"> &middot; {logged.length} logged</span>{/if}
                    </span>
                  </span>
                  <span class="text-muted">{openMovement === mv.name ? '−' : '+'}</span>
                </button>

                {#if logged.length}
                  <div class="flex flex-wrap gap-1.5 px-3 pb-3">
                    {#each logged as s}
                      <button onclick={async () => { await deleteRow('set_logs', s.id); await load(); }}
                        title="Remove set"
                        class="tnum rounded-md bg-raised px-2 py-1 text-xs text-muted hover:text-warn">
                        {s.reps}&times;{+s.weight_kg}kg
                      </button>
                    {/each}
                  </div>
                {/if}

                {#if openMovement === mv.name}
                  <div class="flex gap-2 border-t border-line p-3">
                    <input bind:value={sReps} inputmode="numeric" placeholder="reps"
                      class="tnum w-full rounded-lg border border-line bg-ink px-3 py-2 text-sm" />
                    <input bind:value={sWeight} inputmode="decimal" placeholder="kg"
                      class="tnum w-full rounded-lg border border-line bg-ink px-3 py-2 text-sm" />
                    <input bind:value={sRpe} inputmode="decimal" placeholder="rpe"
                      class="tnum w-20 rounded-lg border border-line bg-ink px-3 py-2 text-sm" />
                    <button onclick={() => logSet(mv.name, mv.id)}
                      class="shrink-0 rounded-lg bg-bone px-4 text-sm font-bold text-ink">Add</button>
                  </div>
                {/if}
              </div>
            {/each}
          </div>
        {:else}
          <p class="mt-3 text-sm text-muted">{pd.exercise.focus}</p>
          <p class="mt-1 tnum text-xs text-muted">
            {pd.exercise.duration_min} min &middot; ~{pd.exercise.est_kcal} kcal
          </p>
        {/if}
      </section>
    {/if}

    <!-- metrics -->
    <section class="panel p-5">
      <p class="eyebrow">Body &amp; recovery</p>
      <div class="mt-4 grid grid-cols-2 gap-3">
        {#each [['weight_kg','Weight','kg','decimal'], ['steps','Steps','','numeric'],
                ['sleep_hours','Sleep','h','decimal'], ['water_l','Water','L','decimal'],
                ['waist_cm','Waist','cm','decimal'], ['chest_cm','Chest','cm','decimal']] as [f,label,unit,mode]}
          <label class="block">
            <span class="eyebrow">{label}{unit ? ` (${unit})` : ''}</span>
            <input value={d.log?.[f as string] ?? ''} inputmode={mode}
              oninput={(e) => metric(f as string, (e.currentTarget as HTMLInputElement).value)}
              class="tnum mt-1 w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-bone" />
          </label>
        {/each}
      </div>

      <div class="mt-4 grid grid-cols-2 gap-4">
        {#each [['energy','Energy'], ['soreness','Soreness']] as [f,label]}
          <div>
            <span class="eyebrow">{label}</span>
            <div class="mt-1.5 flex gap-1">
              {#each [1,2,3,4,5] as n}
                <button onclick={() => metric(f as string, n)}
                  class="tnum h-9 flex-1 rounded-md border text-xs transition
                    {d.log?.[f as string] === n
                      ? 'border-fast bg-fast/15 text-fast' : 'border-line text-muted'}">{n}</button>
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
          class="mt-1 w-full resize-none rounded-lg border border-line bg-ink px-3 py-2.5
                 text-sm placeholder:text-muted/50"></textarea>
      </label>
    </section>

    <!-- extras -->
    <section class="panel p-5">
      <div class="flex items-center justify-between">
        <p class="eyebrow">Off plan</p>
        <button onclick={() => (xOpen = !xOpen)} class="text-sm text-fast">
          {xOpen ? 'Cancel' : '+ Add'}
        </button>
      </div>

      {#if d.extras.length}
        <div class="mt-3 space-y-1.5">
          {#each d.extras as x}
            <div class="flex items-center justify-between rounded-lg bg-raised px-3 py-2 text-sm">
              <span class="truncate">
                <span class="mr-2 font-data text-[10px] uppercase tracking-wider
                             {x.kind === 'food' ? 'text-fed' : 'text-fast'}">{x.kind}</span>
                {x.name}
              </span>
              <span class="flex shrink-0 items-center gap-3">
                <span class="tnum text-xs text-muted">
                  {x.kind === 'food' ? `${x.kcal} kcal` : `−${x.kcal_burned} kcal`}
                </span>
                <button onclick={async () => { await deleteRow('extra_items', x.id); await load(); }}
                  aria-label="Remove" class="text-muted hover:text-warn">&times;</button>
              </span>
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
          <input bind:value={xName} placeholder={xKind === 'food' ? 'What did you eat?' : 'What did you do?'}
            class="w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-sm" />
          <div class="flex gap-2">
            {#if xKind === 'food'}
              <input bind:value={xKcal} inputmode="numeric" placeholder="kcal"
                class="tnum w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-sm" />
              <input bind:value={xProt} inputmode="numeric" placeholder="protein g"
                class="tnum w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-sm" />
            {:else}
              <input bind:value={xBurn} inputmode="numeric" placeholder="kcal burned"
                class="tnum w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-sm" />
            {/if}
            <button onclick={saveExtra} class="shrink-0 rounded-lg bg-bone px-5 text-sm font-bold text-ink">
              Save
            </button>
          </div>
        </div>
      {/if}
    </section>
  </div>
{/if}
