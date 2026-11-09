import 'dart:convert';

/// Only whitelisted, serialized public transport data belongs here.
const publicCacheRetention = Duration(hours: 24);
const publicCacheMaxBytes = 512 * 1024;

class CacheEntry {
  const CacheEntry(this.data, this.receivedAt);
  final Object data;
  final DateTime receivedAt;
  bool validAt(DateTime now) =>
      !receivedAt.isAfter(now) &&
      now.difference(receivedAt) < publicCacheRetention;
}

abstract interface class PublicCache {
  Future<CacheEntry?> read(String dataset);
  Future<void> write(String dataset, CacheEntry entry);
}

class MemoryPublicCache implements PublicCache {
  final entries = <String, CacheEntry>{};
  @override
  Future<CacheEntry?> read(String dataset) async => entries[dataset];
  @override
  Future<void> write(String dataset, CacheEntry entry) async {
    if (utf8.encode(jsonEncode(entry.data)).length > publicCacheMaxBytes) {
      throw const FormatException('Cache limit');
    }
    entries[dataset] = entry;
  }
}

/// API results, never connectivity-adapter/Wi-Fi guesses.
class PublicDataState {
  bool offline = true;
  bool attempted = false;
  bool hasSnapshot = false;
  bool cacheWriteFailed = false;
  DateTime? receivedAt;
}

abstract interface class PublicDataSource {
  PublicDataState get state;
}

Duration retryDelay(int failures) => Duration(
  seconds: failures <= 1
      ? 30
      : failures == 2
      ? 60
      : 120,
);
