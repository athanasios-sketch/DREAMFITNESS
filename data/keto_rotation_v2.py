#!/usr/bin/env python3
"""Re-solve Ntinos's ketogenic rotation with no fish and no courgette.

Same method as the original rotation: every meal FIXES its vegetables and its
accessories, then solves the protein source and the olive oil so the plate hits
its calorie and protein target exactly. Two unknowns, two equations, one linear
solve - which is why the amounts come out as ugly numbers like 281 g.

Run:  python3 data/keto_rotation_v2.py           # the table, for reading
      python3 data/keto_rotation_v2.py --sql     # the VALUES rows, for the migration
"""
import sys

# per 100 g: kcal, protein, carbs, fat, fibre, is_veg
REF = {
 'Χόρτα (wild greens), boiled':            (25,  2.5,  4.0,  0.3,  2.5, True),
 'Mushrooms':                              (22,  3.1,  3.3,  0.3,  1.0, True),
 'Spinach, raw':                           (23,  2.9,  3.6,  0.4,  2.2, True),
 'Rocket (ρόκα)':                          (25,  2.6,  3.7,  0.7,  1.6, True),
 'Romaine lettuce':                        (17,  1.2,  3.3,  0.3,  2.1, True),
 'Cucumber':                               (15,  0.7,  3.6,  0.1,  0.5, True),
 'Tomato':                                 (18,  0.9,  3.9,  0.2,  1.2, True),
 'Green pepper':                           (20,  0.9,  4.6,  0.2,  1.7, True),
 'Avocado':                                (160, 2.0,  8.5,  14.7, 6.7, False),
 'Kalamata olives, drained':               (220, 1.5,  6.0,  21.0, 3.2, False),
 'Feta':                                   (264, 14.2, 4.1,  21.3, 0.0, False),
 'Graviera':                               (390, 28.0, 1.0,  30.0, 0.0, False),
 'Halloumi':                               (321, 22.0, 2.2,  25.0, 0.0, False),
 'Greek yogurt 10% (στραγγιστό)':          (133, 6.4,  4.0,  10.0, 0.0, False),
 'Egg, whole':                             (143, 12.6, 0.7,  9.5,  0.0, False),
 'Whey isolate powder':                    (373, 86.0, 4.0,  1.5,  0.0, False),
 'Chicken breast, raw':                    (120, 22.5, 0.0,  2.6,  0.0, False),
 'Chicken thigh, boneless skinless, raw':  (119, 20.3, 0.0,  4.3,  0.0, False),
 'Chicken thigh, skin-on, raw':            (209, 17.5, 0.0,  15.0, 0.0, False),
 'Turkey breast, raw':                     (104, 21.9, 0.0,  1.7,  0.0, False),
 'Beef mince 15% fat, raw':                (215, 18.6, 0.0,  15.0, 0.0, False),
 'Pork shoulder (χοιρινή μπριζόλα), raw':  (180, 19.0, 0.0,  11.5, 0.0, False),
 'Rotisserie chicken, meat only':          (190, 29.0, 0.0,  8.0,  0.0, False),
 'Walnuts':                                (654, 15.0, 14.0, 65.0, 6.7, False),
 'Chia seeds':                             (486, 17.0, 42.0, 31.0, 34.0, False),
 'Ground flaxseed':                        (534, 18.0, 29.0, 42.0, 27.0, False),
 'Psyllium husk':                          (200, 0.0,  85.0, 0.5,  80.0, False),
 'Olive oil':                              (884, 0.0,  0.0,  100.0, 0.0, False),
}

ROLE = {
 'Χόρτα (wild greens), boiled':'veg', 'Mushrooms':'veg', 'Spinach, raw':'veg',
 'Rocket (ρόκα)':'veg', 'Romaine lettuce':'veg', 'Cucumber':'veg', 'Tomato':'veg',
 'Green pepper':'veg', 'Avocado':'produce', 'Kalamata olives, drained':'produce',
 'Feta':'protein', 'Graviera':'protein', 'Halloumi':'protein',
 'Greek yogurt 10% (στραγγιστό)':'protein', 'Egg, whole':'protein',
 'Whey isolate powder':'protein', 'Chicken breast, raw':'protein',
 'Chicken thigh, boneless skinless, raw':'protein', 'Chicken thigh, skin-on, raw':'protein',
 'Turkey breast, raw':'protein', 'Beef mince 15% fat, raw':'protein',
 'Pork shoulder (χοιρινή μπριζόλα), raw':'protein', 'Rotisserie chicken, meat only':'protein',
 'Walnuts':'extra', 'Chia seeds':'extra', 'Ground flaxseed':'extra',
 'Psyllium husk':'extra', 'Olive oil':'fat',
}

