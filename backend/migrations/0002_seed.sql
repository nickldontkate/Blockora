-- Seed data: a starter contract, a starter mission, a launch world event,
-- and the single shared world project. Safe to re-run only once (relies on
-- the UNIQUE(code) constraints) — do not re-apply after edits, add a new
-- migration instead.

INSERT INTO contracts (
  id, code, title, description, required_resources_json,
  reward_coins, reward_blocks, reward_module_pack_json,
  duration_seconds, min_city_level, available_from, available_until, created_at
) VALUES (
  'ctr_seed_goods_starter',
  'GOODS_SUPPLY_RUN_1',
  'Goods Supply Run',
  'The transit authority needs a batch of manufactured goods to open the new district.',
  '{"GOODS": 250}',
  500,
  0,
  '[{"moduleType":"STORAGE","quantity":1}]',
  86400,
  1,
  strftime('%s','now'),
  NULL,
  strftime('%s','now')
);

INSERT INTO missions (
  id, code, title, description, requirements_json, reward_json, repeatable, created_at
) VALUES (
  'msn_seed_first_module',
  'PLACE_FIRST_MODULE',
  'Break Ground',
  'Place your first module in any building.',
  '{"type":"place_module","count":1}',
  '{"COINS": 100}',
  0,
  strftime('%s','now')
);

INSERT INTO world_events (
  id, code, title, description, modifiers_json, starts_at, ends_at, created_at
) VALUES (
  'evt_seed_tech_boom',
  'TECH_BOOM',
  'Tech Boom',
  'City-wide demand for Data has spiked, boosting Data contract rewards.',
  '[{"resource":"DATA","kind":"demand","percent":80}]',
  strftime('%s','now'),
  strftime('%s','now', '+3 days'),
  strftime('%s','now')
);

INSERT INTO world_projects (
  id, code, title, description, goal_resources_json, progress_json, status, reward_json, started_at
) VALUES (
  'wp_seed_orbital_elevator',
  'orbital_elevator_s1',
  'The Orbital Elevator',
  'Every mayor in BLOCKORA is pooling resources to build the first Orbital Elevator.',
  '{"GOODS": 500000, "DATA": 120000, "ENERGY": 250000}',
  '{"GOODS": 0, "DATA": 0, "ENERGY": 0}',
  'active',
  '{"BLOCKS": 50, "module_pack": [{"moduleType":"CORE","quantity":1}]}',
  strftime('%s','now')
);
