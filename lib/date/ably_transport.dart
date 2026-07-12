import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Minimal Ably client over the protocol endpoints: SSE for receiving,
/// REST for publishing. Used by Long-Distance Date Mode instead of
/// ably_flutter, which wraps the native iOS/Android SDKs and doesn't
/// exist on Linux — this one code path runs on every platform Hanamimi
/// does.
///
/// Auth is token-only: the API key never leaves the backend (a Flutter
/// "env var" is just a string inside the APK). The backend's
/// /room/:code/token trades room membership for a short-lived token
/// scoped to that room's channels; when it expires the SSE stream dies
/// with an auth error and [_run] reconnects with a fresh one.
class AblyMessage {
  const AblyMessage({
    required this.channel,
    required this.name,
    required this.data,
    required this.timestamp,
  });

  final String channel;
  final String name;
  final Map<String, dynamic> data;

  /// Ably server time the message was accepted (ms since epoch).
  final DateTime timestamp;
}

class AblyTransport {
  AblyTransport({required this.channels, required this.fetchToken}) {
    _run();
  }

  final List<String> channels;

  /// Mints a fresh scoped token (backend call). Null = can't right now.
  final Future<String?> Function() fetchToken;

  final _messages = StreamController<AblyMessage>.broadcast();
  Stream<AblyMessage> get messages => _messages.stream;

  final _connectedCtrl = StreamController<bool>.broadcast();
  Stream<bool> get connectedStream => _connectedCtrl.stream;

  var _connected = false;
  bool get connected => _connected;

  var _closed = false;
  String? _token;
  http.Client? _sseClient;

  /// Last SSE event serial seen. On reconnect we resume from it so Ably
  /// replays anything published during the gap (its history window is
  /// ~2min) instead of silently dropping it — the difference between a
  /// track change landing in a second and landing on the next slow poll.
  String? _lastEventId;

  void _setConnected(bool value) {
    if (_connected == value || _closed) return;
    _connected = value;
    _connectedCtrl.add(value);
  }

  /// The connection loop: token → SSE stream → parse until it dies →
  /// backoff → again. Exponential backoff resets after a healthy spell.
  Future<void> _run() async {
    var backoff = const Duration(seconds: 1);
    while (!_closed) {
      _token ??= await fetchToken();
      if (_closed) return;
      if (_token == null) {
        await Future<void>.delayed(const Duration(seconds: 5));
        continue;
      }

      final connectedAt = DateTime.now();
      try {
        await _listenOnce(_token!);
      } catch (_) {
        // Fall through to backoff; distinguishing network death from
        // auth expiry isn't worth it — both paths refetch the token.
      }
      _setConnected(false);
      _token = null; // always re-mint; tokens are cheap and short-lived
      if (_closed) return;

      if (DateTime.now().difference(connectedAt) >
          const Duration(minutes: 2)) {
        backoff = const Duration(seconds: 1); // it was healthy — reset
      }
      await Future<void>.delayed(backoff);
      backoff = backoff * 2 > const Duration(seconds: 30)
          ? const Duration(seconds: 30)
          : backoff * 2;
    }
  }

  /// One SSE connection lifetime. Returns when the stream ends; throws
  /// on transport errors. Ably sends a keepalive at least every ~15s,
  /// so a 45s silence means the TCP session is dead even if the socket
  /// hasn't noticed.
  Future<void> _listenOnce(String token) async {
    final client = http.Client();
    _sseClient = client;
    try {
      final uri = Uri.parse('https://realtime.ably.io/sse').replace(
        queryParameters: {
          'channels': channels.join(','),
          'v': '1.2',
          'accessToken': token,
          'heartbeats': 'true',
          if (_lastEventId != null) 'lastEvent': _lastEventId!,
        },
      );
      final req = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream';
      final res = await client.send(req);
      if (res.statusCode != 200) {
        // A stale/invalid resume point can itself be the reason a
        // reconnect keeps failing — drop it so the next attempt starts
        // clean (the room re-syncs from Mongo on connect regardless).
        _lastEventId = null;
        throw http.ClientException('SSE ${res.statusCode}');
      }
      _setConnected(true);

      var eventName = 'message';
      final dataLines = <String>[];
      await for (final line in res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 45))) {
        if (line.isEmpty) {
          if (dataLines.isNotEmpty) {
            _dispatch(eventName, dataLines.join('\n'));
            dataLines.clear();
          }
          eventName = 'message';
        } else if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        } else if (line.startsWith('id:')) {
          // Ably's SSE serial — the resume cursor for reconnects.
          _lastEventId = line.substring(3).trim();
        } else if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        }
        // comment lines (keepalives) need no handling — arriving at all
        // is what feeds the timeout.
      }
    } finally {
      _sseClient = null;
      client.close();
    }
  }

  void _dispatch(String eventName, String payload) {
    if (eventName == 'error') {
      // Token expiry arrives here; ending the read loop triggers the
      // reconnect-with-fresh-token path. The cleanest way out of the
      // await-for is closing the underlying client.
      _sseClient?.close();
      return;
    }
    if (eventName != 'message') return; // heartbeats etc.
    try {
      final envelope = jsonDecode(payload) as Map<String, dynamic>;
      final raw = envelope['data'];
      // Ably delivers an object payload either inline or as a JSON string,
      // and the `encoding` flag it sets over SSE isn't reliable — so
      // decode any string defensively rather than gating on encoding.
      // Getting this wrong drops every message onto the slow Mongo poll.
      var data = const <String, dynamic>{};
      if (raw is Map<String, dynamic>) {
        data = raw;
      } else if (raw is String && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) data = decoded;
        } catch (_) {
          // Not JSON — leave data empty; the frame is simply ignored.
        }
      }
      _messages.add(AblyMessage(
        channel: envelope['channel'] as String? ?? '',
        name: envelope['name'] as String? ?? '',
        data: data,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (envelope['timestamp'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
      ));
    } catch (_) {
      // Malformed frame — skip it, the stream itself is fine.
    }
  }

  /// REST publish. Returns false when it didn't go through (the caller
  /// decides whether that matters — heartbeats don't, controls retry
  /// on the next action anyway).
  Future<bool> publish(
      String channel, String name, Map<String, Object?> data) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = _token ??= await fetchToken();
      if (token == null || _closed) return false;
      try {
        final res = await http
            .post(
              Uri.parse('https://rest.ably.io/channels/'
                  '${Uri.encodeComponent(channel)}/messages'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'name': name, 'data': data}),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 201) return true;
        if (res.statusCode == 401 || res.statusCode == 403) {
          _token = null; // expired — re-mint and retry once
          continue;
        }
        return false;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  void close() {
    _closed = true;
    _sseClient?.close();
    _messages.close();
    _connectedCtrl.close();
  }
}
