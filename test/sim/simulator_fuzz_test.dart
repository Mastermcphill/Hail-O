import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'scenario_runner.dart';
import 'sim_types.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Deterministic simulation harness', () {
    const seeds = <int>[1337, 20260212, 9001, 42, 77];
    const scenariosPerSeed = 10;
    const stepsPerScenario = 40;

    for (final seed in seeds) {
      test(
        'seed $seed is deterministic for $scenariosPerSeed x $stepsPerScenario',
        () async {
          final first = await _runSeedBatch(
            seed: seed,
            scenariosPerSeed: scenariosPerSeed,
            stepsPerScenario: stepsPerScenario,
          );
          final second = await _runSeedBatch(
            seed: seed,
            scenariosPerSeed: scenariosPerSeed,
            stepsPerScenario: stepsPerScenario,
          );

          expect(
            first.map((result) => result.deterministicDigest()).toList(),
            second.map((result) => result.deterministicDigest()).toList(),
          );

          for (final result in first) {
            expect(
              result.ok,
              true,
              reason:
                  'scenario ${result.scenarioId} failed: ${result.errorType}\n${result.reportJson}',
            );
          }
        },
      );
    }

    test(
      'invalid transition scenario fails with typed domain error and writes report JSON',
      () async {
        final db = await HailODatabase().open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(db.close);

        final scenarioId = 'invalid_alt_accept';
        final config = SimScenarioConfig(
          seed: 1337,
          scenarioId: scenarioId,
          stepCount: 3,
          entityIds: SimEntityIds(
            rideId: 'ride_$scenarioId',
            riderId: 'rider_$scenarioId',
            driverId: 'driver_$scenarioId',
            altDriverId: 'driver_alt_$scenarioId',
            adminId: 'admin_$scenarioId',
            escrowId: 'escrow_$scenarioId',
            disputeId: 'dispute_$scenarioId',
          ),
        );
        final runner = ScenarioRunner(
          db,
          startUtc: DateTime.utc(2026, 2, 12, 0, 0),
          writeArtifactsOnFailure: true,
        );

        final result = await runner.runScenario(
          config: config,
          steps: const <SimStepType>[
            SimStepType.bookRide,
            SimStepType.acceptRide,
            SimStepType.acceptRideAltDriver,
          ],
        );

        expect(result.ok, false);
        expect(result.errorType, 'DomainInvariantError');
        expect(result.errorCode, 'ride_already_accepted');
        expect(result.reportJson, isNotNull);

        final artifact = File(
          'test_artifacts/sim_${config.seed}_${config.scenarioId}_failure.json',
        );
        expect(artifact.existsSync(), true);
        final artifactBody = artifact.readAsStringSync();
        expect(artifactBody.contains('ride_already_accepted'), true);
      },
    );
  });
}

Future<List<SimScenarioResult>> _runSeedBatch({
  required int seed,
  required int scenariosPerSeed,
  required int stepsPerScenario,
}) async {
  final results = <SimScenarioResult>[];
  for (
    var scenarioIndex = 0;
    scenarioIndex < scenariosPerSeed;
    scenarioIndex++
  ) {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    final scenarioId = 'seed_${seed}_$scenarioIndex';
    final config = SimScenarioConfig(
      seed: seed,
      scenarioId: scenarioId,
      stepCount: stepsPerScenario,
      entityIds: SimEntityIds(
        rideId: 'ride_$scenarioId',
        riderId: 'rider_$scenarioId',
        driverId: 'driver_$scenarioId',
        altDriverId: 'driver_alt_$scenarioId',
        adminId: 'admin_$scenarioId',
        escrowId: 'escrow_$scenarioId',
        disputeId: 'dispute_$scenarioId',
      ),
    );

    final runner = ScenarioRunner(
      db,
      startUtc: DateTime.utc(2026, 2, 12, 0, 0),
      writeArtifactsOnFailure: false,
    );
    final result = await runner.runRandomScenario(config);
    results.add(result);
    await db.close();
  }
  return results;
}
