import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('GuacamoleUpkeeper', () {
    test('detects outdated containers when pending in auto-update', () async {
      final upkeeper = GuacamoleUpkeeper(
        processRunner: (executable, args) async {
          if (args.contains('auto-update')) {
            return ProcessResult(0, 0, '''
[
  {
    "Unit": "guac-pod.service",
    "Container": "922eb7b54c3f",
    "ContainerName": "guacamole",
    "Image": "docker.io/guacamole/guacamole:latest",
    "Policy": "registry",
    "Updated": "pending"
  }
]
''', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).contains('Updates available for: guacamole');
    });

    test('detects up to date when none pending', () async {
      final upkeeper = GuacamoleUpkeeper(
        processRunner: (executable, args) async {
          if (args.contains('auto-update')) {
            return ProcessResult(0, 0, '''
[
  {
    "Unit": "guac-pod.service",
    "Container": "b55eb6936f75",
    "ContainerName": "guacd",
    "Image": "docker.io/guacamole/guacd:latest",
    "Policy": "registry",
    "Updated": "false"
  }
]
''', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.upToDate);
      check(status.summary).contains('Guacamole stack is up to date');
    });
  });
}
