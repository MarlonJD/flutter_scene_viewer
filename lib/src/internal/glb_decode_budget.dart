/// Largest integer that remains exact on Dart's JavaScript targets.
const int kGlbMaxSafeInteger = 9007199254740991;

/// Immutable resource limits shared by GLB decoder and rewrite boundaries.
///
/// This type records limits needed by Meshopt, Draco, and BasisU hardening,
/// even when a particular decoder does not enforce every field yet. The
/// timeout drives cooperative checkpoints in the pure-Dart Meshopt decoder and
/// bounds Dart's wait for a native MethodChannel result. It does not stop
/// native work or guarantee native resource release. For Meshopt,
/// [cancellationCheckInterval] is the approximate decoded-byte interval between
/// deadline reads; cancellation remains metadata until decoder and bridge
/// contracts accept an external cooperative signal.
final class GlbDecodeBudget {
  const GlbDecodeBudget({
    this.maxJsonBytes = 8 * 1024 * 1024,
    this.maxTotalDecodedBytes = 256 * 1024 * 1024,
    this.maxAccessors = 1 * 1024 * 1024,
    this.maxVertices = 20 * 1024 * 1024,
    this.maxIndices = 60 * 1024 * 1024,
    this.maxTexturePixels = 64 * 1024 * 1024,
    this.maxNativeOutputBytes = 256 * 1024 * 1024,
    this.decodeTimeout = const Duration(seconds: 30),
    this.cancellationCheckInterval = 4096,
  })  : assert(maxJsonBytes >= 0 && maxJsonBytes <= kGlbMaxSafeInteger),
        assert(maxTotalDecodedBytes >= 0 &&
            maxTotalDecodedBytes <= kGlbMaxSafeInteger),
        assert(maxAccessors >= 0 && maxAccessors <= kGlbMaxSafeInteger),
        assert(maxVertices >= 0 && maxVertices <= kGlbMaxSafeInteger),
        assert(maxIndices >= 0 && maxIndices <= kGlbMaxSafeInteger),
        assert(maxTexturePixels >= 0 && maxTexturePixels <= kGlbMaxSafeInteger),
        assert(maxNativeOutputBytes >= 0 &&
            maxNativeOutputBytes <= kGlbMaxSafeInteger),
        assert(cancellationCheckInterval > 0 &&
            cancellationCheckInterval <= kGlbMaxSafeInteger);

  final int maxJsonBytes;
  final int maxTotalDecodedBytes;
  final int maxAccessors;
  final int maxVertices;
  final int maxIndices;
  final int maxTexturePixels;
  final int maxNativeOutputBytes;
  final Duration decodeTimeout;
  final int cancellationCheckInterval;
}

/// A checked budget failure that callers can translate into typed diagnostics.
final class GlbDecodeBudgetExceeded implements Exception {
  const GlbDecodeBudgetExceeded({
    required this.field,
    required this.stage,
    required this.limit,
    required this.actual,
    this.status = 'budgetExceeded',
    this.actualExact = true,
    this.actualExceedsMaxSafeInteger = false,
    this.actualLowerBound,
    this.operands = const <String, Object>{},
  });

  final String field;
  final String stage;
  final int limit;
  final Object actual;
  final String status;
  final bool actualExact;
  final bool actualExceedsMaxSafeInteger;
  final int? actualLowerBound;
  final Map<String, Object> operands;

  @override
  String toString() => status == 'invalidMetadata'
      ? 'Invalid GLB decode metadata for $field at $stage: $actual.'
      : 'GLB decode budget exceeded for $field at $stage: $actual > $limit.';
}

/// Per-load accounting for [GlbDecodeBudget].
///
/// Reservations check the limit before updating counters, so a rejected
/// operation leaves the tracker unchanged. Native output bytes are cumulative
/// across every decoder reservation made through the same tracker.
final class GlbDecodeBudgetTracker {
  GlbDecodeBudgetTracker(this.budget) {
    _validateRuntimeBudget(budget);
  }

  final GlbDecodeBudget budget;

  int _totalDecodedBytes = 0;
  int _nativeOutputBytes = 0;
  int _accessors = 0;
  int _vertices = 0;
  int _indices = 0;
  int _texturePixels = 0;

  int get totalDecodedBytes => _totalDecodedBytes;
  int get nativeOutputBytes => _nativeOutputBytes;
  int get accessors => _accessors;
  int get vertices => _vertices;
  int get indices => _indices;
  int get texturePixels => _texturePixels;

  void checkJsonBytes(int byteLength, {required String stage}) {
    _checkValue(
      field: 'jsonBytes',
      stage: stage,
      limit: budget.maxJsonBytes,
      actual: byteLength,
    );
  }

