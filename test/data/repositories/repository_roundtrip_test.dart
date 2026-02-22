import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/repositories/sqlite_driver_profile_repository.dart';
import 'package:hail_o_finance_core/data/repositories/sqlite_manifest_repository.dart';
import 'package:hail_o_finance_core/data/repositories/sqlite_moneybox_repository.dart';
import 'package:hail_o_finance_core/data/repositories/sqlite_route_repository.dart';
import 'package:hail_o_finance_core/data/repositories/sqlite_seat_repository.dart';
import 'package:hail_o_finance_core/data/repositories/sqlite_user_repository.dart';
import 'package:hail_o_finance_core/data/repositories/sqlite_vehicle_repository.dart';
import 'package:hail_o_finance_core/data/repositories/sqlite_wallet_repository.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/driver_profiles_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/manifest_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/moneybox_accounts_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/moneybox_ledger_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/routes_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/seats_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/users_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/vehicles_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/wallet_ledger_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/wallets_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/data/sqlite/table_names.dart';
import 'package:hail_o_finance_core/domain/models/driver_profile.dart';
import 'package:hail_o_finance_core/domain/models/manifest_entry.dart';
import 'package:hail_o_finance_core/domain/models/moneybox_account.dart';
import 'package:hail_o_finance_core/domain/models/moneybox_ledger_entry.dart';
import 'package:hail_o_finance_core/domain/models/route_chain.dart';
import 'package:hail_o_finance_core/domain/models/route_node.dart';
import 'package:hail_o_finance_core/domain/models/seat.dart';
import 'package:hail_o_finance_core/domain/models/user.dart';
import 'package:hail_o_finance_core/domain/models/vehicle.dart';
import 'package:hail_o_finance_core/domain/models/wallet.dart';
import 'package:hail_o_finance_core/domain/models/wallet_ledger_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('repository roundtrip for core entities and ledgers', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);

    final userRepo = SqliteUserRepository(UsersDao(db));
    final profileRepo = SqliteDriverProfileRepository(DriverProfilesDao(db));
    final vehicleRepo = SqliteVehicleRepository(VehiclesDao(db));
    final routeRepo = SqliteRouteRepository(RoutesDao(db));
    final seatRepo = SqliteSeatRepository(SeatsDao(db));
    final manifestRepo = SqliteManifestRepository(ManifestDao(db));
    final walletRepo = SqliteWalletRepository(
      walletsDao: WalletsDao(db),
      walletLedgerDao: WalletLedgerDao(db),
    );
    final moneyBoxRepo = SqliteMoneyBoxRepository(
      accountsDao: MoneyBoxAccountsDao(db),
      ledgerDao: MoneyBoxLedgerDao(db),
    );

    final now = DateTime.utc(2026, 2, 1, 9, 0);

    final driver = User(
      id: 'driver_repo_1',
      role: UserRole.driver,
      email: 'driver@hailo.dev',
      displayName: 'Driver One',
      createdAt: now,
      updatedAt: now,
    );
    final rider = User(
      id: 'rider_repo_1',
      role: UserRole.rider,
      email: 'rider@hailo.dev',
      displayName: 'Rider One',
      createdAt: now,
      updatedAt: now,
    );
    await userRepo.createUser(driver);
    await userRepo.createUser(rider);

    final loadedDriver = await userRepo.getUser(driver.id);
    expect(loadedDriver?.displayName, 'Driver One');

    await userRepo.updateUser(
      User(
        id: driver.id,
        role: UserRole.driver,
        email: driver.email,
        displayName: 'Driver One Updated',
        createdAt: driver.createdAt,
        updatedAt: now.add(const Duration(minutes: 1)),
      ),
    );
    expect(
      (await userRepo.getUser(driver.id))?.displayName,
      'Driver One Updated',
    );

    await profileRepo.upsertProfile(
      DriverProfile(
        driverId: driver.id,
        cashDebtMinor: 0,
        safetyScore: 82,
        status: 'active',
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect((await profileRepo.getProfile(driver.id))?.safetyScore, 82);

    await vehicleRepo.upsertVehicle(
      Vehicle(
        id: 'vehicle_repo_1',
        driverId: driver.id,
        type: VehicleType.suv,
        plateNumber: 'LAG-100-AA',
        seatCount: 4,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(
      (await vehicleRepo.getVehicle('vehicle_repo_1'))?.type,
      VehicleType.suv,
    );

    final route = RouteChain(
      id: 'route_repo_1',
      driverId: driver.id,
      origin: 'Lagos',
      destination: 'Benin',
      totalDistanceKm: 320,
      status: 'active',
      createdAt: now,
      updatedAt: now,
    );
    await routeRepo.upsertRoute(route);
    await routeRepo.addRouteNode(
      RouteNode(
        id: 'route_node_1',
        routeId: route.id,
        sequenceNo: 1,
        label: 'Lagos',
        createdAt: now,
      ),
    );
    await routeRepo.addRouteNode(
      RouteNode(
        id: 'route_node_2',
        routeId: route.id,
        sequenceNo: 2,
        label: 'Ibadan',
        createdAt: now,
      ),
    );
    expect((await routeRepo.getRoute(route.id))?.nodes.length, 2);

    await db.insert(TableNames.rides, <String, Object?>{
      'id': 'ride_repo_1',
      'rider_id': rider.id,
      'driver_id': driver.id,
      'route_id': route.id,
      'pickup_node_id': 'route_node_1',
      'dropoff_node_id': 'route_node_2',
      'trip_scope': 'inter_state',
      'status': 'booked',
      'bidding_mode': 1,
      'base_fare_minor': 150000,
      'premium_markup_minor': 0,
      'charter_mode': 0,
      'daily_rate_minor': 0,
      'total_fare_minor': 150000,
      'connection_fee_minor': 10000,
      'connection_fee_paid': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await seatRepo.upsertSeat(
      Seat(
        id: 'seat_repo_1',
        rideId: 'ride_repo_1',
        seatCode: SeatCode.frontRight,
        seatType: SeatType.front,
        baseFareMinor: 150000,
        markupMinor: 15000,
        assignmentLocked: true,
        passengerUserId: rider.id,
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect((await seatRepo.listRideSeats('ride_repo_1')).length, 1);

    await manifestRepo.upsertEntry(
      ManifestEntry(
        id: 'manifest_repo_1',
        rideId: 'ride_repo_1',
        riderId: rider.id,
        seatId: 'seat_repo_1',
        status: 'confirmed',
        nextOfKinValid: true,
        docValid: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect((await manifestRepo.listRideEntries('ride_repo_1')).length, 1);

    await walletRepo.upsertWallet(
      Wallet(
        ownerId: driver.id,
        walletType: WalletType.driverA,
        balanceMinor: 120000,
        reservedMinor: 0,
        currency: 'NGN',
        updatedAt: now,
        createdAt: now,
      ),
    );
    await walletRepo.appendLedger(
      WalletLedgerEntry(
        ownerId: driver.id,
        walletType: WalletType.driverA,
        direction: LedgerDirection.credit,
        amountMinor: 120000,
        balanceAfterMinor: 120000,
        kind: 'ride_base_share',
        referenceId: 'ride_repo_1',
        idempotencyScope: 'wallet.credit',
        idempotencyKey: 'wallet_repo_test_1',
        createdAt: now,
      ),
    );
    expect(
      (await walletRepo.listLedger(driver.id, WalletType.driverA)).length,
      1,
    );

    await moneyBoxRepo.upsertAccount(
      MoneyBoxAccount(
        ownerId: driver.id,
        tier: MoneyBoxTier.tier2,
        status: 'locked',
        principalMinor: 20000,
        projectedBonusMinor: 600,
        expectedAtMaturityMinor: 20600,
        autosavePercent: 10,
        bonusEligible: true,
        lockStart: now,
        autoOpenDate: now.add(const Duration(days: 120)),
        maturityDate: now.add(const Duration(days: 120)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await moneyBoxRepo.appendLedger(
      MoneyBoxLedgerEntry(
        ownerId: driver.id,
        entryType: 'autosave_in',
        amountMinor: 20000,
        principalAfterMinor: 20000,
        projectedBonusAfterMinor: 600,
        expectedAfterMinor: 20600,
        sourceKind: 'confirmed_commission_credit',
        referenceId: 'ride_repo_1',
        idempotencyScope: 'moneybox.autosave',
        idempotencyKey: 'moneybox_repo_test_1',
        createdAt: now,
      ),
    );
    expect((await moneyBoxRepo.listLedger(driver.id)).length, 1);
  });
}
