import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _opHandshake = 0;
const _opFrame = 1;
const _opClose = 2;
const _opPing = 3;
const _opPong = 4;
const _maxFrameBytes = 1024 * 1024;

class DiscordRpcException implements Exception {
  const DiscordRpcException(this.message);

  final String message;

  @override
  String toString() => 'DiscordRpcException: $message';
}

class DiscordActivity {
  const DiscordActivity({
    required this.name,
    required this.type,
    required this.details,
    required this.state,
    this.start,
    this.end,
    this.largeImage,
    this.largeText,
    this.smallImage,
    this.smallText,
  });

  final String name;
  final int type;
  final String details;
  final String state;
  final DateTime? start;
  final DateTime? end;
  final String? largeImage;
  final String? largeText;
  final String? smallImage;
  final String? smallText;

  Map<String, Object?> toJson() {
    final timestamps = <String, Object?>{
      if (start != null) 'start': start!.millisecondsSinceEpoch,
      if (end != null) 'end': end!.millisecondsSinceEpoch,
    };
    final assets = <String, Object?>{
      if (largeImage != null) 'large_image': largeImage,
      if (largeText != null) 'large_text': largeText,
      if (smallImage != null) 'small_image': smallImage,
      if (smallText != null) 'small_text': smallText,
    };
    return {
      'name': name,
      'type': type,
      'details': details,
      'state': state,
      if (timestamps.isNotEmpty) 'timestamps': timestamps,
      if (assets.isNotEmpty) 'assets': assets,
    };
  }
}

abstract interface class DiscordRpcClient {
  Stream<void> get disconnected;

  Future<void> connect();
  Future<void> setActivity(DiscordActivity activity);
  Future<void> disconnect();
}

/// Minimal implementation of Discord's documented local RPC protocol.
/// It deliberately owns only SET_ACTIVITY: no account token, OAuth, friends,
/// messages, or network API is involved.
class DiscordLocalRpcClient implements DiscordRpcClient {
  DiscordLocalRpcClient({required this.applicationId});

  final String applicationId;
  final _disconnected = StreamController<void>.broadcast();
  final _pending = <String, Completer<void>>{};

  _DiscordIpcTransport? _transport;
  StreamSubscription<_DiscordIpcFrame>? _frameSub;
  Completer<void>? _ready;
  var _nonce = 0;
  bool _connected = false;
  bool _closing = false;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  @override
  Future<void> connect() async {
    if (_connected) return;
    if (_transport != null) {
      throw const DiscordRpcException('Connection is already in progress');
    }

    final transport =
        Platform.isWindows
            ? _WindowsDiscordIpcTransport()
            : _UnixDiscordIpcTransport();
    _transport = transport;
    _ready = Completer<void>();
    _frameSub = transport.frames.listen(
      _onFrame,
      onError: (Object error, StackTrace stack) => _connectionLost(error),
      onDone:
          () => _connectionLost(
            const DiscordRpcException('Discord closed the IPC connection'),
          ),
    );

    try {
      await transport.connect();
      await transport.send(_opHandshake, {'v': 1, 'client_id': applicationId});
      await _ready!.future.timeout(const Duration(seconds: 5));
      _connected = true;
    } catch (error) {
      await disconnect();
      if (error is DiscordRpcException) rethrow;
      throw DiscordRpcException('$error');
    }
  }

  @override
  Future<void> setActivity(DiscordActivity activity) async {
    if (!_connected || _transport == null) {
      throw const DiscordRpcException('Discord is not connected');
    }
    final nonce = '${pid}_${DateTime.now().microsecondsSinceEpoch}_${_nonce++}';
    final response = Completer<void>();
    _pending[nonce] = response;
    try {
      await _transport!.send(_opFrame, {
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': pid, 'activity': activity.toJson()},
        'nonce': nonce,
      });
      await response.future.timeout(const Duration(seconds: 5));
    } finally {
      _pending.remove(nonce);
    }
  }

  void _onFrame(_DiscordIpcFrame frame) {
    if (frame.opcode == _opPing) {
      final transport = _transport;
      if (transport != null) {
        unawaited(transport.send(_opPong, frame.payload));
      }
      return;
    }
    if (frame.opcode == _opClose) {
      final message = frame.payload['message'] ?? 'Discord rejected the RPC';
      _connectionLost(DiscordRpcException('$message'));
      return;
    }
    if (frame.opcode != _opFrame) return;

    if (frame.payload['evt'] == 'READY') {
      final ready = _ready;
      if (ready != null && !ready.isCompleted) ready.complete();
      return;
    }

    final nonce = frame.payload['nonce'];
    if (nonce is! String) return;
    final pending = _pending[nonce];
    if (pending == null || pending.isCompleted) return;
    if (frame.payload['evt'] == 'ERROR') {
      final data = frame.payload['data'];
      final message = data is Map ? data['message'] : null;
      pending.completeError(
        DiscordRpcException('${message ?? 'Discord rejected the activity'}'),
      );
    } else {
      pending.complete();
    }
  }