  int reserveDecodedProduct({
    required int count,
    required int bytesPerElement,
    required String stage,
  }) {
    final byteLength = _checkedProduct(
      count,
      bytesPerElement,
      field: 'totalDecodedBytes',
      stage: stage,
      limit: budget.maxTotalDecodedBytes,
      current: _totalDecodedBytes,
      leftName: 'count',
      rightName: 'bytesPerElement',
    );
    _totalDecodedBytes += byteLength;
    return byteLength;
  }

  void reserveDecodedBytes(int byteLength, {required String stage}) {
    _totalDecodedBytes = _checkedAccumulation(
      current: _totalDecodedBytes,
      increment: byteLength,
      field: 'totalDecodedBytes',
      stage: stage,
      limit: budget.maxTotalDecodedBytes,
    );
  }

  void reserveNativeOutputBytes(int byteLength, {required String stage}) {
    final nextNativeOutputBytes = _checkedAccumulation(
      current: _nativeOutputBytes,
      increment: byteLength,
      field: 'nativeOutputBytes',
      stage: stage,
      limit: budget.maxNativeOutputBytes,
    );
    final nextTotalDecodedBytes = _checkedAccumulation(
      current: _totalDecodedBytes,
      increment: byteLength,
      field: 'totalDecodedBytes',
      stage: stage,
      limit: budget.maxTotalDecodedBytes,
    );
    _nativeOutputBytes = nextNativeOutputBytes;
    _totalDecodedBytes = nextTotalDecodedBytes;
  }

  void checkNativeOutputBytes(int byteLength, {required String stage}) {
    _checkValue(
      field: 'nativeOutputBytes',
      stage: stage,
      limit: budget.maxNativeOutputBytes,
      actual: byteLength,
    );
  }

  void reserveAccessors(int count, {required String stage}) {
    _accessors = _checkedAccumulation(
      current: _accessors,
      increment: count,
      field: 'accessors',
      stage: stage,
      limit: budget.maxAccessors,
    );
  }

  void reserveVertices(int count, {required String stage}) {
    _vertices = _checkedAccumulation(
      current: _vertices,
      increment: count,
      field: 'vertices',
      stage: stage,
      limit: budget.maxVertices,
    );
  }

  void reserveIndices(int count, {required String stage}) {
    _indices = _checkedAccumulation(
      current: _indices,
      increment: count,
      field: 'indices',
      stage: stage,
      limit: budget.maxIndices,
    );
  }

  int reserveTexturePixels({
    required int width,
    required int height,
    required String stage,
  }) {
    final pixels = _checkedProduct(
      width,
      height,
      field: 'texturePixels',
      stage: stage,
      limit: budget.maxTexturePixels,
      current: _texturePixels,
      leftName: 'width',
      rightName: 'height',
    );
    _texturePixels += pixels;
    return pixels;
  }
}

int _checkedAccumulation({
  required int current,
  required int increment,
  required String field,
  required String stage,
  required int limit,
}) {
  _validateTrackerOperand(
    current,
    name: 'current',
    field: field,
    stage: stage,
    limit: limit,
  );
  _validateTrackerOperand(
    increment,
    name: 'increment',
    field: field,
    stage: stage,
    limit: limit,
  );
  _validateTrackerLimit(limit, field: field, stage: stage);
  if (current > limit) {
    throw GlbDecodeBudgetExceeded(
      field: field,
      stage: stage,
      limit: limit,
      actual: current,
      operands: <String, int>{'current': current, 'increment': increment},
    );
  }
  final remaining = limit - current;
  if (increment > remaining) {
    throw _additionExceeded(
      current: current,
      increment: increment,
      field: field,
      stage: stage,
      limit: limit,
    );
  }
  return current + increment;
}

