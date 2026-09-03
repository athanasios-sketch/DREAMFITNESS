import { createClient } from '@supabase/supabase-js';
import fs from 'node:fs';
const env = Object.fromEntries(fs.readFileSync('.env.local','utf8').split('\n')
  .filter(l=>l.includes('=')).map(l=>{const i=l.indexOf('=');return [l.slice(0,i).trim(), l.slice(i+1).trim()];}));
const db = createClient(env.PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession:false, autoRefreshToken:false } });

const EMAIL='ntinos@dreamfitness.local';
const PASSWORD = process.argv[2];
if(!PASSWORD){ console.error('need password arg'); process.exit(1); }

// 1. auth user
let uid;
const { data:list } = await db.auth.admin.listUsers({ perPage:200 });
const found = list.users.find(u=>u.email===EMAIL);
if(found){ uid=found.id; await db.auth.admin.updateUserById(uid,{password:PASSWORD}); console.log('auth user exists ->',uid); }
else{
  const { data, error } = await db.auth.admin.createUser({email:EMAIL,password:PASSWORD,email_confirm:true});
  if(error) throw error; uid=data.user.id; console.log('auth user created ->',uid);
}

// 2. profile
const profile = {
  id: uid, email: EMAIL, sex:'male', birth_date:'2002-01-01', height_cm:180,
  start_weight_kg:102.5, program_start_date:'2026-09-07', program_days:180,
  timezone:'Europe/Athens',
  neat_factor:1.06, deficit_kcal:700,
  protein_target_g:190, protein_g_per_kg:2.10,
  diet_mode:'keto', carb_cap_g:28, fiber_target_g:28, veg_target_g:400,
  steps_target:9000, water_target_l:3.5,
  eat_window_start:'16:00', eat_window_end:'00:00',
  set_seconds:40, rest_seconds:150, tdee_adjustment:1.000,
};
{ const {error}=await db.from('profiles').upsert(profile,{onConflict:'id'}); if(error) throw error; }
console.log('profile upserted');

// 3. template
await db.from('program_templates').delete().eq('user_id',uid);
const { data:tpl, error:te } = await db.from('program_templates')
  .insert({user_id:uid, name:'Keto 16:00-00:00, four heavy days', active:true}).select().single();
if(te) throw te;

const EX=['KUA','KLA','REST','KUB','KLB','REST','REST'];   // Mon..Sun

// A rest day burns ~350 kcal less and is budgeted ~320 kcal lower, so it eats
// the leaner rotation: same 190 g of protein, ~35 g less fat. See migration
// 20260903150000 - without this the rest-day menu overshoots its own target by
// 322 kcal, three days a week.
const REST=['K-R1','K-R2','K-R3'];

// Only FOUR days a week eat the training rotation, and two variants makes eight
// menu slots. Assigning them by weekday and rotating the offset left two meals
// (the beef mince and the sardines) landing only on rest days, where they are
// replaced - so they would never once have been cooked. These eight are chosen
// to cover all eleven, no meal more than three times, every day inside
// 2338-2366 kcal, 189-193 g protein and 28 g net carbohydrate.
const TRAIN=[
  ['K-M1a','K-M2a','K-M3a'],   // Mon A
  ['K-M1a','K-M2a','K-M3c'],   // Tue A
  ['K-M1a','K-M2b','K-M3c'],   // Thu A
  ['K-M1b','K-M2a','K-M3a'],   // Fri A
  ['K-M1b','K-M2b','K-M3b'],   // Mon B
  ['K-M1b','K-M2c','K-M3a'],   // Tue B
  ['K-M1c','K-M2b','K-M3b'],   // Thu B
  ['K-M1d','K-M2d','K-M3c'],   // Fri B
];
const TRAIN_DOW=[1,2,4,5];                       // Mon, Tue, Thu, Fri
const menuFor=(dow, variant) => {
  const i = TRAIN_DOW.indexOf(dow);
  return i < 0 ? REST : TRAIN[i + variant*4];
};
const rows=[];
for(let d=0; d<7; d++){
  for(const variant of [0,1]){
    rows.push({template_id:tpl.id, dow:d+1, variant, day_type:'regular',
               exercise_code:EX[d], meal_codes:menuFor(d+1, variant)});
  }
}
{ const {error}=await db.from('program_template_days').insert(rows); if(error) throw error; }
console.log('template written:',rows.length,'rows');

// 4. generate. RPCs are security invoker, so call them AS Ntinos.
const asNtinos = createClient(env.PUBLIC_SUPABASE_URL, env.PUBLIC_SUPABASE_ANON_KEY,
  { auth:{persistSession:false} });
const { error:se } = await asNtinos.auth.signInWithPassword({email:EMAIL,password:PASSWORD});
if(se) throw se;
const { data:n, error:ge } = await asNtinos.rpc('generate_program',{});
if(ge) throw ge;
console.log('program generated:',n,'days');
