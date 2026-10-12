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
      if (store.usesReminderWorkflow) {
        for (final item in await store.loadReminders()) {
          if (item.phaseDue(now) == null) continue;
          final claimed = await store.prepareReminder(item.id, now);
          if (claimed == null ||
              _disposed ||
              !canPresent() ||
              !identical(store, repository())) {
            return;
          }
          final phase = claimed.pendingPhase!;
          final occurrence = claimed.phaseTime(phase);
          final event = GoodDayEvent(
            id: claimed.id,
            title: claimed.title,
            notes: claimed.notes,
            startsAt: claimed.dueAt,
            reminderMinutes: phase == 'early'
                ? claimed.dueAt.difference(occurrence).inMinutes
                : 0,
          );
          await present(event, occurrence, (snooze) async {
            await store.resolveReminder(
              claimed.id,
              phase,
              snoozeUntil: snooze == null ? null : clock().add(snooze),
            );
            try {
              await onChanged();
            } catch (error) {
              if (!_disposed) onError(error);
            }
          });
          break;
        }
        _lastError = null;
        return;
      }
      final events = [...await store.loadEvents()];
      final taskReminders = <String, String>{};
      final tasks = await store.loadTaskReminders();
      final latest = <String, DateTime>{};
      final today = DateTime(now.year, now.month, now.day);
      for (final task in tasks) {
        if (task.seriesId == null || task.scheduledDate.isAfter(today)) {
          continue;
        }
        final day = task.occurrenceDate ?? task.scheduledDate;
        if (latest[task.seriesId] == null ||
            day.isAfter(latest[task.seriesId]!)) {
          latest[task.seriesId!] = day;
        }
      }
      if (tasks.any((task) => task.seriesId != null)) {
        for (final series in await store.loadTaskSeries()) {
          final due = series.schedule.latestOccurrenceAtOrBefore(today);
          if (due != null &&
              series.generatedThrough != null &&
              !series.generatedThrough!.isBefore(due) &&
              (latest[series.id] == null || due.isAfter(latest[series.id]!))) {
            latest[series.id] = due;
          }
        }
      }
      for (final task in tasks) {
        final day = task.occurrenceDate ?? task.scheduledDate;
        if (task.seriesId != null &&
            latest[task.seriesId] != null &&
            day.isBefore(latest[task.seriesId]!)) {
          continue;
        }
        final reminder = task.activeReminder;
        if (reminder == null) continue;
        events.add(reminder);
        taskReminders[reminder.id] = task.id;
      }
      events.sort(
        (a, b) => (a.nextReminderAt(now) ?? DateTime(9999)).compareTo(
          b.nextReminderAt(now) ?? DateTime(9999),
        ),
      );
      for (final event in events) {
        if (event.dueOccurrence(now) == null) continue;
        final taskId = taskReminders[event.id];
        final claimed = taskId == null
            ? await store.prepareEventReminder(event.id, now)
            : await store.prepareTaskReminder(taskId, now);
        if (claimed == null ||
            _disposed ||
            !canPresent() ||
            !identical(store, repository())) {
          return;
        }
        final occurrence = claimed.pendingOccurrence!;
        await present(claimed, occurrence, (snooze) async {
          final snoozeUntil = snooze == null ? null : clock().add(snooze);
          if (taskId == null) {
            await store.resolveEventReminder(
              claimed.id,
              occurrence,
              snoozeUntil: snoozeUntil,
            );
          } else {
            await store.resolveTaskReminder(
              taskId,
              occurrence,
              snoozeUntil: snoozeUntil,
            );
          }
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
