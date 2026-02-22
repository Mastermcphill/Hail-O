import '../migration.dart';

class M0017RuleRollouts extends Migration {
  const M0017RuleRollouts();

  @override
  int get version => 17;

  @override
  String get name => 'm0017_rule_rollouts';

  @override
  String get checksum => 'm0017_rule_rollouts_v1';

  @override
  List<String> get upSql => <String>[
    '''
    ALTER TABLE pricing_rules
    ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1))
    ''',
    '''
    ALTER TABLE pricing_rules
    ADD COLUMN rollout_percent INTEGER NOT NULL DEFAULT 100 CHECK(rollout_percent >= 0 AND rollout_percent <= 100)
    ''',
    '''
    ALTER TABLE pricing_rules
    ADD COLUMN rollout_salt TEXT NOT NULL DEFAULT 'default'
    ''',
    '''
    ALTER TABLE penalty_rules
    ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1))
    ''',
    '''
    ALTER TABLE penalty_rules
    ADD COLUMN rollout_percent INTEGER NOT NULL DEFAULT 100 CHECK(rollout_percent >= 0 AND rollout_percent <= 100)
    ''',
    '''
    ALTER TABLE penalty_rules
    ADD COLUMN rollout_salt TEXT NOT NULL DEFAULT 'default'
    ''',
    '''
    ALTER TABLE compliance_requirements
    ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1))
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_pricing_rules_scope_enabled_effective
    ON pricing_rules(scope, enabled, effective_from DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_pricing_rules_scope_version
    ON pricing_rules(scope, version DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_penalty_rules_scope_enabled_effective
    ON penalty_rules(scope, enabled, effective_from DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_penalty_rules_scope_version
    ON penalty_rules(scope, version DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_compliance_requirements_lookup_enabled
    ON compliance_requirements(scope, from_country, to_country, enabled)
    ''',
  ];
}
