String formatDuration(int ms) {
  final Duration d = Duration(milliseconds: ms);
  final int m = d.inMinutes;
  final int s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String stageLabel(String? stage) {
  switch (stage) {
    case 'noise_reduction':
      return 'Cleaning noise';
    case 'de_ess':
      return 'Taming sibilance';
    case 'pop_filter':
      return 'Smoothing plosives';
    case 'pitch_correction':
      return 'Tuning pitch';
    case 'eq':
      return 'Shaping tone';
    case 'compression':
      return 'Balancing dynamics';
    case 'render':
      return 'Rendering take';
    default:
      return 'Preparing';
  }
}
