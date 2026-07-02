import 'material_patch.dart';
import 'part_address.dart';

/// Immutable snapshot of persisted runtime material override state.
final class MaterialOverrideSnapshot {
  factory MaterialOverrideSnapshot({
    Map<PartAddress, MaterialPatch> patches =
        const <PartAddress, MaterialPatch>{},
  }) {
    return MaterialOverrideSnapshot._(
      Map<PartAddress, MaterialPatch>.unmodifiable(patches),
    );
  }

  const MaterialOverrideSnapshot._(this._patches);

  static const empty = MaterialOverrideSnapshot._(
    <PartAddress, MaterialPatch>{},
  );

  final Map<PartAddress, MaterialPatch> _patches;

  bool get isEmpty => _patches.isEmpty;

  Iterable<MapEntry<PartAddress, MaterialPatch>> get entries =>
      _patches.entries;

  MaterialPatch? patchFor(PartAddress address) => _patches[address];

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'overrides': <Object?>[
          for (final entry in _patches.entries)
            <String, Object?>{
              'address': entry.key.toJson(),
              'patch': entry.value.toJson(),
            },
        ],
      };

  static MaterialOverrideSnapshot fromJson(Map<String, Object?> json) {
    final rawOverrides = json['overrides'];
    if (rawOverrides is! List) {
      throw ArgumentError.value(json, 'json', 'Invalid override snapshot JSON');
    }
    final patches = <PartAddress, MaterialPatch>{};
    for (final rawEntry in rawOverrides) {
      final entry = _objectMap(rawEntry, 'override');
      final address =
          PartAddress.fromJson(_objectMap(entry['address'], 'address'));
      final patch = MaterialPatch.fromJson(_objectMap(entry['patch'], 'patch'));
      if (!patch.isEmpty) {
        patches[address] = patch;
      }
    }
    return MaterialOverrideSnapshot(patches: patches);
  }
}

/// Mutable accumulator for runtime material override patches.
final class MaterialOverrideStore {
  final Map<PartAddress, MaterialPatch> _patches =
      <PartAddress, MaterialPatch>{};

  MaterialOverrideSnapshot get snapshot =>
      MaterialOverrideSnapshot(patches: _patches);

  void applyPatch(PartAddress address, MaterialPatch patch) {
    if (patch.isEmpty) {
      return;
    }
    _patches[address] = (_patches[address] ?? const MaterialPatch()).merge(
      patch,
    );
  }

  void resetPart(PartAddress address) {
    _patches.remove(address);
  }

  void resetAll() {
    _patches.clear();
  }
}

Map<String, Object?> _objectMap(Object? value, String name) {
  if (value is! Map) {
    throw ArgumentError.value(value, name, 'Expected a map');
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}
