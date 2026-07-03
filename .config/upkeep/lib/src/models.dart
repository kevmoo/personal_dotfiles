enum UpkeepState {
  upToDate,
  outdated,
  error,
  skipped,
}

class UpkeepStatus {
  final String upkeeperId;
  final String displayName;
  final UpkeepState state;
  final String summary;
  final List<String> details;
  final String? errorMessage;

  const UpkeepStatus({
    required this.upkeeperId,
    required this.displayName,
    required this.state,
    required this.summary,
    this.details = const [],
    this.errorMessage,
  });

  bool get isOutdated => state == UpkeepState.outdated;
  bool get isUpToDate => state == UpkeepState.upToDate;
  bool get isError => state == UpkeepState.error;
  bool get isSkipped => state == UpkeepState.skipped;

  Map<String, dynamic> toJson() => {
        'id': upkeeperId,
        'displayName': displayName,
        'state': state.name,
        'summary': summary,
        'details': details,
        if (errorMessage != null) 'error': errorMessage,
      };
}

class UpkeepResult {
  final String upkeeperId;
  final String displayName;
  final bool success;
  final String message;
  final String? errorMessage;

  const UpkeepResult({
    required this.upkeeperId,
    required this.displayName,
    required this.success,
    required this.message,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
        'id': upkeeperId,
        'displayName': displayName,
        'success': success,
        'message': message,
        if (errorMessage != null) 'error': errorMessage,
      };
}
