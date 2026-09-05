<script lang="ts">
  import { onMount } from 'svelte';
  import { athensToday, shiftDate, weekStart, isoWeekday,
           loadWeek, setTravelDays, shoppingList, byAisle } from '../lib/api';

  const TODAY = athensToday();
  let from  = $state(weekStart(TODAY));
  let w     = $state<any>(null);
  let busy  = $state(false);
  let err   = $state('');
  let view  = $state<'shop' | 'days'>('shop');
  let ticked = $state<Record<string, boolean>>({});

  const load = async () => {
    try { w = await loadWeek(from); err = ''; }
    catch (e: any) { w = null; err = e?.message ?? 'Could not load the week.'; }
  };

  /** A program that starts next Monday leaves the CURRENT week empty, and an
   *  empty first screen reads as a broken one. Land on the first week that has
   *  days in it instead. */
  onMount(async () => {
    await load();
    const start = w?.profile?.program_start_date;
    if (w && !w.days.length && start && start > from) {
      from = weekStart(start);
      await load();
    }
  });

  async function goto(iso: string) { from = iso; w = null; await load(); }

  const list = $derived(w ? shoppingList(w) : { home: [], road: [] });
  const travelDays = $derived((w?.days ?? []).filter((d: any) => d.day_type === 'travel'));
  const homeDays   = $derived((w?.days ?? []).filter((d: any) => d.day_type !== 'travel'));
  const pack = $derived(list.road.filter((l: any) => l.packable));
  const buyThere = $derived(list.road.filter((l: any) => !l.packable));

  /** The plates a travel day names, deduplicated - what he is actually
   *  ordering, as opposed to the grams underneath them. */
  const roadMeals = $derived.by(() => {
    const seen = new Map<string, any>();
    for (const d of travelDays)
      for (const p of d.planned ?? []) if (!seen.has(p.meal.code)) seen.set(p.meal.code, p.meal);
    return [...seen.values()];
  });

  async function flip(d: any) {
    if (busy) return; busy = true;
    try { await setTravelDays([d.day_date], d.day_type !== 'travel'); await load(); }
    catch (e: any) { err = e?.message ?? 'Could not change that day.'; }
    finally { busy = false; }
  }

  /** Mon-Fri in one tap, because that is the week he actually has. Already all
   *  five? Then the button clears them - the same tap, read backwards. */
  const weekdayDates = $derived((w?.days ?? [])
    .filter((d: any) => isoWeekday(d.day_date) <= 5).map((d: any) => d.day_date));
  const allAway = $derived(weekdayDates.length > 0 &&
    weekdayDates.every((iso: string) =>
      w.days.find((d: any) => d.day_date === iso)?.day_type === 'travel'));

  async function flipWeek() {
    if (busy || !weekdayDates.length) return; busy = true;
    try { await setTravelDays(weekdayDates, !allAway); await load(); }
    catch (e: any) { err = e?.message ?? 'Could not change those days.'; }
    finally { busy = false; }
  }

  const dayName = (iso: string) =>
    new Date(iso + 'T12:00:00').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric' });
  const range = (a: string, b: string) => {
    const f = (iso: string, opts: any) => new Date(iso + 'T12:00:00').toLocaleDateString('en-GB', opts);
    return `${f(a, { day: 'numeric', month: 'short' })} – ${f(b, { day: 'numeric', month: 'short' })}`;
  };
  const n0 = (v: any) => Math.round(Number(v ?? 0)).toLocaleString();
  const key = (l: any) => from + ':' + l.name;
</script>

<header class="px-5 pb-2 pt-[calc(env(safe-area-inset-top)+1.5rem)]">
  <p class="eyebrow">One trip to the supermarket</p>
  <h1 class="font-display text-3xl font-extrabold tracking-tight">The week</h1>
  <p class="mt-2 text-sm leading-relaxed text-muted">
    Everything the next seven days need, added up per ingredient. Days you are
    away are costed separately &mdash; you do not buy those on Saturday.
  </p>
</header>

