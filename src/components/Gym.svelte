<script lang="ts">
  import { onMount } from 'svelte';
  import { loadGym, claimExercise, updateExercise, saveMovement, createExercise,
           assignDay, saveProfile, rescoreAll, deleteRow, sessionKcal,
           isoWeekday, WEEKDAYS } from '../lib/api';

  let g       = $state<any>(null);
  let busy    = $state(false);
  let err     = $state('');
  let openEx  = $state<number | null>(null);
  let openDay = $state<string | null>(null);
  let justSet = $state<{ date: string; id: number | null } | null>(null);
  let adding  = $state(false);
  let newName = $state('');

  const load = async () => {
    try { g = await loadGym(); err = ''; }
    catch (e: any) { err = e?.message ?? 'Could not load your program.'; }
  };
  onMount(load);

  const CATS = [
    ['resistance', 'Lifting'],
    ['mixed',      'Mixed'],
    ['cardio',     'Cardio'],
    ['rest',       'Rest'],
  ] as const;

  const TRACKING = [
    ['load',       'kg'],
    ['bodyweight', 'body'],
    ['time',       'time'],
  ] as const;

  /** Fraction of a session actually spent under load. This single number is
   *  why an hour of lifting is not an hour of work. */
  const duty = (e: any) => {
    if (e?.duty_pct != null) return +e.duty_pct;
    const set = +(g?.profile?.set_seconds ?? 45), rest = +(g?.profile?.rest_seconds ?? 120);
    return set + rest > 0 ? set / (set + rest) : 1;
  };

  const kcalFor = (e: any, minutes = e?.duration_min) => {
    if (!e) return 0;
    if (e.kcal_override != null && Number.isFinite(+e.kcal_override)) {
      const over = +e.kcal_override;
      return +e.duration_min > 0 && Number.isFinite(+minutes)
        ? Math.round(over * (+minutes / +e.duration_min))
        : Math.round(over);
    }
    return Math.round(sessionKcal({
      minutes: +minutes || 0, weightKg: g?.weightKg ?? 88,
      workMet: +e.work_met, recoveryMet: +e.recovery_met, dutyPct: e.duty_pct,
      setSeconds: +(g?.profile?.set_seconds ?? 45),
      restSeconds: +(g?.profile?.rest_seconds ?? 120), epoc: +e.epoc_factor,
    }));
  };

  const perMin = (e: any) => {
    const d = +e.duration_min || 60;
    const v = kcalFor(e, d) / d;
    return Number.isFinite(v) ? v.toFixed(1) : '0.0';
  };

  /** Editing a shared system session forks it into a private copy first, so
   *  the ids change underneath us - reopen on whatever comes back. */
  async function open(e: any) {
    if (openEx === e.id) { openEx = null; return; }
    if (e.user_id) { openEx = e.id; return; }
    busy = true;
    try {
      const mine = await claimExercise(e.id);
      await load();
      openEx = mine;
    } catch (x: any) { err = x?.message ?? 'Could not open this session for editing.'; }
    finally { busy = false; }
  }

  let timers: Record<string, any> = {};
  function patchEx(id: number, field: string, value: any, delay = 500) {
    const ex = g.library.find((e: any) => e.id === id);
    if (ex) ex[field] = value === '' ? null : value;      // optimistic, keeps typing smooth
    clearTimeout(timers['e' + id + field]);
    timers['e' + id + field] = setTimeout(async () => {
      try { await updateExercise(id, { [field]: value }); await rescoreAll(); }
      catch (x: any) { err = x?.message ?? 'Could not save.'; await load(); }
    }, delay);
  }

  function patchMv(exId: number, mv: any, field: string, value: any, delay = 500) {
    mv[field] = value === '' ? null : value;
    clearTimeout(timers['m' + mv.id + field]);
    timers['m' + mv.id + field] = setTimeout(async () => {
      try { await saveMovement(exId, { ...$state.snapshot(mv), [field]: value === '' ? null : value }); }
      catch (x: any) { err = x?.message ?? 'Could not save.'; await load(); }
    }, delay);
  }

  async function addMovement(e: any) {
    if (busy) return; busy = true;
    try {
      const next = Math.max(-1, ...e.movements.map((m: any) => m.order_index)) + 1;
      await saveMovement(e.id, { name: 'New movement', order_index: next,
                                 target_sets: 3, rep_low: 8, rep_high: 12, tracking: 'load' });
      await load();
    } finally { busy = false; }
  }

  async function move(e: any, i: number, dir: number) {
    const j = i + dir;
    if (j < 0 || j >= e.movements.length || busy) return;
    busy = true;
    try {
      const a = e.movements[i], b = e.movements[j];
      await Promise.all([
        saveMovement(e.id, { ...$state.snapshot(a), order_index: b.order_index }),
        saveMovement(e.id, { ...$state.snapshot(b), order_index: a.order_index }),
      ]);
      await load();
    } finally { busy = false; }
  }

  async function removeMovement(id: number) {
    if (busy) return; busy = true;
    try { await deleteRow('exercise_movements', id); await load(); }
    finally { busy = false; }
  }

  async function pick(date: string, exerciseId: number | null) {
    if (busy) return; busy = true;
    try {
      await assignDay(date, exerciseId, 'day');
      await rescoreAll();
      justSet = { date, id: exerciseId };
      openDay = null;
      await load();
    } catch (x: any) { err = x?.message ?? 'Could not change that day.'; }
    finally { busy = false; }
  }

  async function widen(scope: 'weekday' | 'all') {
    if (!justSet || busy) return; busy = true;
    try {
      await assignDay(justSet.date, justSet.id, scope);
      await rescoreAll();
      justSet = null;
      await load();
    } finally { busy = false; }
  }

  async function addSession() {
    if (!newName.trim() || busy) return; busy = true;
    try {
      const e = await createExercise(newName.trim(), g.profile);
      newName = ''; adding = false;
      await load();
      openEx = e.id;
    } catch (x: any) { err = x?.message ?? 'Could not create that session.'; }
    finally { busy = false; }
  }

  function protocolField(field: string, value: string) {
    clearTimeout(timers[field]);
    timers[field] = setTimeout(async () => {
      const n = parseInt(value, 10);
      if (!Number.isFinite(n)) return;
      try { await saveProfile({ [field]: n }); await rescoreAll(); await load(); }
      catch (x: any) { err = x?.message ?? 'Could not save.'; }
    }, 700);
  }

  const dayName = (iso: string) =>
    new Date(iso + 'T12:00:00').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
