class StickerTooLargeException implements Exception {
  StickerTooLargeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Returns the next WebP quality to try for a lossy static encode, or null
/// once [currentSizeBytes] is already within [targetBytes].
int? nextStaticQuality({
  required int currentQuality,
  required int currentSizeBytes,
  required int targetBytes,
  int floor = 10,
  int step = 15,
}) {
  if (currentSizeBytes <= targetBytes) return null;
  final next = currentQuality - step;
  if (next < floor) {
    throw StickerTooLargeException(
      'Image too complex to fit under ${targetBytes ~/ 1024}KB',
    );
  }
  return next;
}

/// Parameters for one lossless animated-encode attempt: how many colors to
/// quantize down to, and how many source frames to skip between kept frames.
class AnimatedEncodeAttempt {
  const AnimatedEncodeAttempt({required this.colorCount, required this.frameStep});

  final int colorCount;
  final int frameStep;
}

/// Returns the next attempt to try for a lossless animated encode, or null
/// once [currentSizeBytes] is already within [targetBytes]. Reduces color
/// count first (cheaper to visual quality), then falls back to dropping
/// frames once color count hits [colorFloor].
AnimatedEncodeAttempt? nextAnimatedAttempt({
  required AnimatedEncodeAttempt current,
  required int currentSizeBytes,
  required int targetBytes,
  int colorFloor = 32,
  int colorStep = 32,
  int maxFrameStep = 4,
}) {
  if (currentSizeBytes <= targetBytes) return null;
  if (current.colorCount - colorStep >= colorFloor) {
    return AnimatedEncodeAttempt(
      colorCount: current.colorCount - colorStep,
      frameStep: current.frameStep,
    );
  }
  if (current.frameStep < maxFrameStep) {
    return AnimatedEncodeAttempt(
      colorCount: current.colorCount,
      frameStep: current.frameStep + 1,
    );
  }
  throw StickerTooLargeException(
    'GIF too complex to fit under ${targetBytes ~/ 1024}KB',
  );
}
