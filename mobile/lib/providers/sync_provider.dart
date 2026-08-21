import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/bgg_expansion_scan_service.dart';
import '../data/sync_service.dart';

/// Provider que expone el estado de sincronizaci\u00f3n a la UI.
///
/// Se suscribe al stream de `SyncService` y reemite cambios para Provider.
class SyncProvider extends ChangeNotifier with WidgetsBindingObserver {
  final SyncService _service = SyncService();
  late StreamSubscription<SyncSnapshot> _sub;
  SyncSnapshot _snapshot = const SyncSnapshot();

  SyncProvider() {
    _sub = _service.stream.listen((s) {
      _snapshot = s;
      notifyListeners();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  SyncSnapshot get snapshot => _snapshot;
  SyncStatus get status => _snapshot.status;
  bool get isSyncing => _snapshot.status == SyncStatus.syncing;

  Future<void> syncNow({bool fullPull = false}) async {
    await _service.syncAll(fullPull: fullPull);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_service.syncAll());
      unawaited(_maybeRunIncrementalExpansionScan());
    }
  }

  Future<void> _maybeRunIncrementalExpansionScan() async {
    try {
      if (!await _service.isOnline()) return;
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('last_expansion_scan_at');
      if (last != null) {
        final lastDate = DateTime.tryParse(last);
        if (lastDate != null &&
            DateTime.now().difference(lastDate).inHours < 24) {
          return;
        }
      }
      await BggExpansionScanService().runScan(modo: 'incremental');
      await prefs.setString(
        'last_expansion_scan_at',
        DateTime.now().toIso8601String(),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub.cancel();
    super.dispose();
  }
}
