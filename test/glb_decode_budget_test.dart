import 'package:flutter_scene_viewer/src/internal/glb_decode_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports a web-unsafe product without forming the product', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(maxTotalDecodedBytes: kGlbMaxSafeInteger),
    );

    expect(
      () => tracker.reserveDecodedProduct(
        count: 9007199254740991,
        bytesPerElement: 2,
        stage: 'meshoptDeclaredOutput',
      ),
      throwsA(
        isA<GlbDecodeBudgetExceeded>()
            .having((error) => error.field, 'field', 'totalDecodedBytes')
            .having((error) => error.stage, 'stage', 'meshoptDeclaredOutput')
            .having((error) => error.limit, 'limit', kGlbMaxSafeInteger)
            .having(
              (error) => error.actual,
              'actual',
              '0 + (9007199254740991 * 2)',
            )
            .having((error) => error.actualExact, 'actualExact', isFalse)
            .having(
              (error) => error.actualExceedsMaxSafeInteger,
              'actualExceedsMaxSafeInteger',
              isTrue,
            )
            .having(
              (error) => error.actualLowerBound,
              'actualLowerBound',
              kGlbMaxSafeInteger,
            )
            .having(
          (error) => error.operands,
          'operands',
          <String, int>{
            'current': 0,
            'left': 9007199254740991,
            'right': 2,
          },
        ),
      ),
    );
    expect(tracker.totalDecodedBytes, 0);
  });

  test('enforces accumulated decoded bytes without partial reservation', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(maxTotalDecodedBytes: 7),
    )..reserveDecodedBytes(4, stage: 'first');

    expect(
      () => tracker.reserveDecodedBytes(4, stage: 'second'),
      throwsA(
        isA<GlbDecodeBudgetExceeded>()
            .having((error) => error.limit, 'limit', 7)
            .having((error) => error.actual, 'actual', 8),
      ),
    );
    expect(tracker.totalDecodedBytes, 4);
  });

  test('accepts exact product and accumulated decoded-byte limits', () {
    final productTracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(maxTotalDecodedBytes: 6),
    );
    expect(
      productTracker.reserveDecodedProduct(
        count: 2,
        bytesPerElement: 3,
        stage: 'product',
      ),
      6,
    );
    expect(productTracker.totalDecodedBytes, 6);

    final aggregateTracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(maxTotalDecodedBytes: 6),
    )
      ..reserveDecodedBytes(2, stage: 'first')
      ..reserveDecodedBytes(4, stage: 'second');
    expect(aggregateTracker.totalDecodedBytes, 6);
  });

  test('accepts exact JSON and native-output limits', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxJsonBytes: 11,
        maxTotalDecodedBytes: 17,
        maxNativeOutputBytes: 17,
      ),
    );

    expect(
      () => tracker.checkJsonBytes(11, stage: 'json'),
      returnsNormally,
    );
    expect(
      () => tracker.reserveNativeOutputBytes(17, stage: 'native'),
      returnsNormally,
    );
    expect(tracker.totalDecodedBytes, 17);
    expect(tracker.nativeOutputBytes, 17);
  });

  test('native-output budget is aggregate and failure is atomic', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 9,
        maxNativeOutputBytes: 8,
      ),
    )..reserveNativeOutputBytes(5, stage: 'first');

    expect(
      () => tracker.reserveNativeOutputBytes(4, stage: 'second'),
      throwsA(
        isA<GlbDecodeBudgetExceeded>()
            .having((error) => error.field, 'field', 'nativeOutputBytes')
            .having((error) => error.stage, 'stage', 'second')
            .having((error) => error.limit, 'limit', 8)
            .having((error) => error.actual, 'actual', 9),
      ),
    );
    expect(tracker.nativeOutputBytes, 5);
    expect(tracker.totalDecodedBytes, 5);
  });

  test('native-output reservation leaves both counters on total failure', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 8,
        maxNativeOutputBytes: 9,
      ),
    )..reserveNativeOutputBytes(5, stage: 'first');

    expect(
      () => tracker.reserveNativeOutputBytes(4, stage: 'second'),
      throwsA(
        isA<GlbDecodeBudgetExceeded>()
            .having((error) => error.field, 'field', 'totalDecodedBytes')
            .having((error) => error.actual, 'actual', 9),
      ),
    );
    expect(tracker.nativeOutputBytes, 5);
    expect(tracker.totalDecodedBytes, 5);
  });

  test('checks final native output size without mutating reservations', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 4,
        maxNativeOutputBytes: 10,
      ),
    )..reserveNativeOutputBytes(4, stage: 'componentPayload');

    expect(
      () => tracker.checkNativeOutputBytes(10, stage: 'finalOutput'),
      returnsNormally,
    );
    expect(tracker.totalDecodedBytes, 4);
    expect(tracker.nativeOutputBytes, 4);
    expect(
      () => tracker.checkNativeOutputBytes(11, stage: 'finalOutput'),
      throwsA(
        isA<GlbDecodeBudgetExceeded>()
            .having((error) => error.field, 'field', 'nativeOutputBytes')
            .having((error) => error.stage, 'stage', 'finalOutput')
            .having((error) => error.limit, 'limit', 10)
            .having((error) => error.actual, 'actual', 11),
      ),
    );
    expect(tracker.totalDecodedBytes, 4);
    expect(tracker.nativeOutputBytes, 4);
  });

  test('rejects negative and unsafe tracker operands before arithmetic', () {
    final unsafeInteger = int.parse('9007199254740992');
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget());

    for (final entry in <({int count, int stride})>[
      (count: -1, stride: 4),
      (count: unsafeInteger, stride: 4),
      (count: 1, stride: -1),
      (count: 1, stride: unsafeInteger),
    ]) {
      expect(
        () => tracker.reserveDecodedProduct(
          count: entry.count,
          bytesPerElement: entry.stride,
          stage: 'meshoptDeclaredOutput',
        ),
        throwsA(
          isA<GlbDecodeBudgetExceeded>()
              .having((error) => error.status, 'status', 'invalidMetadata')
              .having((error) => error.actualExact, 'actualExact', isFalse),
        ),
      );
    }
    expect(tracker.totalDecodedBytes, 0);
  });

  test('validates every numeric budget limit and cancellation interval', () {
    final unsafeInteger = int.parse('9007199254740992');
    final invalidBudgets = <GlbDecodeBudget Function()>[
      () => GlbDecodeBudget(maxJsonBytes: -1),
      () => GlbDecodeBudget(maxTotalDecodedBytes: unsafeInteger),
      () => GlbDecodeBudget(maxAccessors: -1),
      () => GlbDecodeBudget(maxVertices: unsafeInteger),
      () => GlbDecodeBudget(maxIndices: -1),
      () => GlbDecodeBudget(maxTexturePixels: unsafeInteger),
      () => GlbDecodeBudget(maxNativeOutputBytes: -1),
      () => GlbDecodeBudget(cancellationCheckInterval: 0),
    ];

    for (final createBudget in invalidBudgets) {
      expect(createBudget, throwsA(isA<AssertionError>()));
    }
  });

  test('retains future codec limits and timeout cancellation metadata', () {
    const budget = GlbDecodeBudget(
      maxJsonBytes: 11,
      maxTotalDecodedBytes: 12,
      maxAccessors: 13,
      maxVertices: 14,
      maxIndices: 15,
      maxTexturePixels: 16,
      maxNativeOutputBytes: 17,
      decodeTimeout: Duration(seconds: 2),
      cancellationCheckInterval: 18,
    );

    expect(budget.maxJsonBytes, 11);
    expect(budget.maxTotalDecodedBytes, 12);
    expect(budget.maxAccessors, 13);
    expect(budget.maxVertices, 14);
    expect(budget.maxIndices, 15);
    expect(budget.maxTexturePixels, 16);
    expect(budget.maxNativeOutputBytes, 17);
    expect(budget.decodeTimeout, const Duration(seconds: 2));
    expect(budget.cancellationCheckInterval, 18);
  });
}