<div class="sticky top-0 z-30 border-b border-line bg-ink/95 px-5 pb-3 backdrop-blur
            pt-[calc(env(safe-area-inset-top)+0.75rem)]">
  <div class="flex items-center justify-between gap-2">
    <button onclick={() => goto(shiftDate(from, -7))} aria-label="Previous week"
      class="rounded-lg px-2 py-1 text-muted hover:text-bone">&larr;</button>
    <div class="text-center">
      <p class="text-sm font-semibold">{range(from, shiftDate(from, 6))}</p>
      {#if from !== weekStart(TODAY)}
        <button onclick={() => goto(weekStart(TODAY))} class="text-[11px] text-fast">this week</button>
      {:else}
        <p class="eyebrow text-[9px]">this week</p>
      {/if}
    </div>
    <button onclick={() => goto(shiftDate(from, 7))} aria-label="Next week"
      class="rounded-lg px-2 py-1 text-muted hover:text-bone">&rarr;</button>
  </div>
  <div class="mt-3 flex gap-2">
    {#each [['shop', 'Shopping list'], ['days', 'The days']] as [k, label]}
      <button onclick={() => (view = k as any)}
        class="rounded-full border px-3.5 py-1.5 text-xs font-medium transition
          {view === k ? 'border-bone bg-bone/10 text-bone' : 'border-line text-muted'}"
        >{label}</button>
    {/each}
  </div>
</div>

{#if err}
  <div class="mx-5 mt-4 rounded-xl border border-warn/40 bg-warn/10 p-4">
    <p class="text-sm text-warn">{err}</p>
    <button onclick={() => { err = ''; load(); }} class="mt-2 text-sm underline">Try again</button>
  </div>
{/if}

{#if !w}
  <p class="p-8 text-center eyebrow animate-pulse">Loading</p>
{:else if !w.days.length}
  <p class="p-8 text-center text-muted">No program days in this week.</p>
{:else if view === 'days'}
  <!-- ── which days you are away ───────────────────────────────────────── -->
  <div class="space-y-5 px-5 pt-5 pb-4">
    <section class="panel p-5">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="eyebrow">Away</p>
          <p class="mt-1 text-xs leading-relaxed text-muted">
            Tap a day to move it on or off the road. A travel day swaps to the
            supermarket menu, gains a hotel breakfast, and drops the eating
            window &mdash; there is a buffet at 08:00 and no reason to walk past it.
          </p>
        </div>
        <button onclick={flipWeek} disabled={busy}
          class="shrink-0 rounded-lg border px-3 py-1.5 text-xs
                 {allAway ? 'border-muted/50 text-muted' : 'border-fast/50 text-fast'}">
          {allAway ? 'Clear Mon–Fri' : 'Away Mon–Fri'}
        </button>
      </div>

      <div class="mt-4 space-y-1.5">
        {#each w.days as d}
          {@const away = d.day_type === 'travel'}
          {@const rest = d.exercise?.category === 'rest'}
          <button onclick={() => flip(d)} disabled={busy}
            class="flex w-full items-center gap-3 rounded-xl border p-3 text-left
                   {away ? 'border-muted/40 bg-raised/40' : 'border-line'}">
            <span class="w-1 self-stretch rounded-full {away ? 'bg-muted' : 'bg-fed'}"></span>
            <span class="min-w-0 flex-1">
              <span class="flex items-baseline gap-2">
                <span class="text-sm font-semibold">{dayName(d.day_date)}</span>
                {#if d.day_date === TODAY}<span class="eyebrow text-[9px] text-fast">today</span>{/if}
                {#if away}<span class="eyebrow text-[9px] text-muted">away</span>{/if}
              </span>
              <span class="block truncate text-xs text-muted">
                {rest ? 'Rest — walking only' : (d.exercise?.name ?? 'Nothing scheduled')}
                &middot; {d.planned.length} meals
              </span>
            </span>
            <span class="tnum shrink-0 text-right text-xs text-muted">
              {n0(d.menu_kcal)}<br />
              <span class="text-[10px]">of {n0(d.kcal_target)}</span>
            </span>
          </button>
        {/each}
      </div>
    </section>
  </div>
{:else}
  <!-- ── the list ──────────────────────────────────────────────────────── -->
  <div class="space-y-6 px-5 pt-5 pb-4">
    <p class="text-xs text-muted">
      {homeDays.length} day{homeDays.length === 1 ? '' : 's'} cooking at home
      {#if travelDays.length}&middot; {travelDays.length} away{/if}
      {#if list.home.length}&middot; {list.home.length} things to buy{/if}
    </p>

    {#if !list.home.length}
      <p class="panel p-5 text-sm text-muted">
        Every day this week is a travel day, so there is nothing to buy for the
        kitchen. What to take with you, and what to pick up on the road, is below.
      </p>
    {/if}

    {#each byAisle(list.home) as g}
      <section>
        <p class="eyebrow mb-2">{g.label}</p>
        <div class="panel divide-y divide-line">
          {#each g.items as l}
            <button onclick={() => (ticked[key(l)] = !ticked[key(l)])}
              class="flex w-full items-center gap-3 p-3 text-left">
              <span class="grid size-6 shrink-0 place-items-center rounded-md border-2 text-ink
                           {ticked[key(l)] ? 'border-peak bg-peak' : 'border-line'}">
                {#if ticked[key(l)]}<span class="text-xs font-bold">&check;</span>{/if}
              </span>
              <span class="min-w-0 flex-1 text-sm {ticked[key(l)] ? 'text-muted line-through' : ''}">
                {l.name}
              </span>
              <span class="tnum shrink-0 text-sm {ticked[key(l)] ? 'text-muted/50' : 'text-bone'}">
                {l.label}
              </span>
            </button>
          {/each}
        </div>
      </section>
    {/each}

    {#if travelDays.length}
      <section>
        <p class="eyebrow mb-2">Pack it</p>
        <p class="mb-2 text-[11px] leading-relaxed text-muted">
          These keep for a month in a bag. Buying psyllium in a town you do not
          know is a treasure hunt, and buying it five times is five tubs.
        </p>
        <div class="panel divide-y divide-line">
          {#each pack as l}
            <button onclick={() => (ticked[key(l)] = !ticked[key(l)])}
              class="flex w-full items-center gap-3 p-3 text-left">
              <span class="grid size-6 shrink-0 place-items-center rounded-md border-2 text-ink
                           {ticked[key(l)] ? 'border-peak bg-peak' : 'border-line'}">
                {#if ticked[key(l)]}<span class="text-xs font-bold">&check;</span>{/if}
              </span>
              <span class="min-w-0 flex-1 text-sm {ticked[key(l)] ? 'text-muted line-through' : ''}">{l.name}</span>
              <span class="tnum shrink-0 text-sm text-bone">{l.label}</span>
            </button>
          {/each}
        </div>
      </section>

      <section>
        <p class="eyebrow mb-2">Buy it there</p>
        <p class="mb-2 text-[11px] leading-relaxed text-muted">
          Fresh, and in any supermarket in the country. These are the totals for all
          {travelDays.length} day{travelDays.length === 1 ? '' : 's'} &mdash; you are buying a day
          at a time, so divide by {travelDays.length} and buy that.
        </p>
        <div class="panel divide-y divide-line">
          {#each buyThere as l}
            <div class="flex items-center gap-3 p-3">
              <span class="min-w-0 flex-1 text-sm">{l.name}</span>
              <span class="tnum shrink-0 text-sm text-muted">{l.label}</span>
            </div>
          {/each}
        </div>
      </section>

      <section>
        <p class="eyebrow mb-2">What you are ordering</p>
        <div class="space-y-2">
          {#each roadMeals as m}
            <div class="panel p-4">
              <div class="flex items-baseline justify-between gap-2">
                <p class="text-sm font-semibold">{m.name}</p>
                <p class="tnum shrink-0 text-xs text-muted">{n0(m.kcal)} kcal</p>
              </div>
              <p class="mt-1 text-xs uppercase tracking-wider text-muted">{m.slot}</p>
            </div>
          {/each}
        </div>
      </section>
    {/if}
  </div>
{/if}
