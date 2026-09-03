<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../lib/supabase';
  import Login from './Login.svelte';
  import Today from './Today.svelte';
  import Dashboard from './Dashboard.svelte';
  import Meals from './Meals.svelte';
  import Gym from './Gym.svelte';

  let session = $state<any>(null);
  let ready   = $state(false);
  let online  = $state(true);
  let tab     = $state<'dashboard' | 'today' | 'gym' | 'meals'>('dashboard');

  onMount(async () => {
    const { data } = await supabase.auth.getSession();
    session = data.session;
    ready = true;
    supabase.auth.onAuthStateChange((_e, s) => (session = s));

    online = navigator.onLine;
    addEventListener('online',  () => (online = true));
    addEventListener('offline', () => (online = false));

    // Deliberately NOT on localhost: a dev-scoped worker outlives the project
    // and starts intercepting whatever runs on that port next.
    if (import.meta.env.PROD && location.hostname !== 'localhost'
        && location.hostname !== '127.0.0.1' && 'serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js').catch(() => {});
    }
  });

  const signOut = async () => { await supabase.auth.signOut(); session = null; };

  const TABS = [
    ['dashboard', 'Overview'], ['today', 'Today'], ['gym', 'Gym'], ['meals', 'Meals'],
  ] as const;
</script>

<!-- Installed to the home screen, iOS runs this full-bleed: black-translucent
     puts the web view UNDERNEATH the status bar. Anything that doesn't reserve
     env(safe-area-inset-top) draws behind the clock, and the status bar eats
     the taps meant for it. Every top-anchored element pads for it. -->
{#if !online}
  <div role="status"
       class="fixed inset-x-0 top-0 z-50 bg-fed px-4 pb-1.5 text-center text-xs font-semibold text-ink
              pt-[calc(env(safe-area-inset-top)+0.375rem)]">
    Offline &mdash; your plan is readable, but changes won't save until you reconnect
  </div>
{/if}

{#if !ready}
  <div class="grid min-h-dvh place-items-center">
    <div class="eyebrow animate-pulse">Loading</div>
  </div>
{:else if !session}
  <Login />
{:else}
  <div class="mx-auto max-w-lg pb-[calc(7rem+env(safe-area-inset-bottom))]">
    {#if tab === 'dashboard'}
      <Dashboard {signOut} onOpenToday={() => (tab = 'today')} />
    {:else if tab === 'today'}
      <Today />
    {:else if tab === 'gym'}
      <Gym />
    {:else}
      <Meals />
    {/if}
  </div>

  <nav class="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-panel/95 backdrop-blur
              pb-[env(safe-area-inset-bottom)]">
    <div class="mx-auto flex max-w-lg">
      {#each TABS as [key, label]}
        <button
          onclick={() => (tab = key as any)}
          class="flex-1 py-4 text-sm font-medium transition-colors
                 {tab === key ? 'text-bone' : 'text-muted'}">
          <span class="relative">
            {label}
            {#if tab === key}
              <span class="absolute -bottom-1.5 left-0 right-0 h-0.5 rounded bg-fast"></span>
            {/if}
          </span>
        </button>
      {/each}
    </div>
  </nav>
{/if}
