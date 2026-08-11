import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('Cloudtop Upkeepers Gating', () {
    test('BrewUpkeeper isSupported returns false on cloudtop', () async {
      final upkeeper = BrewUpkeeper(isCloudtopOverride: true);
      check(await upkeeper.isSupported()).isFalse();
    });

    test('BrewfileUpkeeper isSupported returns false on cloudtop', () async {
      final upkeeper = BrewfileUpkeeper(isCloudtopOverride: true);
      check(await upkeeper.isSupported()).isFalse();
    });

    test('VscodeUpkeeper isSupported returns false on cloudtop', () async {
      final upkeeper = VscodeUpkeeper(isCloudtopOverride: true);
      check(await upkeeper.isSupported()).isFalse();
    });
  });
}