  void _connectionLost(Object error) {
    if (_closing) return;
    _connected = false;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    if (!_disconnected.isClosed) _disconnected.add(null);
  }

  @override
  Future<void> disconnect() async {
    if (_closing) return;
    _closing = true;
    _connected = false;
    final frameSub = _frameSub;
    _frameSub = null;
    await frameSub?.cancel();
    final transport = _transport;
    _transport = null;
    try {
      await transport?.close();
    } catch (_) {}
    _pending.clear();
    _ready = null;
    _closing = false;
  }
}

class _DiscordIpcFrame {
  const _DiscordIpcFrame(this.opcode, this.payload);

  final int opcode;
  final Map<String, Object?> payload;
}

abstract class _DiscordIpcTransport {
  Stream<_DiscordIpcFrame> get frames;

  Future<void> connect();
  Future<void> send(int opcode, Map<String, Object?> payload);
  Future<void> close();
}

class _FrameDecoder {
  _FrameDecoder(this.output);

  final StreamController<_DiscordIpcFrame> output;
  final _buffer = <int>[];

  void add(List<int> bytes) {
    _buffer.addAll(bytes);
    while (_buffer.length >= 8) {
      final header = ByteData.sublistView(Uint8List.fromList(_buffer), 0, 8);
      final opcode = header.getUint32(0, Endian.little);
      final length = header.getUint32(4, Endian.little);
      if (length > _maxFrameBytes) {
        output.addError(
          const DiscordRpcException('Discord sent an oversized RPC frame'),
        );
        _buffer.clear();
        return;
      }
      if (_buffer.length < 8 + length) return;
      final payloadBytes = _buffer.sublist(8, 8 + length);
      _buffer.removeRange(0, 8 + length);
      try {
        final decoded = jsonDecode(utf8.decode(payloadBytes));
        if (decoded is Map) {
          output.add(
            _DiscordIpcFrame(
              opcode,
              decoded.map((key, value) => MapEntry('$key', value)),
            ),
          );
        }
      } catch (error, stack) {
        output.addError(
          DiscordRpcException('Invalid Discord RPC frame: $error'),
          stack,
        );
      }
    }
  }
}

Uint8List _encodeFrame(int opcode, Map<String, Object?> payload) {
  final body = utf8.encode(jsonEncode(payload));
  final frame = Uint8List(8 + body.length);
  final header =
      ByteData.sublistView(frame, 0, 8)
        ..setUint32(0, opcode, Endian.little)
        ..setUint32(4, body.length, Endian.little);
  // Keep [header] alive until both fields have been written.
  if (header.lengthInBytes != 8) {
    throw const DiscordRpcException('Could not create Discord RPC frame');
  }
  frame.setRange(8, frame.length, body);
  return frame;
}

class _UnixDiscordIpcTransport implements _DiscordIpcTransport {
  final _frames = StreamController<_DiscordIpcFrame>.broadcast();
  late final _decoder = _FrameDecoder(_frames);
  Socket? _socket;
  bool _closed = false;

  @override
  Stream<_DiscordIpcFrame> get frames => _frames.stream;

  @override
  Future<void> connect() async {
    for (final path in _candidateSocketPaths()) {
      try {
        final address = InternetAddress(path, type: InternetAddressType.unix);
        _socket = await Socket.connect(
          address,
          0,
          timeout: const Duration(milliseconds: 500),
        );
        _socket!.listen(
          _decoder.add,
          onError: (Object error, StackTrace stack) {
            if (!_frames.isClosed) _frames.addError(error, stack);
          },
          onDone: _finish,
          cancelOnError: false,
        );
        return;
      } catch (_) {}
    }
    throw const DiscordRpcException('Discord desktop is not running');
  }

  Iterable<String> _candidateSocketPaths() sync* {
    final roots = <String>{
      if (Platform.environment['XDG_RUNTIME_DIR'] case final value?) value,
      if (Platform.environment['TMPDIR'] case final value?) value,
      if (Platform.environment['TMP'] case final value?) value,
      if (Platform.environment['TEMP'] case final value?) value,
      '/tmp',
    };
    for (final root in roots) {
      for (var id = 0; id < 10; id++) {
        yield '$root/discord-ipc-$id';
        yield '$root/app/com.discordapp.Discord/discord-ipc-$id';
        yield '$root/app/dev.vencord.Vesktop/discord-ipc-$id';
      }
    }
  }

  @override
  Future<void> send(int opcode, Map<String, Object?> payload) async {
    final socket = _socket;
    if (socket == null || _closed) {
      throw const DiscordRpcException('Discord IPC socket is closed');
    }
    socket.add(_encodeFrame(opcode, payload));
    await socket.flush();
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    if (!_frames.isClosed) unawaited(_frames.close());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket?.destroy();
    _socket = null;
    if (!_frames.isClosed) await _frames.close();
  }
}

