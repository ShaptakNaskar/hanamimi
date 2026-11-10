import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../platform/ios/ios_library.dart';

/// A temporary, capability-authenticated receiver. No library files are served.
class LocalUploadServer {
  LocalUploadServer({
    required this.onImported,
    this.importFile = IosLibrary.import,
  });
  final Future<void> Function() onImported;
  final Future<File> Function(String, Stream<List<int>>) importFile;
  HttpServer? _server;
  Timer? _expiry;
  bool _busy = false;
  String? _token;
  Uri? address;
  final _requests = <HttpRequest>{};

  Future<Uri> start(InternetAddress ip) async {
    await stop();
    final server = await HttpServer.bind(ip, 0, backlog: 4);
    server.idleTimeout = const Duration(seconds: 30);
    _server = server;
    _token = base64Url.encode(
      List.generate(24, (_) => Random.secure().nextInt(256)),
    );
    address = Uri(scheme: 'http', host: ip.address, port: server.port);
    _expiry = Timer(const Duration(minutes: 30), () => unawaited(stop()));
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (_) => unawaited(stop()),
    );
    return address!.replace(fragment: _token);
  }

  Future<void> stop() async {
    _expiry?.cancel();
    _token = null;
    _busy = false;
    address = null;
    final server = _server;
    _server = null;
    for (final request in _requests.toList()) {
      try {
        (await request.response.detachSocket()).destroy();
      } catch (_) {}
    }
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final origin = address?.origin;
    final token = _token;
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    var ownsBusy = false;
    try {
      if (origin == null ||
          token == null ||
          request.headers.value('host') != address!.authority ||
          (request.headers.value('origin') != null &&
              request.headers.value('origin') != origin)) {
        response.statusCode = HttpStatus.forbidden;
      } else if (request.method == 'GET' && request.uri.path == '/') {
        response.headers.contentType = ContentType.html;
        response.write(_page);
      } else if (request.method == 'POST' && request.uri.path == '/upload') {
        if (request.headers.value('authorization') != 'Bearer $token') {
          response.statusCode = HttpStatus.unauthorized;
        } else if (_busy) {
          response.statusCode = HttpStatus.conflict;
        } else if (request.contentLength < 1 ||
            request.contentLength > IosLibrary.maxBytes) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
        } else {
          _busy = ownsBusy = true;
          _requests.add(request);
          final name = request.uri.queryParameters['name'] ?? '';
          await importFile(name, request);
          await onImported();
          response.write('Imported');
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      response.statusCode = HttpStatus.badRequest;
      response.write(
        'Import failed. Check the audio file and available storage, then retry.',
      );
    } finally {
      _requests.remove(request);
      if (ownsBusy && _token == token) _busy = false;
      try {
        await response.close();
      } catch (_) {}
    }
  }

  static const _page = '''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width"><title>Hanamimi music import</title>
<style>body{font:18px system-ui;max-width:36rem;margin:3rem auto;padding:1rem;background:#fff7fa;color:#342832}button,input{font:inherit;margin:1rem 0}progress{width:100%}</style>
<h1>Receive music 🌸</h1><p>Choose music to copy to Hanamimi. Keep the app open. Maximum 2 GiB per file.</p>
<label>Music files <input id="files" type="file" multiple accept=".mp3,.m4a,.aac,.flac,.wav,.aiff,.aif"></label>
<button id="send">Import</button><button id="cancel">Cancel</button><progress id="progress" max="100" value="0"></progress><p id="status" role="status"></p>
<script>
const token=location.hash.slice(1);history.replaceState(null,'',location.pathname);
let active=null,cancelled=false;
const status=document.getElementById('status'),send=document.getElementById('send');
document.getElementById('cancel').onclick=()=>{cancelled=true;active?.abort()};
send.onclick=async()=>{cancelled=false;send.disabled=true;
try { const files=Array.from(document.getElementById('files').files); if(files.length>100)throw Error('Choose at most 100 files.');
for(const file of files){if(cancelled)break;
status.textContent='Receiving '+file.name;
await new Promise((resolve,reject)=>{const x=active=new XMLHttpRequest();x.open('POST','/upload?name='+encodeURIComponent(file.name));x.setRequestHeader('Authorization','Bearer '+token);x.upload.onprogress=e=>{if(e.lengthComputable)document.getElementById('progress').value=100*e.loaded/e.total};x.onload=()=>x.status===200?resolve():reject(Error(x.responseText||'Import failed'));x.onerror=()=>reject(Error('Connection lost. Keep Hanamimi open and retry.'));x.onabort=()=>reject(Error('Cancelled'));x.send(file)});
status.textContent='Imported '+file.name;
}}catch(e){status.textContent=e.message}finally{active=null;send.disabled=false}};
</script></html>''';
}
