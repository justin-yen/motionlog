-- Development prescription for the fixed Supabase test-phone account.
-- Safe to re-run because every seeded row has a stable ID.

insert into public.exercises (id, owner_id, name, tracking_mode, instructions, pt_note)
values
  (
    '10000000-0000-4000-8000-000000000001',
    '99e0c9ae-24b0-461a-af87-29684b15bfee',
    'Shoulder flexion wall slide (facing wall)',
    'reps',
    array['Face the wall.', 'Slide both arms upward without shrugging.', 'Return with control.'],
    'Stay in a comfortable range and avoid forcing through pain.'
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    '99e0c9ae-24b0-461a-af87-29684b15bfee',
    'Shoulder flexion wall slide (facing forward)',
    'reps',
    array['Stand facing forward with your back near the wall.', 'Slide both arms upward without shrugging.', 'Return with control.'],
    'Keep the movement smooth and stay in a comfortable range.'
  ),
  (
    '10000000-0000-4000-8000-000000000003',
    '99e0c9ae-24b0-461a-af87-29684b15bfee',
    'Thoracic twist',
    'reps',
    array['Set your trunk in a stable starting position.', 'Rotate through the upper back.', 'Return with control and repeat on the other side.'],
    'Complete the prescribed repetitions on each side.'
  ),
  (
    '10000000-0000-4000-8000-000000000004',
    '99e0c9ae-24b0-461a-af87-29684b15bfee',
    'Plank into downward dog',
    'reps',
    array['Begin in a strong plank.', 'Press your hips back and up into downward dog.', 'Return to plank with control.'],
    'Keep the transition controlled.'
  )
on conflict (id) do update set
  name = excluded.name,
  tracking_mode = excluded.tracking_mode,
  instructions = excluded.instructions,
  pt_note = excluded.pt_note;

insert into public.routines (id, owner_id, title, scheduled_for)
values (
  '20000000-0000-4000-8000-000000000001',
  '99e0c9ae-24b0-461a-af87-29684b15bfee',
  'Shoulder and thoracic routine',
  '2026-11-06'
)
on conflict (owner_id, scheduled_for) do update set
  title = excluded.title;

insert into public.routine_items (
  id, owner_id, routine_id, exercise_id, position,
  target_sets, target_reps, prescription_notes
)
values
  (
    '30000000-0000-4000-8000-000000000001',
    '99e0c9ae-24b0-461a-af87-29684b15bfee',
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    0, 3, 10, 'Facing wall.'
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    '99e0c9ae-24b0-461a-af87-29684b15bfee',
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    1, 3, 10, 'Facing forward.'
  ),
  (
    '30000000-0000-4000-8000-000000000003',
    '99e0c9ae-24b0-461a-af87-29684b15bfee',
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000003',
    2, 3, 10, '10 repetitions on each side.'
  ),
  (
    '30000000-0000-4000-8000-000000000004',
    '99e0c9ae-24b0-461a-af87-29684b15bfee',
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004',
    3, 3, 10, null
  )
on conflict (id) do update set
  position = excluded.position,
  target_sets = excluded.target_sets,
  target_reps = excluded.target_reps,
  prescription_notes = excluded.prescription_notes;
