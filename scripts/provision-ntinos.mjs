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
  steps_target:9000, water_target_l:3.5, measure_weekday:6,   // Saturday
  eat_window_start:'16:00', eat_window_end:'00:00',
  set_seconds:40, rest_seconds:150, tdee_adjustment:1.000,
  // Away Monday to Friday. The generator reads this and lays those days out as
  // travel days; set_travel_days() overrides individual dates for the weeks
  // that differ, so a different week is a few taps rather than a regeneration.
  travel_weekdays:[1,2,3,4,5],
};
{ const {error}=await db.from('profiles').upsert(profile,{onConflict:'id'}); if(error) throw error; }
console.log('profile upserted');

// 3. template
await db.from('program_templates').delete().eq('user_id',uid);
const { data:tpl, error:te } = await db.from('program_templates')
  .insert({user_id:uid, name:'Away Mon-Fri, two full-body days at the weekend', active:true})
  .select().single();
if(te) throw te;

// He is away Monday to Friday with no barbell and only walking, so those five
// days are rest days - and the whole lifting budget is Saturday and Sunday.
// Two CONSECUTIVE days is what makes this full body twice rather than an
// upper/lower split: split over Sat+Sun, chest would be trained once a
// fortnight, which is how a 700 kcal deficit takes muscle with it. Saturday is
// squat-and-press, Sunday is hinge-and-pull, so the second day is not
// repeating the first one's patterns under the first one's fatigue.
//
// Mon-Fri still need a menu for the weeks he does not travel: the leaner
// rest-day rotation (migration 20260903150000), which is ~320 kcal below a
// training day because a rest day is.
const REST=['K-R1','K-R2','K-R3'];

// Four weekend slots across a fortnight, chosen so that all eleven plates of
// the home rotation get cooked rather than the same three every Saturday.
const WEEKEND={
  6:[['KFA',['K-M1a','K-M2a','K-M3a']],['KFA',['K-M1b','K-M2c','K-M3a']]],
  7:[['KFB',['K-M1c','K-M2b','K-M3b']],['KFB',['K-M1d','K-M2d','K-M3c']]],
};

const rows=[];
for(let dow=1; dow<=7; dow++){
  for(const variant of [0,1]){
    const [ex, meals] = WEEKEND[dow]?.[variant] ?? ['REST', REST];
    rows.push({template_id:tpl.id, dow, variant, day_type:'regular',
               exercise_code:ex, meal_codes:meals});
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