def solve(fixed, free_a, free_b, kcal_t, prot_t, step_a=5, step_b=1):
    """fixed: [(name, grams)]. free_a/free_b: the two names being solved for."""
    fk = sum(REF[n][0]*g/100 for n, g in fixed)
    fp = sum(REF[n][1]*g/100 for n, g in fixed)
    ka, pa = REF[free_a][0]/100, REF[free_a][1]/100
    kb, pb = REF[free_b][0]/100, REF[free_b][1]/100
    det = ka*pb - kb*pa
    if abs(det) < 1e-9:
        raise ValueError('the two free ingredients are not independent')
    dk, dp = kcal_t - fk, prot_t - fp
    a = (dk*pb - kb*dp) / det
    b = (ka*dp - dk*pa) / det
    a = round(a/step_a)*step_a
    b = round(b/step_b)*step_b
    if a < 0 or b < 0:
        raise ValueError(f'negative solve: {free_a}={a}, {free_b}={b}')
    return fixed + [(free_a, a), (free_b, b)]

def totals(items):
    t = dict(kcal=0.0, p=0.0, c=0.0, f=0.0, fib=0.0, veg=0.0)
    for n, g in items:
        k, p, c, f, fib, veg = REF[n]
        s = g/100
        t['kcal'] += k*s; t['p'] += p*s; t['c'] += c*s; t['f'] += f*s
        t['fib'] += fib*s
        if veg: t['veg'] += g
    return t


# ────────────────────────────────────────────────────────────────── the meals
# Only the plates that had to change are re-solved here. K-M1b, K-M2b, K-M2c,
# K-M3a, K-M3b, K-R2 and K-R3 carry no fish and no courgette and are untouched.
#
# `free` names the two ingredients solved for; a meal with `free=None` is
# written out by hand, because on some plates there is nothing left to solve.
MEALS = {}

MEALS['K-M1a'] = dict(
    name='Airfryer chicken thighs, χόρτα, σπανάκι and feta',
    slot='lunch', day_type='regular', kcal=892, prot=72.36,
    fixed=[('Χόρτα (wild greens), boiled', 200), ('Spinach, raw', 120),
           ('Mushrooms', 60), ('Feta', 30), ('Egg, whole', 60)],
    free=('Chicken thigh, skin-on, raw', 'Olive oil'),
    instructions='Airfryer 200C, 22-25 min, skin side up. No oil in the basket - the thigh renders its own. Χόρτα boiled and drained hard: a side now rather than the whole plate. Spinach and mushrooms go in the pan with the fat that came off the chicken, sixty seconds for the spinach and no more. Feta and the egg on the side, far more lemon than feels right.')

MEALS['K-M1c'] = dict(
    name='Airfryer turkey fillet with mushrooms, spinach and avocado',
    slot='lunch', day_type='regular', kcal=890, prot=72.26,
    fixed=[('Mushrooms', 120), ('Spinach, raw', 120), ('Rocket (ρόκα)', 40),
           ('Avocado', 60), ('Walnuts', 25)],
    free=('Turkey breast, raw', 'Olive oil'),
    instructions='Airfryer 190C, 16-18 min - turkey is leaner than chicken breast and goes to sawdust past that, so pull it early and rest it. Mushrooms in the basket alongside. Spinach, rocket and avocado raw underneath, walnuts over, oil and lemon. Turkey brings almost no fat of its own, so on this plate the oil is not a dressing, it is the meal: two and a bit tablespoons, measured, or the day comes in 300 kcal light.')

MEALS['K-M1d'] = dict(
    name='Beef mince, mushroom and spinach pan, feta on top',
    slot='lunch', day_type='regular', kcal=906, prot=72.22,
    fixed=[('Mushrooms', 200), ('Spinach, raw', 150), ('Feta', 40),
           ('Ground flaxseed', 12)],
    free=('Beef mince 15% fat, raw', 'Olive oil'),
    instructions='Pan, high heat. Brown the mince hard and do not stir it too early or it steams. Mushrooms in next - they want the fat that came out of the mince, and they will take all of it. Spinach wilted in at the end, feta crumbled over off the heat, flaxseed stirred through.')