int _checkedProduct(
  int left,
  int right, {
  required String field,
  required String stage,
  required int limit,
  required int current,
  required String leftName,
  required String rightName,
}) {
  _validateTrackerOperand(
    current,
    name: 'current',
    field: field,
    stage: stage,
    limit: limit,
  );
  _validateTrackerOperand(
    left,
    name: leftName,
    field: field,
    stage: stage,
    limit: limit,
  );
  _validateTrackerOperand(
    right,
    name: rightName,
    field: field,
    stage: stage,
    limit: limit,
  );
  _validateTrackerLimit(limit, field: field, stage: stage);
  final operands = <String, int>{
    'current': current,
    'left': left,
    'right': right,
  };
  if (current > limit) {
    throw GlbDecodeBudgetExceeded(
      field: field,
      stage: stage,
      limit: limit,
      actual: current,
      operands: operands,
    );
  }
  if (left != 0 && right > kGlbMaxSafeInteger ~/ left) {
    throw GlbDecodeBudgetExceeded(
      field: field,
      stage: stage,
      limit: limit,
      actual: '$current + ($left * $right)',
      actualExact: false,
      actualExceedsMaxSafeInteger: true,
      actualLowerBound: kGlbMaxSafeInteger,
      operands: operands,
    );
  }
  final product = left * right;
  final remaining = limit - current;
  if (product > remaining) {
    if (product > kGlbMaxSafeInteger - current) {
      throw GlbDecodeBudgetExceeded(
        field: field,
        stage: stage,
        limit: limit,
        actual: '$current + $product',
        actualExact: false,
        actualExceedsMaxSafeInteger: true,
        actualLowerBound: kGlbMaxSafeInteger,
        operands: operands,
      );
    }
    throw GlbDecodeBudgetExceeded(
      field: field,
      stage: stage,
      limit: limit,
      actual: current + product,
      operands: operands,
    );
  }
  return product;
}

void _checkValue({
  required String field,
  required String stage,
  required int limit,
  required int actual,
}) {
  _validateTrackerOperand(
    actual,
    name: field,
    field: field,
    stage: stage,
    limit: limit,
  );
  _validateTrackerLimit(limit, field: field, stage: stage);
  if (actual > limit) {
    throw GlbDecodeBudgetExceeded(
      field: field,
      stage: stage,
      limit: limit,
      actual: actual,
    );
  }
}

GlbDecodeBudgetExceeded _additionExceeded({
  required int current,
  required int increment,
  required String field,
  required String stage,
  required int limit,
}) {
  final operands = <String, int>{
    'current': current,
    'increment': increment,
  };
  if (increment > kGlbMaxSafeInteger - current) {
    return GlbDecodeBudgetExceeded(
      field: field,
      stage: stage,
      limit: limit,
      actual: '$current + $increment',
      actualExact: false,
      actualExceedsMaxSafeInteger: true,
      actualLowerBound: kGlbMaxSafeInteger,
      operands: operands,
    );
  }
  return GlbDecodeBudgetExceeded(
    field: field,
    stage: stage,
    limit: limit,
    actual: current + increment,
    operands: operands,
  );
}

void _validateTrackerOperand(
  int value, {
  required String name,
  required String field,
  required String stage,
  required int limit,
}) {
  if (value >= 0 && value <= kGlbMaxSafeInteger) {
    return;
  }
  throw GlbDecodeBudgetExceeded(
    field: field,
    stage: stage,
    limit: limit,
    actual: '$name=$value',
    status: 'invalidMetadata',
    actualExact: false,
    actualExceedsMaxSafeInteger: value > kGlbMaxSafeInteger,
    actualLowerBound: value > kGlbMaxSafeInteger ? kGlbMaxSafeInteger : null,
    operands: <String, Object>{
      name: value > kGlbMaxSafeInteger ? value.toString() : value,
    },
  );
}

void _validateTrackerLimit(
  int limit, {
  required String field,
  required String stage,
}) {
  if (limit >= 0 && limit <= kGlbMaxSafeInteger) {
    return;
  }
  throw StateError(
    'Invalid GLB decode budget limit for $field at $stage: $limit.',
  );
}

void _validateRuntimeBudget(GlbDecodeBudget budget) {
  final limits = <String, int>{
    'maxJsonBytes': budget.maxJsonBytes,
    'maxTotalDecodedBytes': budget.maxTotalDecodedBytes,
    'maxAccessors': budget.maxAccessors,
    'maxVertices': budget.maxVertices,
    'maxIndices': budget.maxIndices,
    'maxTexturePixels': budget.maxTexturePixels,
    'maxNativeOutputBytes': budget.maxNativeOutputBytes,
  };
  for (final entry in limits.entries) {
    if (entry.value < 0 || entry.value > kGlbMaxSafeInteger) {
      throw ArgumentError.value(
        entry.value,
        entry.key,
        'must be between 0 and $kGlbMaxSafeInteger',
      );
    }
  }
  if (budget.decodeTimeout.isNegative) {
    throw ArgumentError.value(
      budget.decodeTimeout,
      'decodeTimeout',
      'must not be negative',
    );
  }
  if (budget.cancellationCheckInterval <= 0 ||
      budget.cancellationCheckInterval > kGlbMaxSafeInteger) {
    throw ArgumentError.value(
      budget.cancellationCheckInterval,
      'cancellationCheckInterval',
      'must be between 1 and $kGlbMaxSafeInteger',
    );
  }
}
