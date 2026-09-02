<script lang="ts">
  import { onMount } from 'svelte';
  import { loadMeals } from '../lib/api';

  let meals  = $state<any[]>([]);
  let filter = $state<'all' | 'regular' | 'fasting'>('all');
  let open   = $state<number | null>(null);

  onMount(async () => { meals = await loadMeals(); });

  const ORDER = ['breakfast', 'lunch', 'snack', 'dinner'];
  /** 'any' items - oats, honey, the milks - belong to every day, so they have to
   *  survive both filters. Hiding them under "Fasting" is how you forget the
   *  side you are allowed to add. */
  const shown = $derived(
    meals.filter((m) => filter === 'all' || m.day_type === filter || m.day_type === 'any'));

  const grouped = $derived(
    ORDER.map((slot) => ({ slot, items: shown.filter((m) => m.slot === slot) }))
         .filter((g) => g.items.length)
  );

  /** Protein per 100 kcal. On a cut this is the number that decides a swap:
   *  it tells you which meals buy the most protein for the calorie budget. */
  const density = (m: any) => (+m.protein_g / +m.kcal) * 100;

  const best = $derived(shown.length ? Math.max(...shown.map(density)) : 0);

  /** Amounts you can push around without saving anything. The plan is a
   *  starting point - you rarely have exactly 240g of chicken in the fridge,
   *  and the only useful answer to "I have 180" is what it does to the day. */
  /*  Held as the RAW STRING, not a number: parsing on every keystroke means an
   *  emptied field snaps back to 0 and you cannot retype it. */
  let edits = $state<Record<number, string>>({});

  function toggle(id: number) {
    open  = open === id ? null : id;
    edits = {};                     // a newly opened meal starts from its plan
  }

  const ROLE: Record<string, string> = {
    protein: 'bg-peak', carb: 'bg-fed', fat: 'bg-warn',
    veg: 'bg-fast', produce: 'bg-fast/50', extra: 'bg-muted',
  };

  const rawOf    = (it: any) => edits[it.id] ?? String(+it.amount);
  const amountOf = (it: any) => Math.max(0, +rawOf(it) || 0);
  /*  Typing 240 back over 240 is not a change. Compare values, not presence. */
  const changedOf = (it: any) => edits[it.id] != null && amountOf(it) !== +it.amount;
  const dirty = (m: any) => (m.items ?? []).some(changedOf);
  const part = (it: any) => {
    const s = amountOf(it) / 100;
    return { kcal: +it.kcal_100 * s, p: +it.protein_100 * s, c: +it.carbs_100 * s,
             f: +it.fat_100 * s, fib: +it.fiber_100 * s,
             veg: it.is_veg ? amountOf(it) : 0 };
  };
  const totals = (m: any) => (m.items ?? []).reduce((a: any, it: any) => {
    const x = part(it);
    return { kcal: a.kcal + x.kcal, p: a.p + x.p, c: a.c + x.c,
             f: a.f + x.f, fib: a.fib + x.fib, veg: a.veg + x.veg };
  }, { kcal: 0, p: 0, c: 0, f: 0, fib: 0, veg: 0 });

</script>

<header class="px-5 pb-2 pt-[calc(env(safe-area-inset-top)+1.5rem)]">
  <p class="eyebrow">Your kitchen</p>
  <h1 class="font-display text-3xl font-extrabold tracking-tight">Meals</h1>
  <p class="mt-2 text-sm leading-relaxed text-muted">
    Every meal in the program, down to the gram. Change an amount and the totals
    follow &mdash; nothing is saved, so it is safe to ask what-if.
  </p>
</header>