MEALS['K-M2a'] = dict(
    name='Airfryer chicken breast, peppers, mushrooms and olives',
    slot='dinner', day_type='regular', kcal=800, prot=66.49,
    fixed=[('Green pepper', 100), ('Mushrooms', 150), ('Kalamata olives, drained', 25),
           ('Graviera', 25), ('Ground flaxseed', 12)],
    free=('Chicken breast, raw', 'Olive oil'),
    instructions='Airfryer 190C, 16-18 min - breast goes dry past that. Peppers and mushrooms in the basket alongside; mushrooms shrink to nothing, so pile them in. Olives, grated graviera and the flaxseed over the top.')

MEALS['K-M2d'] = dict(
    name='Chicken thigh with yogurt-cucumber sauce and rocket',
    slot='dinner', day_type='regular', kcal=803, prot=65.52,
    fixed=[('Greek yogurt 10% (στραγγιστό)', 80), ('Cucumber', 120),
           ('Rocket (ρόκα)', 80), ('Tomato', 50),
           ('Kalamata olives, drained', 20), ('Ground flaxseed', 12)],
    free=('Chicken thigh, boneless skinless, raw', 'Olive oil'),
    instructions='Pan or airfryer, 200C, 15-18 min. Half the cucumber grated into the yogurt with garlic, dill and salt - tzatziki without the shop version\'s sugar. The other half sliced into the salad with the rocket, tomato and olives, flaxseed over. Keep the sauce on the side or the salad goes to soup.')

MEALS['K-M3c'] = dict(
    name='Cold chicken, avocado and leaves',
    slot='snack', day_type='regular', kcal=648, prot=52.54,
    fixed=[('Avocado', 100), ('Romaine lettuce', 120), ('Ground flaxseed', 20)],
    free=('Chicken breast, raw', 'Olive oil'),
    instructions='Nothing to cook if you plan it: this is the extra breast you put in the airfryer at lunch, kept in the fridge. Two minutes, one bowl. It is the lowest-carbohydrate plate in the rotation, which is why it turns up on the days the other two meals are expensive.')

MEALS['K-R1'] = dict(
    name='Airfryer chicken breast, χόρτα and mushrooms',
    slot='lunch', day_type='regular', kcal=783, prot=72.09,
    fixed=[('Χόρτα (wild greens), boiled', 180), ('Mushrooms', 120),
           ('Spinach, raw', 80), ('Ground flaxseed', 12)],
    free=('Chicken breast, raw', 'Olive oil'),
    instructions='Airfryer 190C, 16-18 min. Χόρτα boiled and drained hard, mushrooms in the basket alongside the chicken, spinach wilted into them at the end. The olive oil is measured, not poured - on a rest day it is most of what separates this plate from the training-day version.')

# ── travel. Five days out of seven, so this is a rotation in its own right and
#    not a fallback: a breakfast, two lunches, two dinners, and a top-up that
#    only appears on the days he actually trains.
MEALS['K-T0'] = dict(
    name='Hotel breakfast — eggs, yogurt, cheese and olives',
    slot='breakfast', day_type='travel', kcal=700, prot=55.0,
    fixed=[('Greek yogurt 10% (στραγγιστό)', 100), ('Graviera', 30),
           ('Kalamata olives, drained', 20), ('Ground flaxseed', 15),
           ('Psyllium husk', 5)],
    free=('Egg, whole', 'Whey isolate powder'), step_a=10,
    instructions='The buffet, read correctly. Three or four eggs - boiled, or an omelette from the station if there is one. Yogurt plain, never the fruit ones. A slice of hard yellow cheese, olives, cucumber, a few walnuts. What you walk past: bread, croissants, cereal, juice, honey, jam, fruit, and the milk in the coffee if it is more than a splash. If the eggs are missing, the whey in the shaker covers the protein and you take double cheese. Tomato and cucumber off the buffet are welcome and are not counted here - a plateful costs about 2 g of net carbohydrate, which this day has room for. The flaxseed and psyllium go into the yogurt and are the reason a five-day week away does not end in a fibre drought; drink a full glass of water with them or they do the opposite. Nothing here needs a kitchen or a scale - the grams are the shape of the plate, not a rule.')

