<script lang="ts">
  import { onMount } from 'svelte';
  import { loadProgram, athensToday } from '../lib/api';

  let { signOut, onOpenToday } = $props<{ signOut: () => void; onOpenToday: () => void }>();

  let p = $state<any>(null);
  const today = athensToday();
  onMount(async () => { p = await loadProgram(); });

  const KCAL_PER_KG = 7700;

  const byDate  = $derived(new Map((p?.scores ?? []).map((s: any) => [s.score_date, s])));
  const elapsed = $derived((p?.days ?? []).filter((d: any) => d.day_date <= today));
  const scored  = $derived(elapsed.map((d: any) => byDate.get(d.day_date)).filter(Boolean));
  const todayDay = $derived((p?.days ?? []).find((d: any) => d.day_date === today));
  const remaining = $derived(Math.max(0, 90 - elapsed.length));

  const mean = (xs: number[]) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;

  /** EWMA of daily score. a=0.1 -> ~7-day half-life: last week weighs most. */
  const momentum = $derived.by(() => {
    const xs = scored.map((s: any) => +s.total_score);
    if (!xs.length) return null;
    let e = xs[0];
    for (const v of xs.slice(1)) e = 0.1 * v + 0.9 * e;
    return e;
  });

  /** Reliability = mean − 0.5σ over the trailing 14 days. Ranks a steady 75
   *  above alternating 100/50, because consistency is what finishes 90 days. */
  const reliability = $derived.by(() => {
    const xs = scored.slice(-14).map((s: any) => +s.total_score);
    if (xs.length < 2) return null;
    const m = mean(xs)!;
    const sd = Math.sqrt(mean(xs.map((v) => (v - m) ** 2))!);
    return Math.max(0, m - 0.5 * sd);
  });

  /** Streak with freeze tokens: one earned per 7 days scoring >=70, spent
   *  automatically on a miss. One bad day shouldn't erase forty good ones. */
  const streak = $derived.by(() => {
    let run = 0, freezes = 0, best = 0, good = 0;
    for (const d of elapsed) {
      const s = byDate.get(d.day_date)?.total_score;
      if (s != null && +s >= 70) { run++; good++; if (good % 7 === 0) freezes++; }
      else if (freezes > 0) freezes--;
      else run = 0;
      best = Math.max(best, run);
    }
    return { run, freezes, best };
  });

  /** Where the points are actually going. This is the actionable one. */
  const pillars = $derived.by(() => {
    if (!scored.length) return null;
    return [
      ['Nutrition', mean(scored.map((s: any) => +s.nutrition_score))!, 35],
      ['Training',  mean(scored.map((s: any) => +s.training_score))!,  30],
      ['Recovery',  mean(scored.map((s: any) => +s.recovery_score))!,  20],
      ['Movement',  mean(scored.map((s: any) => +s.movement_score))!,  15],
    ].sort((a, b) => (a[1] as number) - (b[1] as number));
  });

  /** Weight: EWMA-smoothed, then least-squares slope over the last 21 points.
   *  Daily scale readings are mostly water; never show a day-over-day delta. */
  const weight = $derived.by(() => {
    const w = (p?.logs ?? []).filter((l: any) => l.weight_kg != null)
                .map((l: any) => ({ d: l.log_date, kg: +l.weight_kg }));
    if (!w.length) return null;
    let e = w[0].kg; const sm = [{ ...w[0], ewma: e }];
    for (const r of w.slice(1)) { e = 0.25 * r.kg + 0.75 * e; sm.push({ ...r, ewma: e }); }
    const tail = sm.slice(-21);
    let perWeek: number | null = null;
    if (tail.length >= 4) {
      const t0 = Date.parse(tail[0].d);
      const xs = tail.map((r) => (Date.parse(r.d) - t0) / 86400000);
      const ys = tail.map((r) => r.ewma);
      const n = xs.length, sx = xs.reduce((a, b) => a + b, 0), sy = ys.reduce((a, b) => a + b, 0);
      const sxy = xs.reduce((a, x, i) => a + x * ys[i], 0), sxx = xs.reduce((a, x) => a + x * x, 0);
      const den = n * sxx - sx * sx;
      if (den !== 0) perWeek = ((n * sxy - sx * sy) / den) * 7;
    }
    return { series: sm, latest: sm.at(-1)!, perWeek, start: +(p?.profile?.start_weight_kg ?? w[0].kg) };
  });

  /** Sparkline over the smoothed series. */
  const spark = $derived.by(() => {
    const s = weight?.series;
    if (!s || s.length < 3) return null;
    const ys = s.map((r: any) => r.ewma);
    const lo = Math.min(...ys), hi = Math.max(...ys), span = hi - lo || 1;
    return ys.map((y, i) =>
      `${(i / (ys.length - 1)) * 100},${28 - ((y - lo) / span) * 24}`).join(' ');
  });

  const projected = $derived(
    weight?.perWeek != null ? weight.latest.ewma + (weight.perWeek * remaining) / 7 : null);

  /** Adaptive TDEE = mean intake + energy drawn from tissue. */
  const tdee = $derived.by(() => {
    if (!weight?.perWeek) return null;
    const k = scored.slice(-21).map((s: any) => s.kcal_actual).filter((v: any) => v != null).map(Number);
    if (k.length < 7) return null;
    return mean(k)! - (weight.perWeek / 7) * KCAL_PER_KG;
  });

  const avgBalance = $derived.by(() => {
    const b = scored.map((s: any) => s.energy_balance).filter((v: any) => v != null).map(Number);
    return b.length ? mean(b) : null;
  });

  const avgProtein = $derived.by(() => {
    const x = scored.map((s: any) => s.protein_actual_g).filter((v: any) => v != null).map(Number);
    return x.length ? mean(x) : null;
  });

  const waist = $derived.by(() => {
    const xs = (p?.logs ?? []).filter((l: any) => l.waist_cm != null);
    return xs.length ? { first: +xs[0].waist_cm, last: +xs.at(-1).waist_cm } : null;
  });

  const volumeTrend = $derived.by(() => {
    const xs = scored.filter((s: any) => +s.volume_load > 0).map((s: any) => +s.volume_load);
    if (xs.length < 4) return null;
    const h = Math.floor(xs.length / 2);
    const a = mean(xs.slice(0, h))!, b = mean(xs.slice(h))!;
    return a ? ((b - a) / a) * 100 : null;
  });

  function cell(d: any) {
    const s = byDate.get(d.day_date)?.total_score;
    if (d.day_date === today) return 'bg-bone';
    if (d.day_date > today) return d.day_type === 'fasting' ? 'bg-fast/12' : 'bg-fed/12';
    if (s == null) return 'bg-raised';
    const v = +s;
    return v >= 85 ? 'bg-peak' : v >= 70 ? 'bg-peak/65' : v >= 50 ? 'bg-fed/70' : 'bg-warn/70';
  }

  const lead = $derived.by(() => {
    if (!p?.days?.length) return 0;
    return (new Date(p.days[0].day_date + 'T12:00:00').getDay() + 6) % 7;
  });

  const f = (n: any, d = 1) => n == null ? '--' : Number(n).toFixed(d);
  const n0 = (n: any) => n == null ? '--' : Math.round(Number(n)).toLocaleString();
