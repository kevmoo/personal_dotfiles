import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('Upkeep Models & Serialization', () {
    test('UpkeepStatus toJson serialization', () {
      final status = UpkeepStatus(
        upkeeperId: 'test_id',
        displayName: 'Test Subsystem',
        state: UpkeepState.outdated,
        summary: '2 updates pending',
        details: ['Item A', 'Item B'],
      );

      final json = status.toJson();
      check(json['id']).equals('test_id');
      check(json['state']).equals('outdated');
      check(json['summary']).equals('2 updates pending');
      check((json['details'] as List).length).equals(2);
    });
  });
}
