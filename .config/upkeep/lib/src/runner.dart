import 'models.dart';
import 'upkeepers/upkeepers.dart';

class UpkeepRunner {
  final List<Upkeeper> upkeepers;

  UpkeepRunner({List<Upkeeper>? upkeepers})
    : upkeepers =
          upkeepers ??
          [
            BrewUpkeeper(),
            BrewfileUpkeeper(),
            MiseUpkeeper(),
            // Refresh `dart install` binaries before pulling dotfiles: the
            // dotfiles tree ships `_kscripts_shim` symlinks that dispatch to
            // `kscripts <subcommand>`, so landing a new shim ahead of the
            // binary that knows the subcommand breaks that command until the
            // next run. `updateSelected` runs in this order.
            DartInstallUpkeeper(),
            DotfilesUpkeeper(),
            DotfilesCorpUpkeeper(),
            GuacamoleUpkeeper(),
            SkillsUpkeeper(),
            DartPubGlobalUpkeeper(),
            ScriptsDartUpkeeper(),
            FlutterRepoUpkeeper(),
            OsUpkeeper(),
            BeadsDoltUpkeeper(),
            VscodeUpkeeper(),
          ];

  /// Checks status across supported upkeepers concurrently.
  /// Option to filter by [targetIds] (case-insensitive exact match).
  Future<List<UpkeepStatus>> checkAll({List<String>? targetIds}) async {
    final supportedList = <Upkeeper>[];
    for (final u in upkeepers) {
      if (targetIds != null && targetIds.isNotEmpty) {
        final matches = targetIds.any(
          (t) => u.id.toLowerCase() == t.toLowerCase(),
        );
        if (!matches) continue;
      }
      if (await u.isSupported()) {
        supportedList.add(u);
      }
    }

    final futures = supportedList.map((u) => u.check());
    final results = await Future.wait(futures);
    return results;
  }

  /// Runs update on specified upkeeper IDs sequentially (case-insensitive exact match).
  Future<List<UpkeepResult>> updateSelected(
    List<String> targetIds, {
    bool verbose = false,
    bool cleanup = false,
  }) async {
    final results = <UpkeepResult>[];
    final selected = upkeepers.where(
      (u) => targetIds.any((t) => u.id.toLowerCase() == t.toLowerCase()),
    );

    for (final u in selected) {
      final res = u is BrewfileUpkeeper
          ? await u.update(verbose: verbose, cleanup: cleanup)
          : await u.update(verbose: verbose);
      results.add(res);
    }

    return results;
  }
}
