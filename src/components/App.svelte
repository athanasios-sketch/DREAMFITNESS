<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../lib/supabase';
  import Login from './Login.svelte';
  import Today from './Today.svelte';
  import Dashboard from './Dashboard.svelte';
  import Meals from './Meals.svelte';

  let session = $state<any>(null);
  let ready   = $state(false);
  let tab     = $state<'dashboard' | 'today' | 'meals'>('dashboard');

  onMount(async () => {
    const { data } = await supabase.auth.getSession();
    session = data.session;
    ready = true;
    supabase.auth.onAuthStateChange((_e, s) => (session = s));
  });

  const signOut = async () => { await supabase.auth.signOut(); session = null; };
</script>

{#if !ready}
  <div class="grid min-h-dvh place-items-center">
    <div class="eyebrow animate-pulse">Loading</div>
  </div>
{:else if !session}
  <Login />
{:else}
  <div class="mx-auto max-w-lg pb-28">
    {#if tab === 'dashboard'}
      <Dashboard {signOut} onOpenToday={() => (tab = 'today')} />
    {:else if tab === 'today'}
      <Today />
    {:else}
      <Meals />
    {/if}
  </div>

  <nav class="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-panel/95 backdrop-blur
              pb-[env(safe-area-inset-bottom)]">
    <div class="mx-auto flex max-w-lg">
      {#each [['dashboard', 'Overview'], ['today', 'Today'], ['meals', 'Meals']] as [key, label]}
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