typedef _CreateFileNative =
    IntPtr Function(
      Pointer<Utf16>,
      Uint32,
      Uint32,
      Pointer<Void>,
      Uint32,
      Uint32,
      IntPtr,
    );
typedef _CreateFileDart =
    int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int);
typedef _PipeIoNative =
    Int32 Function(
      IntPtr,
      Pointer<Uint8>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Void>,
    );
typedef _PipeIoDart =
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>);
typedef _PeekNamedPipeNative =
    Int32 Function(
      IntPtr,
      Pointer<Void>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _PeekNamedPipeDart =
    int Function(
      int,
      Pointer<Void>,
      int,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);

class _WindowsDiscordIpcTransport implements _DiscordIpcTransport {
  _WindowsDiscordIpcTransport()
    : _kernel32 = DynamicLibrary.open('kernel32.dll') {
    _createFile = _kernel32.lookupFunction<_CreateFileNative, _CreateFileDart>(
      'CreateFileW',
    );
    _readFile = _kernel32.lookupFunction<_PipeIoNative, _PipeIoDart>(
      'ReadFile',
    );
    _writeFile = _kernel32.lookupFunction<_PipeIoNative, _PipeIoDart>(
      'WriteFile',
    );
    _peekNamedPipe = _kernel32
        .lookupFunction<_PeekNamedPipeNative, _PeekNamedPipeDart>(
          'PeekNamedPipe',
        );
    _closeHandle = _kernel32
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  }

  static const _genericRead = 0x80000000;
  static const _genericWrite = 0x40000000;
  static const _openExisting = 3;
  static const _invalidHandle = -1;

  final DynamicLibrary _kernel32;
  late final _CreateFileDart _createFile;
  late final _PipeIoDart _readFile;
  late final _PipeIoDart _writeFile;
  late final _PeekNamedPipeDart _peekNamedPipe;
  late final _CloseHandleDart _closeHandle;
  final _frames = StreamController<_DiscordIpcFrame>.broadcast();
  late final _decoder = _FrameDecoder(_frames);

  Timer? _readTimer;
  int _handle = _invalidHandle;
  bool _closed = false;

  @override
  Stream<_DiscordIpcFrame> get frames => _frames.stream;

  @override
  Future<void> connect() async {
    for (var id = 0; id < 10; id++) {
      final path = r'\\?\pipe\discord-ipc-' '$id';
      final nativePath = path.toNativeUtf16();
      try {
        final handle = _createFile(
          nativePath,
          _genericRead | _genericWrite,
          0,
          nullptr,
          _openExisting,
          0,
          0,
        );
        if (handle != _invalidHandle) {
          _handle = handle;
          _readTimer = Timer.periodic(
            const Duration(milliseconds: 100),
            (_) => _readAvailable(),
          );
          return;
        }
      } finally {
        calloc.free(nativePath);
      }
    }
    throw const DiscordRpcException('Discord desktop is not running');
  }

  void _readAvailable() {
    if (_closed || _handle == _invalidHandle) return;
    final available = calloc<Uint32>();
    try {
      final ok = _peekNamedPipe(
        _handle,
        nullptr,
        0,
        nullptr,
        available,
        nullptr,
      );
      if (ok == 0) {
        _finishWithError(
          const DiscordRpcException('Discord closed the named pipe'),
        );
        return;
      }
      final byteCount = available.value;
      if (byteCount == 0) return;
      final buffer = calloc<Uint8>(byteCount);
      final read = calloc<Uint32>();
      try {
        final readOk = _readFile(_handle, buffer, byteCount, read, nullptr);
        if (readOk == 0) {
          _finishWithError(
            const DiscordRpcException('Could not read Discord named pipe'),
          );
          return;
        }
        _decoder.add(buffer.asTypedList(read.value));
      } finally {
        calloc.free(read);
        calloc.free(buffer);
      }
    } finally {
      calloc.free(available);
    }
  }

  @override
  Future<void> send(int opcode, Map<String, Object?> payload) async {
    if (_closed || _handle == _invalidHandle) {
      throw const DiscordRpcException('Discord named pipe is closed');
    }
    final frame = _encodeFrame(opcode, payload);
    final buffer = calloc<Uint8>(frame.length);
    final written = calloc<Uint32>();
    try {
      buffer.asTypedList(frame.length).setAll(0, frame);
      final ok = _writeFile(_handle, buffer, frame.length, written, nullptr);
      if (ok == 0 || written.value != frame.length) {
        throw const DiscordRpcException('Could not write Discord named pipe');
      }
    } finally {
      calloc.free(written);
      calloc.free(buffer);
    }
  }

  void _finishWithError(Object error) {
    if (_closed) return;
    if (!_frames.isClosed) _frames.addError(error);
    unawaited(close());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _readTimer?.cancel();
    _readTimer = null;
    if (_handle != _invalidHandle) {
      _closeHandle(_handle);
      _handle = _invalidHandle;
    }
    if (!_frames.isClosed) await _frames.close();
  }
}
