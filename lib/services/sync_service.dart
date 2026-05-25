import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// Polls the backend `/sync` endpoint at a fixed interval to detect
/// when any resource has changed, and notifies listeners so they can
/// refresh just the parts that need updating.
///
/// This is the closest practical equivalent to "real-time" for a
/// PHP/XAMPP backend without WebSockets — the latency is one polling
/// interval (default 3 seconds), which is invisible for a delivery app.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  final ApiClient _api = ApiClient.instance;

  /// How often to ask the server for changes. 3 seconds is a good
  /// balance — feels instant to humans, and at 20 requests/min per user
  /// the server stays comfortable.
  Duration interval = const Duration(seconds: 3);

  Timer? _timer;
  bool _isPolling = false;
  bool _inFlight = false;

  /// Versions we have seen from the server. Initially empty.
  Map<String, int> _versions = {};

  /// True once we have at least one successful poll. Used to avoid
  /// firing a "changed" event on the very first tick (since on that
  /// tick everything looks new because we have no baseline yet).
  bool _hasBaseline = false;

  /// Resources that changed since the previous tick. Listeners use
  /// this to decide what to re-fetch.
  Set<String> changedResources = {};

  Map<String, int> get versions => Map.unmodifiable(_versions);
  bool get isPolling => _isPolling;

  /// Start the polling loop. Safe to call multiple times — only one
  /// timer is ever active.
  void start() {
    if (_isPolling) return;
    _isPolling = true;
    _tick();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  /// Stop the polling loop (logout, app paused, screen unmounted).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isPolling = false;
  }

  /// Reset baseline. Call after a full refresh or on logout/login so
  /// the next tick is the fresh baseline.
  void reset() {
    _versions = {};
    _hasBaseline = false;
    changedResources = {};
  }

  Future<void> _tick() async {
    if (_inFlight || !_api.isAuthenticated) return;
    _inFlight = true;

    try {
      final res = await _api.get('/api/sync');
      if (res is! Map<String, dynamic>) {
        // Respuesta inesperada, ignorar este tick
        return;
      }
      final versionsRaw = res['versions'];
      if (versionsRaw is! Map) return;

      final newVersions = <String, int>{};
      versionsRaw.forEach((k, v) {
        if (k is String && v is num) {
          newVersions[k] = v.toInt();
        }
      });

      if (newVersions.isEmpty) return;

      if (!_hasBaseline) {
        // First successful poll — just record the baseline, don't fire.
        _versions = newVersions;
        _hasBaseline = true;
        return;
      }

      // Detect what changed.
      final changed = <String>{};
      for (final entry in newVersions.entries) {
        if (_versions[entry.key] != entry.value) {
          changed.add(entry.key);
        }
      }

      if (changed.isNotEmpty) {
        _versions = newVersions;
        changedResources = changed;
        notifyListeners();
      }
    } catch (_) {
      // Silently ignore network blips — next tick will retry.
    } finally {
      _inFlight = false;
    }
  }
}
