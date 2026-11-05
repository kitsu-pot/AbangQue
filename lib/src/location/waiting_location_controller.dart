import 'package:flutter/foundation.dart';

import 'waiting_location.dart';

/// Independent of authentication, vehicle reports and API repositories.
class WaitingLocationController extends ChangeNotifier {
  WaitingLocation? _selected;
  WaitingLocation? get selected => _selected;
  void confirm(WaitingLocation location) {
    _selected = location;
    notifyListeners();
  }

  void clear() {
    if (_selected == null) return;
    _selected = null;
    notifyListeners();
  }
}
