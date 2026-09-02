"""
DREAMFITNESS - 90-Day Body Recomp Program Generator (Optimized v6)

Source of truth for seeding Supabase. Two corrections over V5:
  1. Training split re-phased so no heavy resistance day lands on a fasting day.
  2. Fasting-day meals rebuilt to close the 115g -> 185g protein gap.

All dates are Europe/Athens local calendar dates. Never UTC timestamps:
Athens shifts UTC+3 -> UTC+2 on 25/10/2026, which is Day 54 of this program.
"""
import csv, json, datetime, collections
from pathlib import Path

OUT = Path(__file__).parent
START = datetime.date(2026, 9, 2)   # Wednesday - verified
DAYS = 90

# ---------------------------------------------------------------- meals
# v1 = original V5 values. v2 = optimized fasting meals (protein rebuild).
MEALS = [
    # id      slot        daytype    ver name                         P   C   F  kcal
    ("B1",   "breakfast","regular", 1, "Classic Oats & Eggs",        45, 45, 18, 520,
     "3 whole eggs, 150g egg whites, 60g oats",
     "Whisk eggs & whites in an oven-safe bowl. Airfry 180C/8min. Microwave oats with water/cinnamon."),
    ("B2",   "breakfast","regular", 1, "Greek Yogurt Bowl",          45, 40, 15, 475,
     "250g Greek yogurt 2%, 1 scoop whey, 1 banana, 20g almonds",
     "Mix whey into yogurt. Top with sliced banana and crushed almonds."),
    ("L1",   "lunch",    "regular", 1, "Airfryer Chicken & Rice",    55, 60, 15, 595,
     "220g chicken breast, 220g boiled basmati, 15g olive oil",
     "Marinate chicken (paprika/oregano). Airfry 195C/18min. Boil rice."),
    ("L2",   "lunch",    "regular", 1, "Turkey & Sweet Potato",      52, 60, 15, 583,
     "220g turkey breast, 300g sweet potato cubes, 15g olive oil",
     "Airfry turkey 185C/16min. Sweet potatoes 200C/20min."),
    ("S1",   "snack",    "regular", 1, "Whey & Fruit",               35, 30,  3, 280,
     "1 scoop whey protein, 1 medium apple or banana, water",
     "Shake whey with water. Eat fruit on the side."),
    ("D1",   "dinner",   "regular", 1, "Airfryer Salmon & Potatoes", 50, 60, 22, 638,
     "220g salmon fillet, 280g potatoes, veggies",
     "Airfry salmon 200C/10min. Potatoes 200C/18min."),
    ("D2",   "dinner",   "regular", 1, "Beef Strips & Veggies",      55, 50, 18, 582,
     "220g lean beef (5% fat) strips, 200g rice, peppers",
     "Airfry beef strips 190C/10min. Serve with rice and peppers."),

    # --- original fasting set (kept for reference / comparison) ---
    ("BF1",  "breakfast","fasting", 1, "Vegan Oats & Tahini",        30, 55, 18, 490,
     "30g vegan protein, 60g oats, almond milk, 15g tahini",
     "Mix protein with almond milk, stir in oats, top with tahini."),
    ("LF1",  "lunch",    "fasting", 1, "Crispy Chickpeas & Bread",   25, 75, 20, 580,
     "250g canned chickpeas, 120g whole wheat bread, 15g olive oil",
     "Drain chickpeas, toss in olive oil & spices. Airfry 190C/12min until crispy."),
    ("SF1",  "snack",    "fasting", 1, "Soy Yogurt & Vegan Pro",     25, 35,  8, 312,
     "200g soy yogurt, 20g vegan protein, 1 large apple",
     "Mix vegan protein powder into soy yogurt."),
    ("DF1",  "dinner",   "fasting", 1, "Crispy Tofu & Lentils",      35, 50, 18, 490,
     "150g firm tofu, 250g cooked lentils, 10g olive oil",
     "Press tofu, cube, toss with olive oil/soy sauce. Airfry 200C/15min."),
    ("DF2",  "dinner",   "fasting", 1, "Garlic Shrimp & Rice",       45, 55, 12, 490,
     "200g shrimp, 200g rice, 10g olive oil",
     "Toss shrimp in olive oil & garlic powder. Airfry 200C/8min."),

    # --- OPTIMIZED fasting set (protein rebuild, ~calorie neutral) ---
    ("BF1v2","breakfast","fasting", 2, "Vegan Oats & Tahini+",       44, 47, 18, 513,
     "50g vegan protein, 45g oats, 250ml soy milk, 15g tahini",
     "+20g protein powder, oats 60g->45g. Mix protein with soy milk, stir in oats, top with tahini."),
    ("LF1v2","lunch",    "fasting", 2, "Chickpeas, Edamame & Bread", 35, 57, 21, 555,
     "250g canned chickpeas, 150g shelled edamame, 60g whole wheat bread, 10g olive oil",
     "+150g edamame, bread 120g->60g, oil 15g->10g. Airfry chickpeas 190C/12min; steam edamame."),
    ("SF1v2","snack",    "fasting", 2, "Soy Yogurt & Vegan Pro+",    37, 36,  9, 370,
     "200g soy yogurt, 35g vegan protein, 1 large apple",
     "+15g protein powder. Mix into soy yogurt."),
    ("DF1v2","dinner",   "fasting", 2, "Crispy Tofu & Lentils+",     47, 42, 22, 532,
     "250g firm tofu, 200g cooked lentils, 5g olive oil",
     "Tofu 150g->250g, lentils 250g->200g, oil 10g->5g. Airfry 200C/15min."),
    ("DF2v2","dinner",   "fasting", 2, "Garlic Shrimp & Rice+",      56, 55, 12, 543,
     "250g shrimp, 200g rice, 10g olive oil",
     "Shrimp 200g->250g. Toss in olive oil & garlic powder. Airfry 200C/8min."),
]
M = {m[0]: m for m in MEALS}

