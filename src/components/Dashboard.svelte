<script lang="ts">
  import { onMount } from 'svelte';
  import { loadProgram, athensToday } from '../lib/api';

  let { signOut, onOpenToday } = $props<{ signOut: () => void; onOpenToday: () => void }>();

  let p = $state<any>(null);
  const today = athensToday();
  onMount(async () => { p = await loadProgram(); });

  const KCAL_PER_KG = 7700;

  // ── scores keyed by date, only for days that have already happened
  const byDate = $derived(new Map((p?.scores ?? []).map((s: any) => [s.score_date, s])));
  const elapsed = $derived((p?.days ?? []).filter((d: any) => d.day_date <= today));

  /** EWMA of daily score. a=0.1 -> ~7-day half-life: last week weighs most. */
  const momentum = $derived.by(() => {
    const xs = elapsed.map((d: any) => byDate.get(d.day_date)?.total_score).filter((v: any) => v != null);
    if (!xs.length) return null;
    let e = +xs[0];
    for (const v of xs.slice(1)) e = 0.1 * +v + 0.9 * e;
    return e;
  });

  /** Reliability = mean − 0.5σ over the trailing 14 days.
   *  Deliberately ranks a steady 75 above alternating 100/50. Consistency is the game. */
  const reliability = $derived.by(() => {
    const xs = elapsed.slice(-14).map((d: any) => byDate.get(d.day_date)?.total_score)
                      .filter((v: any) => v != null).map(Number);
    if (xs.length < 2) return null;
    const m = xs.reduce((a, b) => a + b, 0) / xs.length;
    const sd = Math.sqrt(xs.reduce((a, b) => a + (b - m) ** 2, 0) / xs.length);
    return Math.max(0, m - 0.5 * sd);
  });

  /** Streak with freeze tokens: 1 earned per 7 days scoring >=70, spent
   *  automatically on a miss. One bad day shouldn't erase forty good ones. */
  const streak = $derived.by(() => {
    let run = 0, freezes = 0, best = 0, good = 0;
    for (const d of elapsed) {
      const s = byDate.get(d.day_date)?.total_score;
      if (s != null && +s >= 70) {
        run++; good++; if (good % 7 === 0) freezes++;
      } else if (freezes > 0) { freezes--; }
      else { run = 0; }
      best = Math.max(best, run);
    }
    return { run, freezes, best };
  });

  /** Weight: EWMA-smoothed trend + least-squares slope over the last 21 points.
   *  Daily scale readings are mostly water; never show a day-over-day delta. */
  const weight = $derived.by(() => {
    const w = (p?.logs ?? []).filter((l: any) => l.weight_kg != null)
                .map((l: any) => ({ d: l.log_date, kg: +l.weight_kg }));
    if (!w.length) return null;
    let e = w[0].kg; const sm = [{ ...w[0], ewma: e }];
    for (const r of w.slice(1)) { e = 0.25 * r.kg + 0.75 * e; sm.push({ ...r, ewma: e }); }
    const tail = sm.slice(-21);
    let perWeek = null;
    if (tail.length >= 4) {
      const t0 = Date.parse(tail[0].d);
      const xs = tail.map((r) => (Date.parse(r.d) - t0) / 86400000);
      const ys = tail.map((r) => r.ewma);
      const n = xs.length, sx = xs.reduce((a, b) => a + b, 0), sy = ys.reduce((a, b) => a + b, 0);
      const sxy = xs.reduce((a, x, i) => a + x * ys[i], 0), sxx = xs.reduce((a, x) => a + x * x, 0);
      const denom = n * sxx - sx * sx;
      if (denom !== 0) perWeek = ((n * sxy - sx * sy) / denom) * 7;
    }
    return { series: sm, latest: sm.at(-1)!, perWeek, start: +(p?.profile?.start_weight_kg ?? w[0].kg) };
  });

  /** Adaptive TDEE = mean intake + energy drawn from tissue.
   *  Replaces the Mifflin-St Jeor guess with your actual metabolism. */
  const tdee = $derived.by(() => {
    if (!weight?.perWeek) return null;
    const days = elapsed.slice(-21).map((d: any) => byDate.get(d.day_date)?.kcal_actual)
                        .filter((v: any) => v != null).map(Number);
    if (days.length < 7) return null;
    const mean = days.reduce((a, b) => a + b, 0) / days.length;
    return mean - (weight.perWeek / 7) * KCAL_PER_KG;
  });

  const waist = $derived.by(() => {
    const xs = (p?.logs ?? []).filter((l: any) => l.waist_cm != null);
    return xs.length ? { first: +xs[0].waist_cm, last: +xs.at(-1).waist_cm } : null;
  });

  const volumeTrend = $derived.by(() => {
    const xs = (p?.scores ?? []).filter((s: any) => +s.volume_load > 0).map((s: any) => +s.volume_load);
    if (xs.length < 4) return null;
    const h = Math.floor(xs.length / 2);
    const a = xs.slice(0, h).reduce((x, y) => x + y, 0) / h;
    const b = xs.slice(h).reduce((x, y) => x + y, 0) / (xs.length - h);
    return a ? ((b - a) / a) * 100 : null;
  });

  const logged = $derived(elapsed.filter((d: any) => byDate.has(d.day_date)).length);

  // grid cell colour: score if logged, otherwise the day's own rhythm
  function cell(d: any) {
    const s = byDate.get(d.day_date)?.total_score;
    if (d.day_date === today) return 'bg-bone';
    if (d.day_date > today) return d.day_type === 'fasting' ? 'bg-fast/12' : 'bg-fed/12';
    if (s == null) return 'bg-raised';
    const v = +s;
    if (v >= 85) return 'bg-peak';
    if (v >= 70) return 'bg-peak/65';
    if (v >= 50) return 'bg-fed/70';
    return 'bg-warn/70';
  }

  // pad so column 1 is always Monday -> Wed/Fri become vertical stripes
  const lead = $derived.by(() => {
    if (!p?.days?.length) return 0;
    const dow = new Date(p.days[0].day_date + 'T12:00:00').getDay(); // 0=Sun
    return (dow + 6) % 7;
  });

  const f1 = (n: number | null | undefined, d = 1) => n == null ? '--' : n.toFixed(d);
