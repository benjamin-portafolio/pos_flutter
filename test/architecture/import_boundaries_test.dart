import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _importPattern = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''');

void main() {
  test('imports respect layer boundaries', () {
    final violations = <String>[];
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final sourcePath = _normalize(file.path);
      final sourceLayer = _layerForPath(sourcePath);
      if (sourceLayer == null) continue;

      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final match = _importPattern.firstMatch(lines[index]);
        if (match == null) continue;

        final targetPath = _resolveLibImport(sourcePath, match.group(1)!);
        if (targetPath == null) continue;

        final targetLayer = _layerForPath(targetPath);
        if (targetLayer == null) continue;

        if (!_isAllowedImport(sourceLayer, targetLayer)) {
          violations.add(
            '$sourcePath:${index + 1} imports $targetPath '
            '($sourceLayer -> $targetLayer)',
          );
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

String? _resolveLibImport(String sourcePath, String importUri) {
  if (importUri.startsWith('dart:')) return null;

  const packagePrefix = 'package:pos_flutter/';
  if (importUri.startsWith(packagePrefix)) {
    return _normalize(p.join('lib', importUri.substring(packagePrefix.length)));
  }

  if (importUri.startsWith('package:')) return null;

  return _normalize(p.join(p.dirname(sourcePath), importUri));
}

String? _layerForPath(String path) {
  if (path.startsWith('lib/core/di/')) return 'composition';
  if (path.startsWith('lib/core/')) return 'core';
  if (path.startsWith('lib/domain/')) return 'domain';
  if (path.startsWith('lib/application/')) return 'application';
  if (path.startsWith('lib/data/')) return 'data';
  if (path.startsWith('lib/presentation/')) return 'presentation';

  return null;
}

bool _isAllowedImport(String sourceLayer, String targetLayer) {
  const allowedTargets = {
    'composition': {'composition', 'core', 'data', 'application', 'domain'},
    'core': {'core'},
    'domain': {'domain'},
    'application': {'application', 'domain', 'data'},
    'data': {'data', 'application', 'domain'},
    'presentation': {
      'presentation',
      'application',
      'domain',
      'core',
      'composition',
    },
  };

  return allowedTargets[sourceLayer]?.contains(targetLayer) ?? false;
}

String _normalize(String path) => p.normalize(path).replaceAll(r'\', '/');
