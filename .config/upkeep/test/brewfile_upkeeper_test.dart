import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('BrewfileUpkeeper', () {
    late Directory tempHome;
    late File sharedBrewfile;
    late File macBrewfile;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('brewfile_test_');
      final brewDir = Directory('${tempHome.path}/.config/brew')
        ..createSync(recursive: true);
      sharedBrewfile = File('${brewDir.path}/Brewfile.shared')
        ..writeAsStringSync('brew "bat"\n');
      macBrewfile = File('${brewDir.path}/Brewfile.mac')
        ..writeAsStringSync('cask "vscodium"\n');
    });

    tearDown(() async {
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test(
      'check returns needsTriage when only unmanaged packages exist',
      () async {
        final upkeeper = BrewfileUpkeeper(
          isCloudtopOverride: false,
          isMacOSOverride: true,
          homeDirOverride: () => tempHome.path,
          processRunner: _fakeBrewRunner(
            leaves: ['bat', 'ffmpeg'],
            formulae: ['bat', 'ffmpeg'],
            casks: ['vscodium'],
          ),
        );

        final status = await upkeeper.check();
        check(status.state).equals(UpkeepState.needsTriage);
        check(status.isOutdated).isFalse();
        check(status.isNeedsTriage).isTrue();
        check(status.summary).equals('1 unmanaged in Brewfile');
        check(status.actionHint).equals('upkeep triage');
        check(status.details).deepEquals(['Unmanaged formula: ffmpeg']);
      },
    );

    test(
      'check returns outdated when missing packages exist alongside unmanaged',
      () async {
        final upkeeper = BrewfileUpkeeper(
          isCloudtopOverride: false,
          isMacOSOverride: true,
          homeDirOverride: () => tempHome.path,
          processRunner: _fakeBrewRunner(
            leaves: ['ffmpeg'],
            formulae: ['ffmpeg'],
            casks: ['vscodium'],
          ),
        );

        final status = await upkeeper.check();
        check(status.state).equals(UpkeepState.outdated);
        check(status.summary)
            .equals('1 missing from Brewfile, 1 unmanaged in Brewfile');
        check(status.actionHint).equals('upkeep triage');
        check(status.details)
            .deepEquals(['Missing formula: bat', 'Unmanaged formula: ffmpeg']);
      },
    );

    test(
      'triageInteractive supports remove, mac, shared, and do nothing',
      () async {
        final invoked = <String>[];
        final inputs = <String>['r', 'm', 's', 'd'];
        var inputIndex = 0;
        final output = StringBuffer();

        final upkeeper = BrewfileUpkeeper(
          isCloudtopOverride: false,
          isMacOSOverride: true,
          homeDirOverride: () => tempHome.path,
          inputReader: () => inputs[inputIndex++],
          outputWriter: output.write,
          processRunner: (executable, args) async {
            invoked.add('$executable ${args.join(' ')}');
            if (args.length == 1 && args.first == 'leaves') {
              return ProcessResult(0, 0, 'bat\nffmpeg\nhtop\njq\ntree\n', '');
            }
            if (args.contains('--formula')) {
              return ProcessResult(0, 0, 'bat\nffmpeg\nhtop\njq\ntree\n', '');
            }
            if (args.contains('--cask')) {
              return ProcessResult(0, 0, 'vscodium\n', '');
            }
            return ProcessResult(0, 0, '', '');
          },
        );

        await upkeeper.triageInteractive();

        // (a) 'r' -> brew uninstall ffmpeg
        check(invoked).contains('brew uninstall ffmpeg');
        check(output.toString()).contains("Removed 'ffmpeg'");

        // (b) 'm' -> added htop to Brewfile.mac
        check(macBrewfile.readAsStringSync()).contains('brew "htop"\n');

        // (c) 's' -> added jq to Brewfile.shared
        check(sharedBrewfile.readAsStringSync()).contains('brew "jq"\n');

        // (d) 'd' -> skipped tree
        check(output.toString()).contains("Skipped 'tree'");
        check(sharedBrewfile.readAsStringSync()).not((c) => c.contains('tree'));
        check(macBrewfile.readAsStringSync()).not((c) => c.contains('tree'));
      },
    );
  });
}

ProcessRunner _fakeBrewRunner({
  required List<String> leaves,
  required List<String> formulae,
  required List<String> casks,
}) {
  return (executable, args) async {
    if (args.length == 1 && args.first == 'leaves') {
      return ProcessResult(0, 0, '${leaves.join('\n')}\n', '');
    }
    if (args.contains('--formula')) {
      return ProcessResult(0, 0, '${formulae.join('\n')}\n', '');
    }
    if (args.contains('--cask')) {
      return ProcessResult(0, 0, '${casks.join('\n')}\n', '');
    }
    return ProcessResult(0, 0, '', '');
  };
}
