import '../models.dart';

abstract class Upkeeper {
  /// Unique identifier for this upkeeper (e.g. 'brew', 'mise').
  String get id;

  /// Human-readable display name.
  String get displayName;

  /// Check if this upkeeper is applicable/supported on the current host/environment.
  Future<bool> isSupported();

  /// Perform a non-destructive status check across the subsystem.
  Future<UpkeepStatus> check();

  /// Apply updates for this subsystem.
  Future<UpkeepResult> update({bool verbose = false});
}
