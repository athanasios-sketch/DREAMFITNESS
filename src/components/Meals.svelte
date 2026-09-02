<script lang="ts">
  import { onMount } from 'svelte';
  import { loadMeals } from '../lib/api';

  let meals  = $state<any[]>([]);
  let filter = $state<'all' | 'regular' | 'fasting'>('all');
  let open   = $state<number | null>(null);

  onMount(async () => { meals = await loadMeals(); });

  const ORDER = ['breakfast', 'lunch', 'snack', 'dinner'];
  const shown = $derived(meals.filter((m) => filter === 'all' || m.day_type === filter));

  const grouped = $derived(
    ORDER.map((slot) => ({ slot, items: shown.filter((m) => m.slot === slot) }))
         .filter((g) => g.items.length)
  );

  /** Protein per 100 kcal. On a cut this is the number that decides a swap:
   *  it tells you which meals buy the most protein for the calorie budget. */
  const density = (m: any) => (+m.protein_g / +m.kcal) * 100;

  const best = $derived(shown.length ? Math.max(...shown.map(density)) : 0);
</script>

<header class="px-5 pb-2 pt-[calc(env(safe-area-inset-top)+1.5rem)]">
  <p class="eyebrow">Your kitchen</p>
  <h1 class="font-display text-3xl font-extrabold tracking-tight">Meals</h1>
  <p class="mt-2 text-sm leading-relaxed text-muted">
    Every meal in the program, with what goes in and how to cook it.
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
          {@const isOpen = open === m.id}
          {@const d = density(m)}
          <div class="panel overflow-hidden {isOpen ? 'border-muted/40' : ''}">
            <button onclick={() => (open = isOpen ? null : m.id)}
              class="flex w-full items-start gap-3 p-4 text-left">
              <span class="mt-1 size-2 shrink-0 rounded-full {fasting ? 'bg-fast' : 'bg-fed'}"
                    title={fasting ? 'Fasting day' : 'Fed day'}></span>
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
                  <p class="eyebrow">In it</p>
                  <p class="mt-1.5 text-sm leading-relaxed">{m.ingredients}</p>
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
