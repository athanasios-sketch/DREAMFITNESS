import { defineConfig } from 'astro/config';
import svelte from '@astrojs/svelte';
import netlify from '@astrojs/netlify';
import tailwindcss from '@tailwindcss/vite';

// Static by default; only /api/login opts into on-demand rendering
// (it needs the service-side password, which must never reach the bundle).
export default defineConfig({
  output: 'static',
  adapter: netlify(),
  integrations: [svelte()],
  vite: { plugins: [tailwindcss()] },
});
