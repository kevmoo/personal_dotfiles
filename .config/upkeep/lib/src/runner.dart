import 'models.dart';
import 'upkeepers/upkeepers.dart';

class UpkeepRunner {
  final List<Upkeeper> upkeepers;

  UpkeepRunner({List<Upkeeper>? upkeepers})
      : upkeepers = upkeepers ??
            [
              BrewUpkeeper(),
              BrewfileUpkeeper(),
              MiseUpkeeper(),
              DotfilesUpkeeper(),
              SkillsUpkeeper(),
              ScriptsDartUpkeeper(),
              OsUpkeeper(),
            ];

  /// Checks status across supported upkeepers concurrently.
  /// Option to filter by [targetIds] (case-insensitive substring match).
  Future<List<UpkeepStatus>> checkAll({List<String>? targetIds}) async {
    final supportedList = <Upkeeper>[];
    for (final u in upkeepers) {
      if (targetIds != null && targetIds.isNotEmpty) {
        final matches =
            targetIds.any((t) => u.id.toLowerCase().contains(t.toLowerCase()));
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

  /// Runs update on specified upkeeper IDs sequentially.
  Future<List<UpkeepResult>> updateSelected(
    List<String> targetIds, {
    bool verbose = false,
  }) async {
    final results = <UpkeepResult>[];
    final selected = upkeepers.where((u) => targetIds.contains(u.id));

    for (final u in selected) {
      final res = await u.update(verbose: verbose);
      results.add(res);
    }

    return results;
  }
}
