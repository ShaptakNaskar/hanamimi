import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/ios/ios_library.dart';
import '../../providers/library_provider.dart';
import '../../providers/power_provider.dart';
import '../../theme/theme_tokens.dart';
import '../../transfer/local_upload_server.dart';

Future<void> showMusicImportSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => const MusicImportSheet(),
);

class MusicImportSheet extends ConsumerStatefulWidget {
  const MusicImportSheet({super.key});
  @override
  ConsumerState<MusicImportSheet> createState() => _MusicImportSheetState();
}

class _MusicImportSheetState extends ConsumerState<MusicImportSheet>
    with WidgetsBindingObserver {
  late final LocalUploadServer _server;
  late final LibraryNotifier _library;
  late final bool _caffeine;
  int _generation = 0;
  Timer? _network;
  Uri? _url;
  String _status =
      'Import from Files, or receive music from a browser on your Wi-Fi network.';
  bool _busy = false;
  Timer? _expiry;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _library = ref.read(libraryProvider.notifier);
    _caffeine = ref.read(caffeineProvider);
    _server = LocalUploadServer(
      onImported: () async {
        await _library.rescan();
        if (mounted) setState(() => _status = 'Music imported.');
      },
    );
  }

  Future<void> _stop() async {
    _generation++;
    _expiry?.cancel();
    _network?.cancel();
    _network = null;
    await _server.stop();
    if (!_disposed) {
      await PowerChannel.setKeepScreenOn(_caffeine);
      if (mounted) setState(() => _url = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stop());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_library.rescan());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _status = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() => _run(() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Audio', uniformTypeIdentifiers: ['public.audio']),
      ],
    );
    for (final file in files) {
      await IosLibrary.import(file.name, file.openRead());
    }
    await _library.rescan();
    if (mounted && files.isNotEmpty) {
      setState(() => _status = 'Imported ${files.length} file(s).');
    }
  });

  Future<void> _start() => _run(() async {
    final generation = ++_generation;
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    // shortcut: en0 IPv4 only; add interface variants after device reachability tests.
    final ip =
        interfaces
            .where((i) => i.name == 'en0')
            .expand((i) => i.addresses)
            .firstOrNull;
    if (ip == null) {
      throw const SocketException('Connect to Wi-Fi, or import from Files.');
    }
    final url = await _server.start(ip);
    if (!mounted || generation != _generation ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      await _server.stop();
      return;
    }
    setState(() {
      _url = url;
      _status =
          'Open this link on a trusted Wi-Fi network. Keep this screen open. Stops after 30 minutes or when backgrounded. HTTP transfer is unencrypted.';
    });
    await PowerChannel.setKeepScreenOn(true);
    if (!mounted || generation != _generation) {
      await PowerChannel.setKeepScreenOn(_caffeine);
      return;
    }
    _network = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final current = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        if (!current
            .where((i) => i.name == 'en0')
            .expand((i) => i.addresses)
            .any((a) => a.address == ip.address)) {
          await _stop();
        }
      } catch (_) {
        await _stop();
      }
    });
    _expiry = Timer(const Duration(minutes: 30), () => unawaited(_stop()));
  });

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    _network?.cancel();
    unawaited(_server.stop());
    unawaited(PowerChannel.setKeepScreenOn(_caffeine));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(Space.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import music', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.s4),
          Text(_status),
          const SizedBox(height: Space.s4),
          FilledButton.icon(
            onPressed: _busy || _url != null ? null : _pick,
            icon: const Icon(Icons.audio_file),
            label: const Text('Import from Files'),
          ),
          TextButton.icon(
            onPressed:
                _busy
                    ? null
                    : _url == null
                    ? _start
                    : _stop,
            icon: const Icon(Icons.wifi),
            label: Text(_url == null ? 'Receive over Wi-Fi' : 'Stop receiving'),
          ),
          if (_url != null) ...[
            SelectableText(_url.toString()),
            TextButton(
              onPressed:
                  () => Clipboard.setData(ClipboardData(text: _url.toString())),
              child: const Text('Copy link'),
            ),
          ],
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: Space.s2),
          const Text(
            'You can also place audio in Hanamimi → Music in Files or Finder, then rescan. Keep a separate backup of your music.',
          ),
        ],
      ),
    ),
  );
}
