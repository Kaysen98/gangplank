class LCUHttpClientCache {
  final Map<String, dynamic> _cacheMap = {};
  final Map<String, DateTime> _cacheExpirationMap = {};

  bool containsKey(String key) {
    return _cacheMap.containsKey(key);
  }

  dynamic get(String key) {
    if (!containsKey(key)) return null;

    if (_cacheExpirationMap[key]!.isBefore(DateTime.now())) {
      // CACHE EXPIRED
      remove(key);

      return null;
    }

    return _cacheMap[key];
  }

  /// Returns the expiration timestamp.
  DateTime set(String key, dynamic value, Duration cacheExpiration) {
    DateTime expiresIn = DateTime.now().add(cacheExpiration);

    _cacheMap[key] = value;
    _cacheExpirationMap[key] = expiresIn;

    return expiresIn;
  }

  remove(String key) {
    if (containsKey(key)) {
      _cacheMap.remove(key);
      _cacheExpirationMap.remove(key);
    }
  }

  clear() {
    _cacheMap.clear();
    _cacheExpirationMap.clear();
  }
}
