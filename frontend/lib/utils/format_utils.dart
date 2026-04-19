// lib/utils/format_utils.dart
String formatTimestamp(String? timestamp) {
  if (timestamp == null || timestamp.isEmpty) return '';
  try {
    final dateTime = DateTime.parse(timestamp).toLocal();
    final year = dateTime.year;
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$minute:$second';
  } catch (e) {
    return timestamp;
  }
}