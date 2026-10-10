import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// One failed operation must not poison subsequent attempts.
class OperationQueue {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;
  bool get isIdle => _pending == 0;

  Future<T> run<T>(Future<T> Function() operation) {
    _pending++;
    final result = _tail
        .then((_) => operation())
        .whenComplete(() => _pending--);
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> get idle => _tail;
}

class SafeFile {
  static final _queues = <String, OperationQueue>{};
  static int _sequence = 0;

  static Future<void> write(File destination, String contents) =>
      writeBytes(destination, utf8.encode(contents));

  static Future<void> writeBytes(File destination, List<int> contents) {
    final key = destination.absolute.path.toLowerCase();
    final queue = _queues[key] ??= OperationQueue();
    return queue
        .run(() async {
          await destination.parent.create(recursive: true);
          final temporary = File(
            '${destination.path}.goodday-${pid}_${_sequence++}.tmp',
          );
          try {
            await temporary.writeAsBytes(contents, flush: true);
            if (Platform.isWindows) {
              _WindowsFileMove.replace(
                temporary.absolute.path,
                destination.absolute.path,
              );
            } else {
              await temporary.rename(destination.path);
            }
          } finally {
            if (await temporary.exists()) await temporary.delete();
          }
        })
        .whenComplete(() {
          if (queue.isIdle && identical(_queues[key], queue)) {
            _queues.remove(key);
          }
        });
  }
}

/// Never delete the destination before moving the fully flushed sibling file.
class _WindowsFileMove {
  static final _kernel = DynamicLibrary.open('kernel32.dll');
  static final _heap = _kernel
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetProcessHeap',
      )();
  static final _allocate = _kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)
      >('HeapAlloc');
  static final _free = _kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('HeapFree');
  static final _move = _kernel
      .lookupFunction<
        Int32 Function(Pointer<Uint16>, Pointer<Uint16>, Uint32),
        int Function(Pointer<Uint16>, Pointer<Uint16>, int)
      >('MoveFileExW');
  static final _lastError = _kernel
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  static Pointer<Uint16> _wide(String value) {
    final pointer = _allocate(_heap, 8, (value.length + 1) * 2).cast<Uint16>();
    if (pointer == nullptr) throw const FileSystemException('无法分配文件路径内存');
    pointer.asTypedList(value.length + 1).setAll(0, value.codeUnits);
    return pointer;
  }

  static void replace(String source, String destination) {
    final from = _wide(source);
    Pointer<Uint16> to = nullptr;
    try {
      to = _wide(destination);
      // MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH; same volume only.
      if (_move(from, to, 9) == 0) {
        final code = _lastError();
        throw FileSystemException(
          '安全保存失败，原文件已保留',
          destination,
          OSError('Windows 文件替换失败', code),
        );
      }
    } finally {
      _free(_heap, 0, from.cast());
      if (to != nullptr) _free(_heap, 0, to.cast());
    }
  }
}
