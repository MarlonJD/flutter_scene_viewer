import 'diagnostics.dart';
import 'part_address.dart';
import 'texture_source.dart';

enum MaterialMaskChannel {
  red,
  green,
  blue,
  alpha,
}

enum MaterialEffectTarget {
  baseColorRegion,
  roughness,
  metallic,
  clearcoat,
  dirt,
  paintRegion,
}

final class MaterialEffectMask {
  const MaterialEffectMask({
    required this.texture,
    required this.channels,
  }) : _invalidJsonEntries = const <_InvalidEffectMaskJsonEntry>[];

  const MaterialEffectMask._({
    required this.texture,
    required this.channels,
    required List<_InvalidEffectMaskJsonEntry> invalidJsonEntries,
  }) : _invalidJsonEntries = invalidJsonEntries;

  final TextureSource texture;

  final Map<MaterialMaskChannel, MaterialEffectTarget> channels;

  final List<_InvalidEffectMaskJsonEntry> _invalidJsonEntries;

  Map<String, Object?> toJson() => <String, Object?>{
        'texture': texture.toJson(),
        'channels': <String, Object?>{
          for (final entry in channels.entries)
            entry.key.name: entry.value.name,
        },
      };

  static MaterialEffectMask fromJson(Map<String, Object?> json) {
    final rawChannels = json['channels'];
    final channels = <MaterialMaskChannel, MaterialEffectTarget>{};
    final invalidEntries = <_InvalidEffectMaskJsonEntry>[];
    if (rawChannels is Map) {
      for (final entry in rawChannels.entries) {
        final rawChannel = entry.key;
        final rawTarget = entry.value;
        final channel = rawChannel is String
            ? _enumByName(MaterialMaskChannel.values, rawChannel)
            : null;
        if (channel == null) {
          invalidEntries.add(
            _InvalidEffectMaskJsonEntry(
              field: 'effectMask.channel',
              value: rawChannel?.toString() ?? 'null',
            ),
          );
          continue;
        }
        final target = rawTarget is String
            ? _enumByName(MaterialEffectTarget.values, rawTarget)
            : null;
        if (target == null) {
          invalidEntries.add(
            _InvalidEffectMaskJsonEntry(
              field: 'effectMask.target',
              value: rawTarget?.toString() ?? 'null',
              channel: channel.name,
            ),
          );
          continue;
        }
        channels[channel] = target;
      }
    } else {
      invalidEntries.add(
        _InvalidEffectMaskJsonEntry(
          field: 'effectMask.channels',
          value: rawChannels?.toString() ?? 'null',
        ),
      );
    }
    return MaterialEffectMask._(
      texture: TextureSource.fromJson(_objectMap(json['texture'], 'texture')),
      channels: Map<MaterialMaskChannel, MaterialEffectTarget>.unmodifiable(
        channels,
      ),
      invalidJsonEntries:
          List<_InvalidEffectMaskJsonEntry>.unmodifiable(invalidEntries),
    );
  }

  List<ViewerDiagnostic> validate(PartAddress address) {
    final diagnostics = <ViewerDiagnostic>[
      for (final entry in _invalidJsonEntries)
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.invalidMaterialOverride,
          message: 'Material effect mask JSON contains an unsupported value.',
          details: <String, Object?>{
            'part': address.debugPath,
            'field': entry.field,
            'value': entry.value,
            if (entry.channel != null) 'channel': entry.channel,
          },
        ),
    ];
    final targetCounts = <MaterialEffectTarget, int>{};
    for (final target in channels.values) {
      targetCounts[target] = (targetCounts[target] ?? 0) + 1;
    }
    for (final entry in targetCounts.entries) {
      if (entry.value > 1) {
        diagnostics.add(
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.invalidMaterialOverride,
            message:
                'Material effect mask channels must not map to the same target more than once.',
            details: <String, Object?>{
              'part': address.debugPath,
              'field': 'effectMask.channels',
              'target': entry.key.name,
            },
          ),
        );
      }
    }
    return List<ViewerDiagnostic>.unmodifiable(diagnostics);
  }
}

T? _enumByName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return null;
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

final class _InvalidEffectMaskJsonEntry {
  const _InvalidEffectMaskJsonEntry({
    required this.field,
    required this.value,
    this.channel,
  });

  final String field;
  final String value;
  final String? channel;
}
