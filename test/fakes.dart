import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:jeeplink/src/domain/jeepney.dart';
import 'package:jeeplink/src/domain/jeepney_repository.dart';

/// Exercises the real map/marker widgets without HTTP or disk caching.
class MemoryTileProvider extends TileProvider {
  static final _image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _image;
}

class TestRepository implements JeepneyRepository {
  final updates = StreamController<List<Jeepney>>.broadcast();
  List<Jeepney> next = [];
  bool failRefresh = false;
  bool disposed = false;

  @override
  Stream<List<Jeepney>> watchJeepneys() => updates.stream;

  @override
  Future<void> refresh() async {
    if (failRefresh) throw StateError('Backend unavailable');
    updates.add(next);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await updates.close();
  }
}
