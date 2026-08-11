import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

class MockUpkeeper implements Upkeeper {
  @override
  final String id;
  @override
  final String displayName;
  final bool supported;
  final UpkeepStatus statusToReturn;

  MockUpkeeper({
    required this.id,
    required this.displayName,
    this.supported = true,
    required this.statusToReturn,
  });

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<UpkeepStatus> check() async => statusToReturn;

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    return UpkeepResult(
      upkeeperId: id,
      displayName: displayName,
      success: true,
      message: 'Mock update succeeded',
    );
  }
}

void main() {
  group('UpkeepRunner Concurrent Execution', () {
    test(
      'Runner filters unsupported upkeepers and checks in parallel',
      () async {
        final mock1 = MockUpkeeper(
          id: 'supported_1',
          displayName: 'Supported 1',
          supported: true,
          statusToReturn: const UpkeepStatus(
            upkeeperId: 'supported_1',
            displayName: 'Supported 1',
            state: UpkeepState.upToDate,
            summary: 'All clear',
          ),
        );

        final mock2 = MockUpkeeper(
          id: 'unsupported_1',
          displayName: 'Unsupported 1',
          supported: false,
          statusToReturn: const UpkeepStatus(
            upkeeperId: 'unsupported_1',
            displayName: 'Unsupported 1',
            state: UpkeepState.skipped,
            summary: 'Skipped',
          ),
        );

        final runner = UpkeepRunner(upkeepers: [mock1, mock2]);
        final statuses = await runner.checkAll();

        check(statuses.length).equals(1);
        check(statuses.first.upkeeperId).equals('supported_1');
        check(statuses.first.state).equals(UpkeepState.upToDate);
      },
    );

    test('Runner filters by targetIds in checkAll', () async {
      final mock1 = MockUpkeeper(
        id: 'brew',
        displayName: 'Brew Subsystem',
        statusToReturn: const UpkeepStatus(
          upkeeperId: 'brew',
          displayName: 'Brew Subsystem',
          state: UpkeepState.upToDate,
          summary: 'All clear',
        ),
      );

      final mock2 = MockUpkeeper(
        id: 'mise',
        displayName: 'Mise Subsystem',
        statusToReturn: const UpkeepStatus(
          upkeeperId: 'mise',
          displayName: 'Mise Subsystem',
          state: UpkeepState.outdated,
          summary: 'Outdated',
        ),
      );

      final runner = UpkeepRunner(upkeepers: [mock1, mock2]);
      final statuses = await runner.checkAll(targetIds: ['brew']);

      check(statuses.length).equals(1);
      check(statuses.first.upkeeperId).equals('brew');
    });

    test(
      'Runner strict exact matching does not select brewfile for target brew',
      () async {
        final mockBrew = MockUpkeeper(
          id: 'brew',
          displayName: 'Brew Subsystem',
          statusToReturn: const UpkeepStatus(
            upkeeperId: 'brew',
            displayName: 'Brew Subsystem',
            state: UpkeepState.upToDate,
            summary: 'All clear',
          ),
        );

        final mockBrewfile = MockUpkeeper(
          id: 'brewfile',
          displayName: 'Brewfile Subsystem',
          statusToReturn: const UpkeepStatus(
            upkeeperId: 'brewfile',
            displayName: 'Brewfile Subsystem',
            state: UpkeepState.upToDate,
            summary: 'All clear',
          ),
        );

        final runner = UpkeepRunner(upkeepers: [mockBrew, mockBrewfile]);
        final statuses = await runner.checkAll(targetIds: ['brew']);

        check(statuses.length).equals(1);
        check(statuses.first.upkeeperId).equals('brew');
      },
    );

    test('Runner executes selected updates', () async {
      final mock1 = MockUpkeeper(
        id: 'sub1',
        displayName: 'Subsystem 1',
        statusToReturn: const UpkeepStatus(
          upkeeperId: 'sub1',
          displayName: 'Subsystem 1',
          state: UpkeepState.outdated,
          summary: 'Outdated',
        ),
      );

      final runner = UpkeepRunner(upkeepers: [mock1]);
      final updateResults = await runner.updateSelected(['sub1']);

      check(updateResults.length).equals(1);
      check(updateResults.first.success).isTrue();
      check(updateResults.first.upkeeperId).equals('sub1');
    });
  });
}