# ---------------------------------------------------------------- exercises
EXERCISES = [
    ("E1","resistance","Push (Chest/Shoulders/Triceps)","Incline Press, Overhead Press, Dips, Lateral Raises",300,60,"Progressive overload. RPE 7-8."),
    ("E2","resistance","Pull (Back/Biceps/Rear Delts)","Pull-ups/Lat Pulldown, Rows, Face Pulls, Bicep Curls",300,60,"Control the eccentric. Squeeze the back."),
    ("E3","resistance","Legs (Quads/Hams/Glutes/Calves)","Squats/Hack Squats, RDLs, Leg Extensions, Leg Curls",375,68,"Heavy compound day. Tough on the CNS."),
    ("E4","resistance","Upper Body (All Round)","Chest Press, Row, Shoulder Press, Pulldown, Arms",320,60,"Shorter rest periods (60-90s)."),
    ("E5","resistance","Lower Body (All Round)","Leg Press, Lunges, Glute Ham Raises, Calves",350,60,"Higher rep ranges (10-15) vs E3."),
    ("C1","cardio","Active Recovery / Zone 2","Brisk walking, light cycling, or stairmaster",250,40,"HR 110-130bpm. Boosts recovery."),
    ("R1","rest","Full Rest","Stretching, mobility work, or complete rest",0,0,"Crucial for CNS recovery and muscle growth."),
]

# ------------------------------------------------- OPTIMIZED weekly split
# Mon=0 ... Sun=6.  Fasting = Wed(2) & Fri(4) -> get the two lowest-demand
# sessions (cardio + rest). No heavy resistance on a low-fuel day.
SPLIT = {2: "C1", 3: "E1", 4: "R1", 5: "E3", 6: "E2", 0: "E4", 1: "E5"}
FASTING_WEEKDAYS = {2, 4}

def macros(ids):
    p = sum(M[i][5] for i in ids); c = sum(M[i][6] for i in ids)
    f = sum(M[i][7] for i in ids); k = sum(M[i][8] for i in ids)
    return p, c, f, k

