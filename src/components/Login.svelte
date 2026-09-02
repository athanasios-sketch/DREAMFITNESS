<script lang="ts">
  import { supabase } from '../lib/supabase';

  let name    = $state('');
  let busy    = $state(false);
  let error   = $state('');

  async function submit(e: Event) {
    e.preventDefault();
    if (!name.trim() || busy) return;
    busy = true; error = '';
    try {
      const res = await fetch('/api/login', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ name }),
      });
      const body = await res.json();
      if (!res.ok) { error = body.error ?? 'Could not sign in.'; return; }
      await supabase.auth.setSession(body.session);
    } catch {
      error = 'No connection. Check your network and try again.';
    } finally {
      busy = false;
    }
  }
</script>

<main class="grid min-h-dvh place-items-center px-6
             pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)]">
  <div class="w-full max-w-sm">
    <p class="eyebrow">90-day body recomp</p>
    <h1 class="mt-3 font-display text-5xl font-extrabold tracking-tight leading-[0.95]">
      DREAM<br /><span class="text-fast">FITNESS</span>
    </h1>
    <p class="mt-4 max-w-[26ch] text-sm leading-relaxed text-muted">
      Sep 2 &rarr; Nov 30. Ninety days, five meals, six sessions a week.
    </p>

    <form onsubmit={submit} class="mt-10">
      <label for="name" class="eyebrow">Your name</label>
      <input
        id="name" bind:value={name} autocomplete="given-name" autocapitalize="none"
        spellcheck="false" placeholder="thanos"
        class="mt-2 w-full rounded-xl border border-line bg-panel px-4 py-4
               font-data text-lg text-bone placeholder:text-muted/50
               focus:border-fast focus:outline-none" />

      {#if error}
        <p role="alert" class="mt-3 text-sm text-warn">{error}</p>
      {/if}

      <button
        type="submit" disabled={busy || !name.trim()}
        class="mt-4 w-full rounded-xl bg-bone py-4 font-display text-sm font-bold
               uppercase tracking-widest text-ink transition
               enabled:hover:bg-white disabled:opacity-30">
        {busy ? 'Signing in' : 'Start'}
      </button>
    </form>
  </div>
</main>
