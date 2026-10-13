import 'package:flutter/widgets.dart';

class EditCoordinator {
  final _participants = <Object, Future<bool> Function()>{};
  void register(Object owner, Future<bool> Function() save) =>
      _participants[owner] = save;
  void unregister(Object owner) => _participants.remove(owner);

  Future<bool> flush() async {
    for (final save in List.of(_participants.values)) {
      if (!await save()) return false;
    }
    return true;
  }
}

class EditScope extends InheritedWidget {
  const EditScope({super.key, required this.coordinator, required super.child});
  final EditCoordinator coordinator;
  static EditCoordinator? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EditScope>()?.coordinator;
  @override
  bool updateShouldNotify(EditScope oldWidget) =>
      coordinator != oldWidget.coordinator;
}

mixin ReliableEditor<T extends StatefulWidget>
    on State<T>, AutomaticKeepAliveClientMixin<T> {
  @override
  bool get wantKeepAlive => true;
  EditCoordinator? _coordinator;
  Future<bool>? _pendingSave;
  int _revision = 0;
  int _savedRevision = 0;
  bool get hasPendingEdits =>
      _revision != _savedRevision || _pendingSave != null;
  void markPendingEdit() => _revision++;
  Future<bool> persistEdits();
  Future<void> onEditsFlushed() async {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = EditScope.of(context);
    if (next == _coordinator) return;
    _coordinator?.unregister(this);
    _coordinator = next;
    next?.register(this, flushPendingEdits);
  }

  Future<bool> flushPendingEdits() {
    if (!mounted) return Future.value(true);
    if (_pendingSave != null) return _pendingSave!;
    if (!hasPendingEdits) return Future.value(true);
    final result = _flush();
    _pendingSave = result;
    return result.whenComplete(() => _pendingSave = null);
  }

  Future<bool> _flush() async {
    while (mounted && _revision != _savedRevision) {
      final revision = _revision;
      if (!await persistEdits()) return false;
      _savedRevision = revision;
    }
    if (mounted) await onEditsFlushed();
    return true;
  }

  @override
  void dispose() {
    _coordinator?.unregister(this);
    super.dispose();
  }
}
