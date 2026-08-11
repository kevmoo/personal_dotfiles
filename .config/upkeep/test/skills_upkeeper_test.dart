import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('SkillsUpkeeper', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('skills_upkeep_test_');
    });

    tearDown(() async {
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('isSupported is false when no skills setup exists', () async {
      final upkeeper = SkillsUpkeeper(homeDirOverride: tempHome.path);

      check(await upkeeper.isSupported()).isFalse();
    });
  });
}
