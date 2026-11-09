import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'public_cache.dart';

PublicCache createPublicCache(Uri origin, bool simulation) => FilePublicCache(
  scope: '${origin.origin}|simulation=$simulation',
  directory: () async => Directory(
    '${(await getApplicationCacheDirectory()).path}/abangque-public-v1',
  ),
);

/// Fixed filenames and bounded files; no account, waiting location or secrets.
class FilePublicCache implements PublicCache {
  FilePublicCache({
    required this.scope,
    required this.directory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final String scope;
  final Future<Directory> Function() directory;
  final DateTime Function() _clock;
  final _written = <String, DateTime>{};
  Future<File> _file(String dataset) async {
    if (!['routes', 'jeepneys'].contains(dataset)) {
      throw ArgumentError('Unknown public dataset');
    }
    return File('${(await directory()).path}/$dataset.json');
  }

  @override
  Future<CacheEntry?> read(String dataset) async {
    try {
      final file = await _file(dataset);
      if (!await file.exists()) return null;
      if (await file.length() > publicCacheMaxBytes) {
        await file.delete();
        return null;
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map || value['version'] != 1 || value['scope'] != scope) {
        return null;
      }
      final entry = CacheEntry(
        value['data'] as Object,
        DateTime.parse(value['receivedAt'] as String).toUtc(),
      );
      if (!entry.validAt(_clock().toUtc())) {
        await file.delete();
        return null;
      }
      return entry;
    } catch (_) {
      return null;
    } // Missing/corrupt/evicted cache never blocks API use.
  }

  @override
  Future<void> write(String dataset, CacheEntry entry) async {
    final now = _clock().toUtc();
    final last = _written[dataset];
    if (last != null &&
        now.difference(last) >= Duration.zero &&
        now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    final bytes = utf8.encode(
      jsonEncode({
        'version': 1,
        'scope': scope,
        'receivedAt': entry.receivedAt.toUtc().toIso8601String(),
        'data': entry.data,
      }),
    );
    if (bytes.length > publicCacheMaxBytes) {
      throw const FormatException('Public cache limit');
    }
    final file = await _file(dataset);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    _written[dataset] = now;
  }
}
