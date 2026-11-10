import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/transfer/local_upload_server.dart';

Future<Cookie> _openPage(HttpClient client, Uri link) async {
  expect(link.fragment, isEmpty);
  expect(link.query, isEmpty);
  final response = await (await client.getUrl(link)).close();
  expect(response.statusCode, 200);
  final cookie = response.cookies.single;
  expect(cookie.httpOnly, isTrue);
  expect(cookie.sameSite, SameSite.strict);
  await response.drain<void>();
  return cookie;
}

void main() {
  test(
    'plain address opens the uploader; session and origin fence uploads',
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
      final session = await _openPage(client, link);
      Future<int> upload({Cookie? cookie, String? origin}) async {
        final request = await client.postUrl(
          link.replace(path: '/upload', query: 'name=song.mp3'),
        );
        if (cookie != null) request.cookies.add(cookie);
        if (origin != null) request.headers.set('Origin', origin);
        request.contentLength = 3;
        request.add([1, 2, 3]);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await upload(), 401);
      expect(await upload(cookie: Cookie(session.name, 'wrong')), 401);
      expect(
        await upload(cookie: session, origin: 'https://evil.example'),
        403,
      );
      expect(await upload(cookie: session, origin: link.origin), 200);
      expect(imports, 1);
      link = await server.start(InternetAddress.loopbackIPv4);
      expect(await upload(cookie: session), 401);
      final newSession = await _openPage(client, link);
      expect(await upload(cookie: newSession), 200);
      await server.stop();
      expect(server.address, isNull);
    },
  );

  test('only one upload can commit at a time', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final server = LocalUploadServer(
      onImported: () async {},
      importFile: (_, bytes) async {
        await bytes.drain<void>();
        entered.complete();
        await release.future;
        return File('/unused');
      },
    );
    final link = await server.start(InternetAddress.loopbackIPv4);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.stop();
    });
    final session = await _openPage(client, link);
    Future<int> upload() async {
      final request = await client.postUrl(
        link.replace(path: '/upload', query: 'name=song.mp3'),
      );
      request.cookies.add(session);
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
