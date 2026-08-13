import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_creator/repositories/compression.dart';

void main() {
  group('nextStaticQuality', () {
    test('returns null when already under target', () {
      final result = nextStaticQuality(
        currentQuality: 90,
        currentSizeBytes: 50 * 1024,
        targetBytes: 100 * 1024,
      );
      expect(result, isNull);
    });

    test('steps quality down when over target', () {
      final result = nextStaticQuality(
        currentQuality: 90,
        currentSizeBytes: 150 * 1024,
        targetBytes: 100 * 1024,
        step: 15,
      );
      expect(result, 75);
    });

    test('throws once quality would drop below floor', () {
      expect(
        () => nextStaticQuality(
          currentQuality: 20,
          currentSizeBytes: 150 * 1024,
          targetBytes: 100 * 1024,
          floor: 10,
          step: 15,
        ),
        throwsA(isA<StickerTooLargeException>()),
      );
    });
  });

  group('nextAnimatedAttempt', () {
    const start = AnimatedEncodeAttempt(colorCount: 256, frameStep: 1);

    test('returns null when already under target', () {
      final result = nextAnimatedAttempt(
        current: start,
        currentSizeBytes: 100 * 1024,
        targetBytes: 500 * 1024,
      );
      expect(result, isNull);
    });

    test('reduces color count first when over target', () {
      final result = nextAnimatedAttempt(
        current: start,
        currentSizeBytes: 600 * 1024,
        targetBytes: 500 * 1024,
        colorStep: 32,
        colorFloor: 32,
      );
      expect(result!.colorCount, 224);
      expect(result.frameStep, 1);
    });

    test('increases frame step once color count is at the floor', () {
      const atFloor = AnimatedEncodeAttempt(colorCount: 32, frameStep: 1);
      final result = nextAnimatedAttempt(
        current: atFloor,
        currentSizeBytes: 600 * 1024,
        targetBytes: 500 * 1024,
        colorFloor: 32,
        maxFrameStep: 4,
      );
      expect(result!.colorCount, 32);
      expect(result.frameStep, 2);
    });

    test('throws once both color count and frame step are exhausted', () {
      const exhausted = AnimatedEncodeAttempt(colorCount: 32, frameStep: 4);
      expect(
        () => nextAnimatedAttempt(
          current: exhausted,
          currentSizeBytes: 600 * 1024,
          targetBytes: 500 * 1024,
          colorFloor: 32,
          maxFrameStep: 4,
        ),
        throwsA(isA<StickerTooLargeException>()),
      );
    });
  });
}
