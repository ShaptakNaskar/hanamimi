import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/platform/ios/ios_library.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String> getApplicationDocumentsPath() async => '$root/Documents';
  @override
  Future<String> getApplicationSupportPath() async => '$root/Support';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('hanamimi-import-');
    PathProviderPlatform.instance = _Paths(root.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IosLibrary.channel, (_) async => null);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'content identity deduplicates names and preserves different recordings',
    () async {
      final a = await IosLibrary.import('same.mp3', Stream.value([1, 2, 3]));
      final retry = await IosLibrary.import(
        'renamed.mp3',
        Stream.value([1, 2, 3]),
      );
      final b = await IosLibrary.import('same.mp3', Stream.value([4, 5, 6]));
      expect(a.path, retry.path);
      expect(b.path, isNot(a.path));
      expect(await a.readAsBytes(), [1, 2, 3]);
      expect(await (await IosLibrary.musicDirectory()).list().length, 2);
    },
  );

  test(
    'rejects traversal, empty, interrupted and native-invalid audio without committing',
    () async {
      for (final name in ['../bad.mp3', 'dir/bad.mp3', 'bad.exe']) {
        await expectLater(
          IosLibrary.import(name, Stream.value([1])),
          throwsFormatException,
        );
      }
      await expectLater(
        IosLibrary.import('empty.mp3', const Stream.empty()),
        throwsFormatException,
      );
      await expectLater(
        IosLibrary.import(
          'broken.mp3',
          Stream.error(const FileSystemException('interrupted')),
        ),
        throwsA(isA<FileSystemException>()),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            IosLibrary.channel,
            (_) async => throw PlatformException(code: 'invalid'),
          );
      await expectLater(
        IosLibrary.import('invalid.mp3', Stream.value([1])),
        throwsA(isA<PlatformException>()),
      );
      expect(await (await IosLibrary.musicDirectory()).list().length, 0);
      expect(
        await Directory('${root.path}/Support/ImportStaging').list().length,
        0,
      );
    },
  );
}