</script>

<header class="flex items-center justify-between px-5 pb-2 pt-6">
  <div>
    <p class="eyebrow">90-day body recomp</p>
    <h1 class="font-display text-3xl font-extrabold tracking-tight">DREAMFITNESS</h1>
  </div>
  <button onclick={signOut} class="eyebrow hover:text-bone">Sign out</button>
</header>

{#if !p}
  <p class="p-8 text-center eyebrow animate-pulse">Loading</p>
{:else}
  {@const dayNo = elapsed.length}

  <div class="space-y-5 px-5 pt-3">

    <!-- ── SIGNATURE: the whole program, one cell per day ───────────────── -->
    <section class="panel p-5">
      <div class="flex items-baseline justify-between">
        <p class="eyebrow">Day {dayNo} of 90</p>
        <p class="tnum text-xs text-muted">{logged} logged</p>
      </div>

      <div class="mt-4 grid grid-cols-7 gap-1.5" role="img"
           aria-label="{logged} of {dayNo} elapsed days logged">
        {#each Array(lead) as _}<div></div>{/each}
        {#each p.days as d}
          <div title="Day {d.day_no} &middot; {d.day_date} &middot; {d.day_type}"
               class="aspect-square rounded-[3px] {cell(d)}
                      {d.day_date === today ? 'ring-2 ring-bone ring-offset-2 ring-offset-panel' : ''}">
          </div>
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

    <!-- persistence -->
    <section class="grid grid-cols-2 gap-3">
      <div class="panel p-5">
        <p class="eyebrow">Momentum</p>
        <p class="tnum mt-1 text-4xl font-bold {momentum == null ? 'text-muted/40' : 'text-peak'}">
          {momentum == null ? '--' : Math.round(momentum)}
        </p>
        <p class="mt-1 text-xs leading-snug text-muted">7-day weighted score</p>
      </div>
      <div class="panel p-5">
        <p class="eyebrow">Reliability</p>
        <p class="tnum mt-1 text-4xl font-bold {reliability == null ? 'text-muted/40' : 'text-fast'}">
          {reliability == null ? '--' : Math.round(reliability)}
        </p>
        <p class="mt-1 text-xs leading-snug text-muted">Consistency-adjusted</p>
      </div>
    </section>

    <section class="panel flex items-center justify-between p-5">
      <div>
        <p class="eyebrow">Streak</p>
        <p class="tnum mt-1 text-3xl font-bold">{streak.run}<span class="text-base text-muted"> days</span></p>
      </div>
      <div class="text-right">
        <p class="eyebrow">Freezes</p>
        <p class="tnum mt-1 text-lg">{'●'.repeat(streak.freezes) || '—'}</p>
        <p class="mt-0.5 text-[11px] text-muted">1 per 7 strong days</p>
      </div>
    </section>

    <!-- recomp: three signals, because the scale alone can't tell fat from muscle -->
    <section class="panel p-5">
      <p class="eyebrow">Recomposition signals</p>
      <p class="mt-1 text-xs text-muted">Flat weight + shrinking waist + rising volume = it's working.</p>

      <div class="mt-4 space-y-3">
        {#each [
          ['Weight trend', weight?.perWeek == null ? '--' : `${weight.perWeek > 0 ? '+' : ''}${f1(weight.perWeek, 2)} kg/wk`, weight?.perWeek != null && weight.perWeek < 0],
          ['Waist', waist == null ? '--' : `${f1(waist.last - waist.first, 1)} cm`, waist != null && waist.last < waist.first],
          ['Volume load', volumeTrend == null ? '--' : `${volumeTrend > 0 ? '+' : ''}${f1(volumeTrend, 0)}%`, volumeTrend != null && volumeTrend > 0],
        ] as [label, val, good]}
          <div class="flex items-center justify-between border-b border-line pb-3 last:border-0 last:pb-0">
            <span class="text-sm text-muted">{label}</span>
            <span class="tnum text-sm font-semibold {val === '--' ? 'text-muted/40' : good ? 'text-peak' : 'text-bone'}">
              {val}
            </span>
          </div>
        {/each}
      </div>
    </section>

    <!-- adaptive TDEE -->
    <section class="panel p-5">
      <p class="eyebrow">Adaptive TDEE</p>
      {#if tdee}
        <p class="tnum mt-1 text-4xl font-bold text-fed">{Math.round(tdee).toLocaleString()}</p>
        <p class="mt-1 text-xs text-muted">
          Measured from your real intake and weight trend, not a formula.
        </p>
      {:else}
        <p class="tnum mt-1 text-4xl font-bold text-muted/40">--</p>
        <p class="mt-1 text-xs leading-relaxed text-muted">
          Needs about 14 days of weight and intake. Until then the seed estimate is
          <span class="tnum text-bone">3,020 kcal</span> from Mifflin-St Jeor.
        </p>
      {/if}
    </section>

    <div class="grid grid-cols-2 gap-3 pb-4">
      <div class="panel p-5">
        <p class="eyebrow">Weight</p>
        <p class="tnum mt-1 text-2xl font-bold">
          {weight ? f1(weight.latest.ewma, 1) : f1(p.profile?.start_weight_kg, 1)}<span class="text-sm text-muted"> kg</span>
        </p>
        <p class="mt-0.5 text-[11px] text-muted">
          {weight ? 'Smoothed trend' : 'Starting weight'}
        </p>
      </div>
      <button onclick={onOpenToday} class="panel p-5 text-left transition hover:border-fast/50">
        <p class="eyebrow">Today</p>
        <p class="mt-1 font-display text-lg font-bold text-fast">Log the day &rarr;</p>
      </button>
    </div>
  </div>
{/if}
