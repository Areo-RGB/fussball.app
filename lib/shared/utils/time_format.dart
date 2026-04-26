String formatElapsedMillisRoundUp(int milliseconds) {
  if (milliseconds <= 0) {
    return '0.00s';
  }

  final centiseconds = (milliseconds / 10).ceil();
  final seconds = centiseconds / 100;
  return '${seconds.toStringAsFixed(2)}s';
}