MEALS['K-T1'] = dict(
    name='Rotisserie chicken and a village salad',
    slot='lunch', day_type='travel', kcal=780, prot=72.0,
    fixed=[('Romaine lettuce', 80), ('Cucumber', 100), ('Tomato', 50),
           ('Green pepper', 40), ('Feta', 40), ('Kalamata olives, drained', 25),
           ('Ground flaxseed', 15)],
    free=('Rotisserie chicken, meat only', 'Olive oil'),
    instructions='Supermarket or ψητοπωλείο, any town, all day, about seven euros. Half a κοτόπουλο σούβλας with the meat off the bone - skin on is fine, that is where the fat is. Build the salad in the tub the deli hands you. Oil from a sachet, or carry the smallest bottle in the bag. No pita, no potatoes, no bread to mop the plate.')

MEALS['K-T4'] = dict(
    name='Σουβλάκι off the skewer, no pita, with a salad',
    slot='lunch', day_type='travel', kcal=780, prot=72.0,
    fixed=[('Romaine lettuce', 120), ('Cucumber', 80), ('Tomato', 60),
           ('Feta', 40), ('Kalamata olives, drained', 25), ('Ground flaxseed', 15)],
    free=('Chicken thigh, boneless skinless, raw', 'Olive oil'),
    instructions='Three or four καλαμάκια κοτόπουλο or χοιρινό, asked for σε μερίδα - off the skewer, on the plate, no pita and no potatoes. Every grill in Greece does this and nobody blinks. Salad on the side: μαρούλι or χωριάτικη, oil and vinegar poured by you. Tzatziki yes, ketchup and mustard no. The grams are what four skewers weigh; you are not weighing them.')

MEALS['K-T2'] = dict(
    name='Eggs, cheese and olives from anywhere',
    slot='dinner', day_type='travel', kcal=540, prot=63.0,
    fixed=[('Graviera', 25), ('Kalamata olives, drained', 25),
           ('Cucumber', 60), ('Romaine lettuce', 100), ('Ground flaxseed', 10),
           ('Psyllium husk', 6)],
    free=('Egg, whole', 'Whey isolate powder'), step_a=10,
    instructions='Mini-market grade, no kitchen. Pre-boiled eggs are on the shelf in every supermarket; failing that, boil a six-pack in the hotel kettle - twelve minutes of boiling water, poured twice. The whey is a scoop in a shaker, which is why it is here instead of four more eggs.')

MEALS['K-T6'] = dict(
    name='Taverna — grilled meat and χωριάτικη, nothing else',
    slot='dinner', day_type='travel', kcal=540, prot=63.0,
    fixed=[('Cucumber', 80), ('Tomato', 60), ('Green pepper', 40),
           ('Feta', 30), ('Kalamata olives, drained', 20),
           ('Romaine lettuce', 80), ('Psyllium husk', 6)],
    free=('Chicken breast, raw', 'Olive oil'),
    instructions='The order that works in any taverna: μπριζόλα, μπιφτέκι or κοτόπουλο σχάρας, plus a χωριάτικη, and that is the whole order. Say no to the πατάτες before they arrive - they come by default and eating half of them is the difference between this day working and not. Bread stays in the basket. If the meat comes with a lemon-oil dressing, that is fat you are already counting.')

MEALS['K-T3'] = dict(
    name='Cheese, walnuts and olives — the training-day top-up',
    slot='snack', day_type='travel', kcal=325, prot=11.0,
    fixed=[('Graviera', 40), ('Walnuts', 20), ('Kalamata olives, drained', 20)],
    free=None,
    instructions='Only on the days you actually train. A travel day that ends in a hotel room after a session is about 325 kcal short of what it cost you, and this is the difference: a wedge of hard cheese, a handful of walnuts, the olives left over from lunch. Nothing needs a fridge, and all three keep in a bag for a week. On a rest day away it is not on the plan at all - and that is deliberate, not an oversight.')

def build():
    out = {}
    for code, m in MEALS.items():
        if m['free'] is None:
            items = list(m['fixed'])
        else:
            items = solve(m['fixed'], m['free'][0], m['free'][1], m['kcal'], m['prot'],
                          step_a=m.get('step_a', 5), step_b=m.get('step_b', 1))
        out[code] = (m, items, totals(items))
    return out