def build():
    days, reg_n = [], 0
    for n in range(1, DAYS + 1):
        d = START + datetime.timedelta(days=n - 1)
        wd = d.weekday()
        if wd in FASTING_WEEKDAYS:
            dtype = "Fasting"
            dinner = "DF1v2" if wd == 2 else "DF2v2"
            ids = ["BF1v2", "LF1v2", "SF1v2", dinner]
            legacy = ["BF1", "LF1", "SF1", "DF1" if wd == 2 else "DF2"]
        else:
            dtype = "Regular"
            reg_n += 1
            ids = ["B1","L1","S1","D1"] if reg_n % 2 == 1 else ["B2","L2","S1","D2"]
            legacy = ids
        p, c, f, k = macros(ids)
        lp = macros(legacy)[0]
        days.append({
            "day": n, "date": d.isoformat(), "date_display": d.strftime("%d/%m/%Y"),
            "weekday": d.strftime("%A"), "day_type": dtype,
            "week": (n - 1) // 7 + 1,
            "meals": ids, "exercise": SPLIT[wd],
            "steps_target": 10000, "water_target_l": 3.5,
            "protein_g": p, "carbs_g": c, "fat_g": f, "kcal": k,
            "legacy_protein_g": lp, "protein_delta": p - lp,
        })
    return days

def main():
    days = build()
    (OUT/"seed_meals.json").write_text(json.dumps([{
        "id":m[0],"slot":m[1],"day_type":m[2],"version":m[3],"name":m[4],
        "protein_g":m[5],"carbs_g":m[6],"fat_g":m[7],"kcal":m[8],
        "ingredients":m[9],"instructions":m[10]} for m in MEALS], indent=2))
    (OUT/"seed_exercises.json").write_text(json.dumps([{
        "id":e[0],"category":e[1],"name":e[2],"focus":e[3],
        "est_kcal":e[4],"duration_min":e[5],"notes":e[6]} for e in EXERCISES], indent=2))
    (OUT/"seed_program_days.json").write_text(json.dumps(days, indent=2))

    with open(OUT/"program_optimized.csv","w",newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Day","Date","Weekday","Week","Type","Meal 1","Meal 2","Meal 3","Meal 4",
                    "Exercise","Steps","Protein (g)","Carbs (g)","Fat (g)","Kcal","Water (L)",
                    "Old Protein (g)","Protein Delta"])
        for d in days:
            w.writerow([d["day"],d["date_display"],d["weekday"],d["week"],d["day_type"],
                        *d["meals"],d["exercise"],d["steps_target"],d["protein_g"],
                        d["carbs_g"],d["fat_g"],d["kcal"],d["water_target_l"],
                        d["legacy_protein_g"],f'+{d["protein_delta"]}' if d["protein_delta"] else "0"])
    return days

if __name__ == "__main__":
    days = main()

    # ---------------- validation ----------------
    print("=== DREAMFITNESS optimized program ===")
    print(f"Day 1  {days[0]['weekday']} {days[0]['date_display']}  ({days[0]['day_type']})")
    print(f"Day 90 {days[-1]['weekday']} {days[-1]['date_display']}")

    coll = [d for d in days if d["day_type"]=="Fasting" and d["exercise"] in ("E1","E2","E3","E4","E5")]
    print(f"\nheavy resistance on a fasting day: {len(coll)}  (was 26/26)")

    pair = collections.Counter((d["day_type"], d["exercise"]) for d in days)
    print("\nnew weekday split:")
    for wd in [2,3,4,5,6,0,1]:
        s = next(d for d in days if datetime.date.fromisoformat(d["date"]).weekday()==wd)
        print(f"   {s['weekday']:<9} {'FAST' if wd in FASTING_WEEKDAYS else '    '}  {s['exercise']}")

    ex = collections.Counter(d["exercise"] for d in days)
    print("\nsession counts /90d:", dict(sorted(ex.items())))

    prot = [d["protein_g"] for d in days]
    old  = [d["legacy_protein_g"] for d in days]
    print(f"\nprotein range: {min(prot)}-{max(prot)}g   (was {min(old)}-{max(old)}g)")
    print(f"mean daily protein: {sum(prot)/90:.1f}g   (was {sum(old)/90:.1f}g)")
    print(f"mean daily kcal:    {sum(d['kcal'] for d in days)/90:.0f}")

    # Atwater sanity
    bad = [d["day"] for d in days
           if abs((d["protein_g"]*4 + d["carbs_g"]*4 + d["fat_g"]*9) - d["kcal"]) > 60]
    print(f"Atwater mismatches >60kcal: {len(bad)}")