<div class="sticky top-0 z-30 border-b border-line bg-ink/95 px-5 pb-3 backdrop-blur
            pt-[calc(env(safe-area-inset-top)+0.75rem)]">
  <div class="flex gap-2">
    {#each [['all', 'All'], ['regular', 'Fed days'], ['fasting', 'Fasting']] as [key, label]}
      <button onclick={() => (filter = key as any)}
        class="rounded-full border px-3.5 py-1.5 text-xs font-medium transition
          {filter === key
            ? key === 'fasting' ? 'border-fast bg-fast/15 text-fast'
              : key === 'regular' ? 'border-fed bg-fed/15 text-fed'
              : 'border-bone bg-bone/10 text-bone'
            : 'border-line text-muted'}">{label}</button>
    {/each}
  </div>
</div>

<div class="space-y-7 px-5 pt-5 pb-4">
  {#each grouped as g}
    <section>
      <p class="eyebrow mb-3">{g.slot}</p>
      <div class="space-y-2">
        {#each g.items as m}
          {@const fasting = m.day_type === 'fasting'}
          {@const anyDay  = m.day_type === 'any'}
          {@const isOpen = open === m.id}
          {@const d = density(m)}
          <div class="panel overflow-hidden {isOpen ? 'border-muted/40' : ''}">
            <button onclick={() => toggle(m.id)}
              class="flex w-full items-start gap-3 p-4 text-left">
              <span class="mt-1 size-2 shrink-0 rounded-full
                           {anyDay ? 'bg-muted' : fasting ? 'bg-fast' : 'bg-fed'}"
                    title={anyDay ? 'Any day' : fasting ? 'Fasting day' : 'Fed day'}></span>
              <span class="min-w-0 flex-1">
                <span class="flex items-baseline justify-between gap-2">
                  <span class="truncate font-semibold">{m.name}</span>
                  <span class="tnum shrink-0 text-sm text-muted">{m.kcal}<span class="text-xs"> kcal</span></span>
                </span>
                <span class="tnum mt-1 block text-xs text-muted">
                  <span class="text-peak">{+m.protein_g}P</span> · {+m.carbs_g}C · {+m.fat_g}F
                  {#if d >= best - 0.4}
                    <span class="ml-1.5 rounded bg-peak/15 px-1.5 py-0.5 text-[10px] text-peak">
                      best protein value
                    </span>
                  {/if}
                </span>
              </span>
              <span class="mt-0.5 shrink-0 text-muted">{isOpen ? '−' : '+'}</span>
            </button>

            {#if isOpen}
              <div class="space-y-4 border-t border-line px-4 py-4">
                {#if m.equipment}
                  <div class="flex flex-wrap gap-3 text-[11px] text-muted">
                    <span class="rounded bg-raised px-2 py-1">{m.equipment}</span>
                    {#if m.prep_min}<span class="tnum rounded bg-raised px-2 py-1">{m.prep_min} min prep</span>{/if}
                    {#if m.cook_min}<span class="tnum rounded bg-raised px-2 py-1">{m.cook_min} min cook</span>{/if}
                  </div>
                {/if}

                <div>
                  <div class="flex items-baseline justify-between gap-2">
                    <p class="eyebrow">In it</p>
                    {#if dirty(m)}
                      <button onclick={() => (edits = {})} class="eyebrow text-fast">Reset</button>
                    {/if}
                  </div>

                  {#if m.items?.length}
                    {@const t = totals(m)}
                    <div class="mt-2 space-y-1.5">
                      {#each m.items as it}
                        {@const x = part(it)}
                        {@const changed = changedOf(it)}
                        <div class="rounded-lg bg-raised/60 px-3 py-2">
                          <div class="flex items-center gap-2">
                            <span class="size-1.5 shrink-0 rounded-full {ROLE[it.role] ?? 'bg-muted'}"
                                  title={it.role}></span>
                            <span class="min-w-0 flex-1 truncate text-sm">{it.name}</span>
                            <input type="number" min="0" step="5" inputmode="decimal"
                              value={rawOf(it)}
                              oninput={(e) => (edits = { ...edits, [it.id]: e.currentTarget.value })}
                              aria-label="{it.name} amount in {it.unit}"
                              class="tnum w-16 rounded border bg-ink px-1.5 py-1 text-right text-xs
                                     {changed ? 'border-fast text-fast' : 'border-line'}" />
                            <span class="w-4 text-[11px] text-muted">{it.unit}</span>
                          </div>
                          <p class="tnum mt-1 pl-3.5 text-[11px] text-muted">
                            {Math.round(x.kcal)} kcal &middot;
                            <span class="text-peak">{x.p.toFixed(1)}P</span> &middot;
                            {x.c.toFixed(1)}C &middot; {x.f.toFixed(1)}F{#if x.fib >= 0.5}
                              &middot; {x.fib.toFixed(1)} fibre{/if}
                          </p>
                          {#if it.note}
                            <p class="mt-1 pl-3.5 text-[11px] leading-relaxed text-muted/70">{it.note}</p>
                          {/if}
                        </div>
                      {/each}
                    </div>

                    {@const isDirty = dirty(m)}
                    <div class="mt-3 rounded-lg border p-3
                                {isDirty ? 'border-fast/40 bg-fast/5' : 'border-line'}">
                      <div class="flex items-baseline justify-between gap-2">
                        <p class="eyebrow {isDirty ? 'text-fast' : ''}">
                          {isDirty ? 'As you have it' : 'Meal total'}</p>
                        {#if isDirty}
                          {@const dk = t.kcal - +m.kcal}
                          <p class="tnum text-[11px] {dk > 0 ? 'text-warn' : 'text-peak'}">
                            {dk > 0 ? '+' : ''}{Math.round(dk)} kcal vs plan
                          </p>
                        {/if}
                      </div>
                      <div class="mt-2 grid grid-cols-5 gap-1 text-center">
                        {#each [['kcal', Math.round(t.kcal)], ['protein', t.p.toFixed(0)],
                                ['carbs', t.c.toFixed(0)], ['fat', t.f.toFixed(0)],
                                ['fibre', t.fib.toFixed(0)]] as [label, val]}
                          <div>
                            <p class="tnum text-sm font-semibold">{val}</p>
                            <p class="text-[9px] uppercase tracking-wider text-muted">{label}</p>
                          </div>
                        {/each}
                      </div>
                      {#if t.veg > 0}
                        <p class="tnum mt-2.5 border-t border-line pt-2.5 text-[11px] text-muted">
                          {Math.round(t.veg)}g of the day's 400g vegetable floor
                        </p>
                      {/if}
                    </div>
                  {:else}
                    <p class="mt-1.5 text-sm leading-relaxed">{m.ingredients}</p>
                  {/if}
                </div>

                <div>
                  <p class="eyebrow">Method</p>
                  {#if m.steps?.length}
                    <ol class="mt-2 space-y-2.5">
                      {#each m.steps as step, i}
                        <li class="flex gap-3 text-sm leading-relaxed">
                          <span class="tnum mt-0.5 shrink-0 text-xs text-fast">{i + 1}</span>
                          <span>{step}</span>
                        </li>
                      {/each}
                    </ol>
                  {:else}
                    <p class="mt-1.5 text-sm leading-relaxed text-muted">{m.instructions}</p>
                  {/if}
                </div>

                {#if m.tips?.length}
                  <div class="rounded-lg border-l-2 border-fed bg-fed/5 py-3 pl-3 pr-3">
                    <p class="eyebrow text-fed">Worth knowing</p>
                    <ul class="mt-2 space-y-2">
                      {#each m.tips as tip}
                        <li class="text-sm leading-relaxed text-bone/80">{tip}</li>
                      {/each}
                    </ul>
                  </div>
                {/if}

                <div class="flex gap-4 border-t border-line pt-3">
                  <span class="tnum text-xs text-muted">
                    {d.toFixed(1)}<span class="text-[10px]"> g protein / 100 kcal</span>
                  </span>
                  <span class="tnum text-xs text-muted">
                    {((+m.fat_g * 9 / +m.kcal) * 100).toFixed(0)}<span class="text-[10px]">% from fat</span>
                  </span>
                </div>
              </div>
            {/if}
          </div>
        {/each}
      </div>
    </section>
  {/each}

  {#if !meals.length}
    <p class="py-12 text-center eyebrow animate-pulse">Loading</p>
  {/if}
</div>
