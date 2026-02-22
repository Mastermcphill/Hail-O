import '../migration.dart';

class M0015PolicyRulesTables extends Migration {
  const M0015PolicyRulesTables();

  @override
  int get version => 15;

  @override
  String get name => 'm0015_policy_rules_tables';

  @override
  String get checksum => 'm0015_policy_rules_tables_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS pricing_rules (
      version TEXT NOT NULL,
      effective_from TEXT NOT NULL,
      scope TEXT NOT NULL,
      parameters_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY(version, scope)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_pricing_rules_scope_effective
    ON pricing_rules(scope, effective_from DESC)
    ''',
    '''
    CREATE TABLE IF NOT EXISTS penalty_rules (
      version TEXT NOT NULL,
      effective_from TEXT NOT NULL,
      scope TEXT NOT NULL,
      parameters_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY(version, scope)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_penalty_rules_scope_effective
    ON penalty_rules(scope, effective_from DESC)
    ''',
    '''
    CREATE TABLE IF NOT EXISTS compliance_requirements (
      id TEXT PRIMARY KEY,
      scope TEXT NOT NULL,
      from_country TEXT,
      to_country TEXT,
      required_docs_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(scope, from_country, to_country)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_compliance_requirements_scope
    ON compliance_requirements(scope, from_country, to_country)
    ''',
    '''
    INSERT OR IGNORE INTO pricing_rules(version, effective_from, scope, parameters_json, created_at)
    VALUES(
      'pricing_v1',
      '2020-01-01T00:00:00.000Z',
      'default',
      '{"base_fare_minor":{"intra_city":15000,"inter_state":40000,"cross_country":70000,"international":120000},"distance_rate_per_km_minor":{"intra_city":2000,"inter_state":5000,"cross_country":7000,"international":9000},"time_rate_per_min_minor":{"intra_city":150,"inter_state":300,"cross_country":400,"international":500},"vehicle_multiplier_percent":{"sedan":100,"hatchback":95,"suv":120,"bus":150},"luggage_surcharge_per_extra_minor":2000,"surge_windows":[{"from_hour":7,"to_hour":10,"percent":10},{"from_hour":17,"to_hour":20,"percent":10}]}',
      '2020-01-01T00:00:00.000Z'
    )
    ''',
    '''
    INSERT OR IGNORE INTO penalty_rules(version, effective_from, scope, parameters_json, created_at)
    VALUES(
      'penalty_v1',
      '2020-01-01T00:00:00.000Z',
      'default',
      '{"intra":{"late_fee_minor":50000,"late_if_cancelled_at_or_after_departure":true},"inter":{"gt_hours":10,"gt_hours_percent":10,"lte_hours_percent":30},"international":{"lt_hours":24,"lt_hours_percent":50,"gte_hours_percent":0}}',
      '2020-01-01T00:00:00.000Z'
    )
    ''',
    '''
    INSERT OR IGNORE INTO compliance_requirements(id, scope, from_country, to_country, required_docs_json, created_at)
    VALUES(
      'compliance_cross_country_default',
      'cross_country',
      NULL,
      NULL,
      '{"requires_next_of_kin":true,"allowed_doc_types":["passport","ecowas_id"],"requires_verified":true,"requires_not_expired":true}',
      '2020-01-01T00:00:00.000Z'
    )
    ''',
    '''
    INSERT OR IGNORE INTO compliance_requirements(id, scope, from_country, to_country, required_docs_json, created_at)
    VALUES(
      'compliance_international_default',
      'international',
      NULL,
      NULL,
      '{"requires_next_of_kin":true,"allowed_doc_types":["passport","ecowas_id"],"requires_verified":true,"requires_not_expired":true}',
      '2020-01-01T00:00:00.000Z'
    )
    ''',
  ];
}
