import type { APIRoute } from 'astro';
import { createClient } from '@supabase/supabase-js';

export const prerender = false;

// astro dev reads .env into import.meta.env; Netlify injects real env vars at
// runtime into process.env. Check both so one code path works in both places.
const env = (k: string): string | undefined =>
  (import.meta.env as any)[k] ?? process.env[k];

// Name-only login. The credential lives here, server-side, never in the bundle.
// Adding a second person is one line.
const PEOPLE: Record<string, { email: string; secret: string }> = {
  thanos: { email: 'thanos@dreamfitness.local', secret: 'THANOS_PASSWORD' },
};

export const POST: APIRoute = async ({ request }) => {
  const json = (b: unknown, status = 200) =>
    new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } });

  let name = '';
  try { name = String((await request.json())?.name ?? ''); } catch { return json({ error: 'Bad request' }, 400); }

  const person = PEOPLE[name.trim().toLowerCase()];
  if (!person) return json({ error: "That name isn't set up yet." }, 401);

  const password = env(person.secret);
  if (!password) return json({ error: 'Server is missing this account\'s credential.' }, 500);

  const admin = createClient(
    env('PUBLIC_SUPABASE_URL')!,
    env('PUBLIC_SUPABASE_ANON_KEY')!,
    { auth: { persistSession: false } }
  );
  const { data, error } = await admin.auth.signInWithPassword({ email: person.email, password });
  if (error || !data.session) return json({ error: 'Could not sign in.' }, 401);

  return json({ session: data.session });
};
