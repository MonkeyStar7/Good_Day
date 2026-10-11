import 'data/vault_repository.dart';
import 'models/good_day_event.dart';

class EventReminderService {
  EventReminderService({
    required this.repository,
    required this.clock,
    required this.canPresent,
    required this.present,
    required this.onChanged,
    required this.onError,
  });
  final VaultRepository Function() repository;
  final DateTime Function() clock;
  final bool Function() canPresent;
  final Future<void> Function(
    GoodDayEvent event,
    DateTime occurrence,
    Future<void> Function(Duration? snooze) resolve,
  )
  present;
  final Future<void> Function() onChanged;
  final void Function(Object error) onError;
  bool _busy = false;
  bool _disposed = false;
  String? _lastError;

  Future<void> check() async {
    if (_busy || _disposed || !canPresent()) return;
    _busy = true;
    try {
      final store = repository();
      final now = clock();
      final events = await store.loadEvents();
      events.sort(
        (a, b) => (a.nextReminderAt(now) ?? DateTime(9999)).compareTo(
          b.nextReminderAt(now) ?? DateTime(9999),
        ),
      );
      for (final event in events) {
        if (event.dueOccurrence(now) == null) continue;
        final claimed = await store.prepareEventReminder(event.id, now);
        if (claimed == null ||
            _disposed ||
            !canPresent() ||
            !identical(store, repository())) {
          return;
        }
        final occurrence = claimed.pendingOccurrence!;
        await present(claimed, occurrence, (snooze) async {
          await store.resolveEventReminder(
            claimed.id,
            occurrence,
            snoozeUntil: snooze == null ? null : clock().add(snooze),
          );
          try {
            await onChanged();
          } catch (error) {
            // The acknowledgement is already durable. A list refresh failure
            // must not trap the user in a dialog that can no longer be saved.
            if (!_disposed) onError(error);
          }
        });
        break; // One modal at a time; the next timer tick handles the next event.
      }
      _lastError = null;
    } catch (error) {
      if (!_disposed && '$error' != _lastError) {
        _lastError = '$error';
        onError(error);
      }
    } finally {
      _busy = false;
    }
  }

  void dispose() => _disposed = true;
}
