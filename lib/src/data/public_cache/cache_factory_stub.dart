import 'public_cache.dart';

PublicCache createPublicCache(Uri origin, bool simulation) =>
    MemoryPublicCache();
