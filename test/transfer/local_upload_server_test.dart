import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/transfer/local_upload_server.dart';

void main() {
  test(
    'receiver fences authentication, origin and revoked links',
    () async {
      var imports = 0;
      final server = LocalUploadServer(
        onImported: () async => imports++,
        importFile: (name, stream) async {
          expect(name, 'song.mp3');
          expect(await stream.fold<int>(0, (n, b) => n + b.length), 3);
          return File('/unused');
        },
      );
      var link = await server.start(InternetAddress.loopbackIPv4);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
      });
      Future<int> upload({String? token, String? origin}) async {
        final req = await client.postUrl(
          link.replace(fragment: '', path: '/upload', query: 'name=song.mp3'),
        );
        if (token != null) req.headers.set('Authorization', 'Bearer $token');
        if (origin != null) req.headers.set('Origin', origin);
        req.contentLength = 3;
        req.add([1, 2, 3]);
        final response = await req.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await upload(), 401);
      expect(await upload(token: 'wrong'), 401);
      expect(
        await upload(token: link.fragment, origin: 'https://evil.example'),
        403,
      );
      expect(await upload(token: link.fragment, origin: link.origin), 200);
      expect(imports, 1);
      final next = await server.start(InternetAddress.loopbackIPv4);
      expect(next.fragment, isNot(link.fragment));
    final revoked = link.fragment;
    link = next;
    expect(await upload(token: revoked), 401);
      await server.stop();
      expect(server.address, isNull);
    },
  );
  test('only one upload can commit at a time', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final server = LocalUploadServer(onImported: () async {}, importFile: (_, bytes) async {
      await bytes.drain<void>();
      entered.complete();
      await release.future;
      return File('/unused');
    });
    final link = await server.start(InternetAddress.loopbackIPv4);
    final client = HttpClient();
    addTearDown(() async { client.close(force: true); await server.stop(); });
    Future<int> upload() async {
      final request = await client.postUrl(link.replace(fragment: '', path: '/upload', query: 'name=song.mp3'));
      request.headers.set('Authorization', 'Bearer ${link.fragment}');
      request.contentLength = 1;
      request.add([1]);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }
    final first = upload();
    await entered.future;
    expect(await upload(), 409);
    release.complete();
    expect(await first, 200);
  });

}