# What the plan actually serves, meal by meal, for the days that do not change.
UNCHANGED = {
 'K-M1b': (892, 71.84, 16.87, 9.44, 380), 'K-M2b': (825, 66.01, 22.25, 11.01, 320),
 'K-M2c': (802, 65.73, 17.83, 8.14, 290), 'K-M3a': (647, 54.14, 24.56, 14.06, 0),
 'K-M3b': (648, 51.64, 14.03, 5.76, 150), 'K-R2': (697, 65.86, 18.41, 7.63, 300),
 'K-R3': (542, 52.48, 17.52, 8.01, 0),
}

def macro(code, built):
    if code in built:
        _, _, t = built[code]
        return t['kcal'], t['p'], t['c'], t['fib'], t['veg']
    return UNCHANGED[code]

DAYS = [
 ('Mon A  train', ['K-M1a','K-M2a','K-M3a']), ('Mon B  train', ['K-M1b','K-M2b','K-M3b']),
 ('Tue A  train', ['K-M1a','K-M2a','K-M3c']), ('Tue B  train', ['K-M1b','K-M2c','K-M3a']),
 ('Thu A  train', ['K-M1a','K-M2b','K-M3c']), ('Thu B  train', ['K-M1c','K-M2b','K-M3b']),
 ('Fri A  train', ['K-M1b','K-M2a','K-M3a']), ('Fri B  train', ['K-M1d','K-M2d','K-M3c']),
 ('rest        ', ['K-R1','K-R2','K-R3']),
 ('travel train A', ['K-T0','K-T1','K-T3','K-T2']),
 ('travel train B', ['K-T0','K-T4','K-T3','K-T6']),
 ('travel rest  A', ['K-T0','K-T1','K-T2']),
 ('travel rest  B', ['K-T0','K-T4','K-T6']),
]

def report(built):
    print('── meals ' + '─'*64)
    print(f"{'code':7} {'kcal':>6} {'prot':>6} {'carb':>6} {'fib':>6} {'net':>6} {'fat':>6} {'veg':>6}")
    for code, (m, items, t) in built.items():
        print(f"{code:7} {t['kcal']:6.0f} {t['p']:6.1f} {t['c']:6.1f} {t['fib']:6.1f} "
              f"{t['c']-t['fib']:6.1f} {t['f']:6.1f} {t['veg']:6.0f}   {m['name']}")
        for n, g in items:
            print(f"          {g:5.0f} g  {n}")
    print('\n── days ' + '─'*65)
    print(f"{'day':16} {'kcal':>6} {'prot':>6} {'net C':>6} {'fibre':>6} {'veg':>6}")
    bad = 0
    for label, codes in DAYS:
        k = p = c = fib = veg = 0.0
        for code in codes:
            a, b, cc, d, e = macro(code, built)
            k += a; p += b; c += cc; fib += d; veg += e
        net = c - fib
        flag = ''
        if net > 28: flag += '  NET CARBS OVER CAP'
        if p < 188:  flag += '  PROTEIN SHORT'
        if fib < 25: flag += '  FIBRE LOW'
        if veg < 380 and 'travel' not in label: flag += '  VEG LOW'
        if flag: bad += 1
        print(f"{label:16} {k:6.0f} {p:6.1f} {net:6.1f} {fib:6.1f} {veg:6.0f}{flag}")
    print(f"\n{bad} day(s) outside the brief")

if __name__ == '__main__' and '--sql' not in sys.argv:
    report(build())

# ────────────────────────────────────────────────────────────────────── sql
def sql(built):
    def q(t): return "'" + str(t).replace("'", "''") + "'"
    print('-- meals: generated by data/keto_rotation_v2.py, do not hand-edit the numbers')
    rows = []
    for code, (m, items, t) in built.items():
        rows.append(f"  (null, {q(code)}, {q(m['name'])}, {q(m['slot'])}, {q(m['day_type'])}, "
                    f"{t['p']:.2f}, {t['c']:.2f}, {t['f']:.2f}, {t['kcal']:.0f}, "
                    f"{t['fib']:.2f}, {t['veg']:.1f}, {q(m['instructions'])})")
    print(',\n'.join(rows))
    print('\n-- ingredients')
    rows = []
    for code, (m, items, t) in built.items():
        for i, (n, g) in enumerate(items):
            k, p, c, f, fib, veg = REF[n]
            rows.append(f"    ({q(code)}, {i}, {q(n)}, {g:.0f}, {q(ROLE[n])}, "
                        f"{k}, {p}, {c}, {f}, {fib}, {str(veg).lower()})")
    print(',\n'.join(rows))

if '--sql' in sys.argv:
    sql(build())