</script>

<header class="px-5 pb-2 pt-[calc(env(safe-area-inset-top)+1.5rem)]">
  <p class="eyebrow">Your split</p>
  <h1 class="font-display text-3xl font-extrabold tracking-tight">Gym</h1>
  <p class="mt-2 text-sm leading-relaxed text-muted">
    Every session, every movement, and the maths that turns minutes into calories.
    Edit any of it &mdash; the plan and your history follow.
  </p>
</header>

{#if err}
  <div class="mx-5 mt-4 rounded-xl border border-warn/40 bg-warn/10 p-4">
    <p class="text-sm text-warn">{err}</p>
    <button onclick={() => { err = ''; load(); }} class="mt-2 text-sm underline">Try again</button>
  </div>
{/if}

{#if !g}
  <p class="p-8 text-center eyebrow animate-pulse">Loading</p>
{:else}
  <div class="space-y-5 px-5 pt-3 pb-4">

    <!-- ── the week ahead ─────────────────────────────────────────────── -->
    <section class="panel p-5">
      <p class="eyebrow">The week ahead</p>
      <p class="mt-1 text-xs leading-relaxed text-muted">
        Chest and back swap between Monday and Thursday each week. Tap any day to change it.
      </p>

      <div class="mt-4 space-y-1.5">
        {#each g.plan.slice(0, 7) as d}
          {@const fasting = d.day_type === 'fasting'}
          {@const isOpen = openDay === d.day_date}
          <div class="rounded-xl border {isOpen ? 'border-fast/50' : 'border-line'}">
            <button onclick={() => (openDay = isOpen ? null : d.day_date)}
              class="flex w-full items-center gap-3 p-3 text-left">
              <span class="w-1 self-stretch rounded-full {fasting ? 'bg-fast' : 'bg-fed'}"></span>
              <span class="min-w-0 flex-1">
                <span class="flex items-baseline gap-2">
                  <span class="text-sm font-semibold">{dayName(d.day_date)}</span>
                  {#if d.day_date === g.today}
                    <span class="eyebrow text-[9px] text-fast">today</span>
                  {/if}
                  {#if fasting}
                    <span class="eyebrow text-[9px] text-fast">fasting</span>
                  {/if}
                </span>
                <span class="block truncate text-sm text-muted">
                  {d.exercise?.name ?? 'Nothing scheduled'}
                </span>
              </span>
              <span class="tnum shrink-0 text-right text-xs text-muted">
                {#if d.exercise && d.exercise.category !== 'rest'}
                  {d.exercise.duration_min} min<br />~{kcalFor(d.exercise)} kcal
                {:else}
                  &mdash;
                {/if}
              </span>
            </button>

            {#if isOpen}
              <div class="border-t border-line p-2">
                {#each g.library as e}
                  <button onclick={() => pick(d.day_date, e.id)} disabled={busy}
                    class="flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-sm
                           {e.id === d.exercise?.id ? 'bg-fast/15 text-fast' : 'hover:bg-raised'}">
                    <span class="truncate">{e.name}</span>
                    <span class="tnum shrink-0 text-xs text-muted">
                      {e.category === 'rest' ? '—' : `${e.duration_min}m · ${kcalFor(e)}`}
                    </span>
                  </button>
                {/each}
              </div>
            {/if}
          </div>
        {/each}
      </div>

      {#if justSet}
        <div class="mt-3 rounded-xl border border-fast/40 bg-fast/5 p-3">
          <p class="text-xs text-muted">
            Changed {dayName(justSet.date)}. Apply the same change further out?
          </p>
          <div class="mt-2 flex gap-2">
            <button onclick={() => widen('weekday')} disabled={busy}
              class="flex-1 rounded-lg border border-fast/40 py-2 text-xs text-fast">
              Every {WEEKDAYS[isoWeekday(justSet.date) - 1]}
            </button>
            <button onclick={() => widen('all')} disabled={busy}
              class="flex-1 rounded-lg border border-line py-2 text-xs text-muted">
              All remaining days
            </button>
            <button onclick={() => (justSet = null)} aria-label="Dismiss"
              class="rounded-lg border border-line px-3 text-xs text-muted">&times;</button>
          </div>
        </div>
      {/if}
    </section>

    <!-- ── set/rest protocol ──────────────────────────────────────────── -->
    <section class="panel p-5">
      <p class="eyebrow">Your protocol</p>
      <p class="mt-1 text-xs leading-relaxed text-muted">
        45 seconds of work against 2 minutes of rest means you are under load for
        {Math.round(duty(null) * 100)}% of a session. That single fraction is what keeps these
        estimates honest &mdash; and it is why an hour of lifting is nowhere near an hour of running.
      </p>
      <div class="mt-4 grid grid-cols-2 gap-3">
        {#each [['set_seconds', 'Set length', 's'], ['rest_seconds', 'Rest between sets', 's']] as [f, label, unit]}
          <label class="block">
            <span class="eyebrow">{label} ({unit})</span>
            <input value={g.profile?.[f as string] ?? ''} inputmode="numeric"
              oninput={(ev) => protocolField(f as string, (ev.currentTarget as HTMLInputElement).value)}
              class="tnum mt-1 w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-bone" />
          </label>
        {/each}
      </div>
      <p class="tnum mt-3 border-t border-line pt-3 text-xs text-muted">
        Time under load <span class="text-bone">{Math.round(duty(null) * 100)}%</span>
        &middot; estimates use <span class="text-bone">{g.weightKg} kg</span>
      </p>
    </section>

    <!-- ── the sessions ───────────────────────────────────────────────── -->
    <section>
      <div class="mb-3 flex items-center justify-between">
        <p class="eyebrow">Sessions</p>
        <button onclick={() => (adding = !adding)} class="text-sm text-fast">
          {adding ? 'Cancel' : '+ New'}
        </button>
      </div>

      {#if adding}
        <div class="panel mb-2 flex gap-2 p-3">
          <input bind:value={newName} placeholder="Session name"
            class="w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-sm" />
          <button onclick={addSession} disabled={busy || !newName.trim()}
            class="shrink-0 rounded-lg bg-bone px-4 text-sm font-bold text-ink disabled:opacity-30">
            Create
          </button>
        </div>
      {/if}

      <div class="space-y-2">
        {#each g.library as e}
          {@const isOpen = openEx === e.id}
          {@const rest = e.category === 'rest'}
          <div class="panel overflow-hidden {isOpen ? 'border-fast/40' : ''}">
            <button onclick={() => open(e)} class="flex w-full items-center gap-3 p-4 text-left">
              <span class="min-w-0 flex-1">
                <span class="flex items-baseline gap-2">
                  <span class="truncate font-semibold">{e.name}</span>
                  {#if e.user_id}
                    <span class="eyebrow shrink-0 text-[9px] text-peak">yours</span>
                  {/if}
                </span>
                <span class="tnum block text-xs text-muted">
                  {#if rest}
                    Recovery &middot; no session
                  {:else}
                    {e.duration_min} min &middot; ~{kcalFor(e)} kcal &middot; {perMin(e)}/min
                    {#if e.movements.length}&middot; {e.movements.length} movements{/if}
                  {/if}
                </span>
              </span>
              <span class="shrink-0 text-muted">{isOpen ? '−' : '+'}</span>
            </button>

            {#if isOpen}
              <div class="space-y-5 border-t border-line px-4 py-4">
                <div class="grid gap-3">
                  <label class="block">
                    <span class="eyebrow">Name</span>
                    <input value={e.name}
                      oninput={(ev) => patchEx(e.id, 'name', (ev.currentTarget as HTMLInputElement).value)}
                      class="mt-1 w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-sm" />
                  </label>
                  <label class="block">
                    <span class="eyebrow">What it covers</span>
                    <input value={e.focus ?? ''}
                      oninput={(ev) => patchEx(e.id, 'focus', (ev.currentTarget as HTMLInputElement).value)}
                      class="mt-1 w-full rounded-lg border border-line bg-ink px-3 py-2.5 text-sm" />
                  </label>
                </div>

                <div>
                  <span class="eyebrow">Type</span>
                  <div class="mt-1.5 flex gap-1.5">
                    {#each CATS as [key, label]}
                      <button onclick={() => patchEx(e.id, 'category', key, 0)}
                        class="h-9 flex-1 rounded-md border text-xs transition
                          {e.category === key ? 'border-fast bg-fast/15 text-fast' : 'border-line text-muted'}"
                        >{label}</button>
                    {/each}
                  </div>
                  <p class="mt-1.5 text-[11px] leading-relaxed text-muted">
                    {#if e.category === 'resistance'}
                      Graded on tonnage against your last three of these.
                    {:else if e.category === 'mixed'}
                      Treadmill plus lifting. Graded on turning up, not on tonnage.
                    {:else if e.category === 'cardio'}
                      Graded on turning up. Runs continuously, so no rest gaps.
                    {:else}
                      Full marks for resting. Train anyway and the minutes still count.
                    {/if}
                  </p>
                </div>

                <!-- energy model -->
                <div class="rounded-lg border border-line p-3">
                  <div class="flex items-baseline justify-between">
                    <span class="eyebrow">Energy</span>
                    <span class="tnum text-sm text-fed">~{kcalFor(e)} kcal</span>
                  </div>
                  {#if e.movements.some((m: any) => m.tracking === 'time')}
                    <p class="mt-1 text-[11px] leading-relaxed text-muted">
                      Lifting only. The timed blocks in this session are costed from the pace
                      you log and added on top.
                    </p>
                  {/if}
                  <div class="mt-3 grid grid-cols-2 gap-3">
                    {#each [['duration_min', 'Planned minutes'],
                            ['work_met', 'Effort during a set (MET)'],
                            ['recovery_met', 'Effort while resting (MET)'],
                            ['epoc_factor', 'Afterburn ×']] as [f, label]}
                      <label class="block">
                        <span class="eyebrow text-[9px]">{label}</span>
                        <input value={e[f as string] ?? ''} inputmode="decimal"
                          oninput={(ev) => patchEx(e.id, f as string,
                                     (ev.currentTarget as HTMLInputElement).value)}
                          class="tnum mt-1 w-full rounded-lg border border-line bg-ink px-2.5 py-2 text-sm" />
                      </label>
                    {/each}
                  </div>

                  <div class="mt-3">
                    <span class="eyebrow text-[9px]">Time under load</span>
                    <div class="mt-1.5 flex items-center gap-2">
                      <button onclick={() => patchEx(e.id, 'duty_pct', null, 0)}
                        class="h-9 rounded-md border px-3 text-xs
                          {e.duty_pct == null ? 'border-fast bg-fast/15 text-fast' : 'border-line text-muted'}">
                        From your sets
                      </button>
                      <input value={e.duty_pct == null ? '' : Math.round(+e.duty_pct * 100)}
                        inputmode="numeric" placeholder={String(Math.round(duty(null) * 100))}
                        oninput={(ev) => {
                          const v = (ev.currentTarget as HTMLInputElement).value;
                          patchEx(e.id, 'duty_pct', v === '' ? null : Math.min(100, Math.max(0, +v)) / 100);
                        }}
                        class="tnum h-9 w-20 rounded-lg border border-line bg-ink px-2.5 text-sm" />
                      <span class="text-xs text-muted">% override</span>
                    </div>
                    <p class="mt-1.5 text-[11px] leading-relaxed text-muted">
                      A treadmill block never stops, so set 100%. Anything with rest between
                      sets should inherit from your protocol.
                    </p>
                  </div>

                  <label class="mt-3 block">
                    <span class="eyebrow text-[9px]">Or fix the number yourself (kcal)</span>
                    <input value={e.kcal_override ?? ''} inputmode="numeric" placeholder="model decides"
                      oninput={(ev) => patchEx(e.id, 'kcal_override',
                                 (ev.currentTarget as HTMLInputElement).value)}
                      class="tnum mt-1 w-full rounded-lg border border-line bg-ink px-2.5 py-2 text-sm" />
                  </label>
                </div>

                <!-- movements -->
                <div>
                  <div class="flex items-center justify-between">
                    <span class="eyebrow">Movements</span>
                    <button onclick={() => addMovement(e)} class="text-sm text-fast">+ Add</button>
                  </div>
                  <div class="mt-2 space-y-2">
                    {#each e.movements as mv, i}
                      <div class="rounded-lg border border-line p-2.5">
                        <div class="flex items-center gap-2">
                          <input value={mv.name}
                            oninput={(ev) => patchMv(e.id, mv, 'name',
                                       (ev.currentTarget as HTMLInputElement).value)}
                            class="min-w-0 flex-1 rounded-md border border-line bg-ink px-2.5 py-2 text-sm" />
                          <button onclick={() => move(e, i, -1)} aria-label="Move up"
                            class="px-1 text-muted disabled:opacity-20" disabled={i === 0}>&uarr;</button>
                          <button onclick={() => move(e, i, 1)} aria-label="Move down"
                            class="px-1 text-muted disabled:opacity-20"
                            disabled={i === e.movements.length - 1}>&darr;</button>
                          <button onclick={() => removeMovement(mv.id)} aria-label="Remove movement"
                            class="px-1 text-muted hover:text-warn">&times;</button>
                        </div>
                        <div class="mt-2 flex items-center gap-2">
                          <label class="flex items-center gap-1.5">
                            <span class="eyebrow text-[9px]">sets</span>
                            <input value={mv.target_sets ?? ''} inputmode="numeric"
                              oninput={(ev) => patchMv(e.id, mv, 'target_sets',
                                         (ev.currentTarget as HTMLInputElement).value)}
                              class="tnum w-12 rounded-md border border-line bg-ink px-2 py-1.5 text-sm" />
                          </label>
                          {#if mv.tracking === 'time'}
                            <label class="flex items-center gap-1.5">
                              <span class="eyebrow text-[9px]">met</span>
                              <input value={mv.met ?? ''} inputmode="decimal" placeholder="6"
                                oninput={(ev) => patchMv(e.id, mv, 'met',
                                           (ev.currentTarget as HTMLInputElement).value)}
                                class="tnum w-14 rounded-md border border-line bg-ink px-2 py-1.5 text-sm" />
                            </label>
                          {:else}
                            <label class="flex items-center gap-1.5">
                              <span class="eyebrow text-[9px]">reps</span>
                              <input value={mv.rep_low ?? ''} inputmode="numeric"
                                oninput={(ev) => patchMv(e.id, mv, 'rep_low',
                                           (ev.currentTarget as HTMLInputElement).value)}
                                class="tnum w-12 rounded-md border border-line bg-ink px-2 py-1.5 text-sm" />
                            </label>
                            <span class="text-muted">–</span>
                            <input value={mv.rep_high ?? ''} inputmode="numeric"
                              oninput={(ev) => patchMv(e.id, mv, 'rep_high',
                                         (ev.currentTarget as HTMLInputElement).value)}
                              class="tnum w-12 rounded-md border border-line bg-ink px-2 py-1.5 text-sm" />
                          {/if}
                          <span class="ml-auto flex gap-1">
                            {#each TRACKING as [key, label]}
                              <button onclick={() => patchMv(e.id, mv, 'tracking', key, 0)}
                                class="rounded-md border px-2 py-1.5 text-[11px]
                                  {mv.tracking === key ? 'border-fast bg-fast/15 text-fast' : 'border-line text-muted'}"
                                >{label}</button>
                            {/each}
                          </span>
                        </div>
                        {#if mv.tracking === 'time'}
                          <p class="mt-1.5 text-[11px] leading-relaxed text-muted">
                            Runs continuously, so it is costed on its own rather than at the
                            session's rest-heavy pace. Log distance with the minutes and the
                            intensity comes from your actual speed and incline &mdash; this MET
                            is only the fallback when distance is missing.
                          </p>
                        {/if}
                      </div>
                    {/each}
                    {#if !e.movements.length}
                      <p class="py-3 text-center text-xs text-muted">
                        No movements yet. Add the lifts you actually do and they show up on Today.
                      </p>
                    {/if}
                  </div>
                </div>
              </div>
            {/if}
          </div>
        {/each}
      </div>
    </section>
  </div>
{/if}