</script>

<header class="flex items-start justify-between px-5 pb-2 pt-6">
  <div>
    <p class="eyebrow">90-day body recomp</p>
    <h1 class="font-display text-3xl font-extrabold tracking-tight">DREAMFITNESS</h1>
  </div>
  <button onclick={signOut} class="eyebrow hover:text-bone">Sign out</button>
</header>

{#if !p}
  <p class="p-8 text-center eyebrow animate-pulse">Loading</p>
{:else}
  <div class="space-y-5 px-5 pt-3">

    <!-- what today actually asks of you -->
    {#if todayDay}
      {@const fasting = todayDay.day_type === 'fasting'}
      <button onclick={onOpenToday}
        class="panel w-full p-5 text-left transition hover:border-fast/50">
        <div class="flex items-start justify-between">
          <div class="min-w-0">
            <p class="eyebrow">Today &middot; Day {todayDay.day_no}</p>
            <p class="mt-2 flex items-center gap-2">
              <span class="rounded-full border px-2 py-0.5 font-data text-[10px] uppercase tracking-widest
                           {fasting ? 'border-fast/40 text-fast' : 'border-fed/40 text-fed'}">
                {fasting ? 'Fasting' : 'Fed'}
              </span>
            </p>
            <p class="mt-2 truncate font-display text-xl font-bold">
              {todayDay.exercise?.name ?? 'Rest'}
            </p>
            <p class="tnum mt-1 text-xs text-muted">
              {n0(todayDay.kcal_target)} kcal &middot; {f(todayDay.protein_target_g, 0)}g protein &middot; 5 meals
            </p>
          </div>
          <span class="shrink-0 pt-1 text-fast">&rarr;</span>
        </div>
      </button>
    {/if}

    <!-- SIGNATURE: the whole program at once, Mon-Sun so fasting days stripe -->
    <section class="panel p-5">
      <div class="flex items-baseline justify-between">
        <p class="eyebrow">Day {elapsed.length} of 90</p>
        <p class="tnum text-xs text-muted">{remaining} to go</p>
      </div>

      <div class="mt-4 grid grid-cols-7 gap-1.5" role="img"
           aria-label="{scored.length} of {elapsed.length} elapsed days logged">
        {#each Array(lead) as _}<div></div>{/each}
        {#each p.days as d}
          <div title="Day {d.day_no} · {d.day_date} · {d.day_type} · {d.exercise?.code ?? ''}"
               class="aspect-square rounded-[3px] {cell(d)}
                      {d.day_date === today ? 'ring-2 ring-bone ring-offset-2 ring-offset-panel' : ''}"></div>
        {/each}
      </div>

      <div class="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-[11px] text-muted">
        <span class="flex items-center gap-1.5"><i class="size-2.5 rounded-[2px] bg-peak"></i>Strong</span>
        <span class="flex items-center gap-1.5"><i class="size-2.5 rounded-[2px] bg-fed/70"></i>Partial</span>
        <span class="flex items-center gap-1.5"><i class="size-2.5 rounded-[2px] bg-warn/70"></i>Missed</span>
        <span class="flex items-center gap-1.5"><i class="size-2.5 rounded-[2px] bg-fast/25"></i>Fasting ahead</span>
        <span class="flex items-center gap-1.5"><i class="size-2.5 rounded-[2px] bg-fed/25"></i>Fed ahead</span>
      </div>
    </section>

    {#if !scored.length}
      <!-- day one: say what to do, not "--" -->
      <section class="panel border-fast/30 p-5">
        <p class="eyebrow text-fast">Starting out</p>
        <p class="mt-2 text-sm leading-relaxed">
          Nothing is scored yet. Weigh in first thing tomorrow morning and tick meals
          as you eat them &mdash; momentum, weight trend and your real TDEE all build
          from that.
        </p>
        <p class="tnum mt-3 text-xs text-muted">
          Seed estimate until then: 3,020 kcal maintenance &middot; 88.0 kg start &middot; target ~80 kg
        </p>
      </section>
    {:else}
      <section class="grid grid-cols-2 gap-3">
        <div class="panel p-5">
          <p class="eyebrow">Momentum</p>
          <p class="tnum mt-1 text-4xl font-bold text-peak">{n0(momentum)}</p>
          <p class="mt-1 text-xs text-muted">7-day weighted</p>
        </div>
        <div class="panel p-5">
          <p class="eyebrow">Reliability</p>
          <p class="tnum mt-1 text-4xl font-bold {reliability == null ? 'text-muted/40' : 'text-fast'}">
            {n0(reliability)}</p>
          <p class="mt-1 text-xs text-muted">Consistency-adjusted</p>
        </div>
      </section>

      <section class="panel flex items-center justify-between p-5">
        <div>
          <p class="eyebrow">Streak</p>
          <p class="tnum mt-1 text-3xl font-bold">{streak.run}<span class="text-base text-muted"> days</span></p>
          {#if streak.best > streak.run}
            <p class="tnum mt-0.5 text-[11px] text-muted">best {streak.best}</p>
          {/if}
        </div>
        <div class="text-right">
          <p class="eyebrow">Freezes</p>
          <p class="tnum mt-1 text-lg">{'●'.repeat(streak.freezes) || '—'}</p>
          <p class="mt-0.5 text-[11px] text-muted">1 per 7 strong days</p>
        </div>
      </section>

      {#if pillars}
        <section class="panel p-5">
          <p class="eyebrow">Where the points go</p>
          <p class="mt-1 text-xs text-muted">Weakest first &mdash; this is what to fix.</p>
          <div class="mt-4 space-y-3">
            {#each pillars as [label, val, w]}
              <div>
                <div class="flex justify-between text-sm">
                  <span class="text-muted">{label} <span class="text-[10px]">({w}%)</span></span>
                  <span class="tnum">{n0(val)}</span>
                </div>
                <div class="mt-1.5 h-1.5 overflow-hidden rounded-full bg-raised">
                  <div class="h-full rounded-full transition-all duration-500
                              {(val as number) >= 80 ? 'bg-peak' : (val as number) >= 60 ? 'bg-fed' : 'bg-warn'}"
                       style="width:{val}%"></div>
                </div>
              </div>
            {/each}
          </div>
        </section>
      {/if}
    {/if}

    <!-- recomp: the scale alone can't tell fat from muscle -->
    <section class="panel p-5">
      <p class="eyebrow">Recomposition signals</p>
      <p class="mt-1 text-xs text-muted">Flat weight + shrinking waist + rising volume = it's working.</p>
      <div class="mt-4 space-y-3">
        {#each [
          ['Weight trend', weight?.perWeek == null ? '--' : `${weight.perWeek > 0 ? '+' : ''}${f(weight.perWeek, 2)} kg/wk`, weight?.perWeek != null && weight.perWeek < 0],
          ['Waist', waist == null ? '--' : `${(waist.last - waist.first) > 0 ? '+' : ''}${f(waist.last - waist.first)} cm`, waist != null && waist.last < waist.first],
          ['Volume load', volumeTrend == null ? '--' : `${volumeTrend > 0 ? '+' : ''}${f(volumeTrend, 0)}%`, volumeTrend != null && volumeTrend > 0],
          ['Avg protein', avgProtein == null ? '--' : `${f(avgProtein, 0)} g`, avgProtein != null && avgProtein >= 195],
        ] as [label, val, good]}
          <div class="flex items-center justify-between border-b border-line pb-3 last:border-0 last:pb-0">
            <span class="text-sm text-muted">{label}</span>
            <span class="tnum text-sm font-semibold
                         {val === '--' ? 'text-muted/40' : good ? 'text-peak' : 'text-bone'}">{val}</span>
          </div>
        {/each}
      </div>
    </section>

    <!-- weight -->
    <section class="panel p-5">
      <div class="flex items-start justify-between">
        <div>
          <p class="eyebrow">Weight</p>
          <p class="tnum mt-1 text-3xl font-bold">
            {weight ? f(weight.latest.ewma) : f(p.profile?.start_weight_kg)}<span class="text-base text-muted"> kg</span>
          </p>
          <p class="mt-0.5 text-[11px] text-muted">{weight ? 'Smoothed trend' : 'Starting weight'}</p>
        </div>
        {#if spark}
          <svg viewBox="0 0 100 30" preserveAspectRatio="none" class="h-14 w-32" aria-hidden="true">
            <polyline points={spark} fill="none" stroke="var(--color-fast)"
                      stroke-width="1.5" vector-effect="non-scaling-stroke"
                      stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        {/if}
      </div>
      {#if projected != null}
        <p class="tnum mt-3 border-t border-line pt-3 text-xs text-muted">
          At this rate, day 90 lands near <span class="text-bone">{f(projected)} kg</span>
        </p>
      {/if}
    </section>

    <!-- energy -->
    <section class="panel p-5 mb-4">
      <p class="eyebrow">Adaptive TDEE</p>
      {#if tdee}
        <p class="tnum mt-1 text-4xl font-bold text-fed">{n0(tdee)}</p>
        <p class="mt-1 text-xs text-muted">Measured from your real intake and weight trend.</p>
      {:else}
        <p class="tnum mt-1 text-4xl font-bold text-muted/40">--</p>
        <p class="mt-1 text-xs leading-relaxed text-muted">
          Needs ~14 days of weight and intake. Seed estimate is
          <span class="tnum text-bone">3,020 kcal</span> from Mifflin-St Jeor.
        </p>
      {/if}
      {#if avgBalance != null}
        <p class="tnum mt-3 border-t border-line pt-3 text-xs text-muted">
          Average daily balance
          <span class={avgBalance < 0 ? 'text-peak' : 'text-warn'}>
            {avgBalance > 0 ? '+' : ''}{n0(avgBalance)} kcal
          </span>
        </p>
      {/if}
    </section>
  </div>
{/if}
