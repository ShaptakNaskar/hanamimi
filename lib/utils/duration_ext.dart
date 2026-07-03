extension DurationFormat on Duration {
  /// "3:22" / "1:03:22"
  String get mmss {
    final h = inHours;
    final m = inMinutes.remainder(60);
    final s = inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}
