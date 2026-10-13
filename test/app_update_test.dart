import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/app_update.dart';
import 'package:good_day/app_version.dart';

Map<String, dynamic> metadata(String version, List<int> bytes) => {
  'tag_name': 'v$version',
  'draft': false,
  'prerelease': false,
  'assets': [
    {
      'name': 'Good-Day-$version-windows-x64-setup.exe',
      'state': 'uploaded',
      'browser_download_url':
          'https://github.com/MonkeyStar7/Good_Day/releases/download/v$version/Good-Day-$version-windows-x64-setup.exe',
      'size': bytes.length,
      'digest': 'sha256:${sha256.convert(bytes)}',
    },
  ],
};

class Headers extends Fake implements HttpHeaders {
  Headers([this.location]);
  final String? location;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(this.bytes, {this.statusCode = 200, this.location});
  final List<int> bytes;
  final String? location;
  @override
  final int statusCode;
  @override
  int get contentLength => bytes.length;
  @override
  bool get isRedirect => location != null;
  @override
  HttpHeaders get headers => Headers(location);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.fromIterable([bytes]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request extends Fake implements HttpClientRequest {
  Request(this.response);
  final HttpClientResponse response;
  @override
  bool followRedirects = false;
  @override
  HttpHeaders get headers => Headers();
  @override
  Future<HttpClientResponse> close() async => response;
}

class Client extends Fake implements HttpClient {
  Client(this.respond);
  final HttpClientResponse Function(Uri) respond;
  final requests = <Uri>[];
  @override
  Duration? connectionTimeout;
  @override
  String? userAgent;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return Request(respond(url));
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final bytes = utf8.encode('MZ Good Day test setup fixture');
  test('release parsing accepts newer stable installers and blocks downgrade and invalid sources', () {
    expect(
      AppRelease.fromJson(metadata('1.4.14', bytes), '1.4.13')!.version,
      '1.4.14',
    );
    expect(AppRelease.fromJson(metadata('1.4.11', bytes), '1.4.13'), isNull);
    final draft = metadata('1.4.14', bytes)..['draft'] = true;
    expect(AppRelease.fromJson(draft, '1.4.13'), isNull);
    final preview = metadata('1.4.14', bytes)..['prerelease'] = true;
    expect(AppRelease.fromJson(preview, '1.4.13'), isNull);
    final invalid = metadata('1.4.14', bytes);
    invalid['assets'][0]['browser_download_url'] =
        'https://example.com/setup.exe';
    expect(() => AppRelease.fromJson(invalid, '1.4.13'), throwsFormatException);
    final corrupted = metadata('1.4.14', bytes);
    corrupted['assets'][0]['digest'] = '';
    expect(
      () => AppRelease.fromJson(corrupted, '1.4.13'),
      throwsFormatException,
    );
  });

  test('check and download verify exact size, sha256, progress, and safe redirects', () async {
    final client = Client((uri) {
      if (uri == GithubUpdateClient.latest) {
        return Response(utf8.encode(jsonEncode(metadata('99.0.0', bytes))));
      }
      if (uri.host == 'github.com') {
        return Response(
          [],
          statusCode: 302,
          location: 'https://release-assets.githubusercontent.com/test',
        );
      }
      return Response(bytes);
    });
    final updater = GithubUpdateClient(client: client);
    final release = (await updater.check())!;
    final progress = <double>[];
    final downloaded = await updater.download(release, progress.add);
    try {
      expect(await downloaded.readAsBytes(), bytes);
      expect(progress.last, 1);
      expect(client.requests.last.host, 'release-assets.githubusercontent.com');
    } finally {
      await downloaded.parent.delete(recursive: true);
      updater.dispose();
    }
  });

  test(
    'a corrupted payload or a non-GitHub redirect never becomes an installer',
    () async {
      final release = AppRelease.fromJson(metadata('1.4.14', bytes), '1.4.13')!;
      final bad = GithubUpdateClient(
        client: Client((_) => Response(List.filled(bytes.length, 0))),
      );
      await expectLater(bad.download(release, (_) {}), throwsFormatException);
      bad.dispose();
      final redirect = GithubUpdateClient(
        client: Client(
          (_) => Response(
            [],
            statusCode: 302,
            location: 'http://example.com/setup.exe',
          ),
        ),
      );
      await expectLater(
        redirect.download(release, (_) {}),
        throwsFormatException,
      );
      redirect.dispose();
    },
  );

  test('updating downloads in-app and respects a save guard refusal before installation', () async {
    final client = GithubUpdateClient(
      client: Client(
        (uri) => uri == GithubUpdateClient.latest
            ? Response(utf8.encode(jsonEncode(metadata('99.0.0', bytes))))
            : Response(bytes),
      ),
    );
    var installs = 0;
    final controller = AppUpdateController(
      client: client,
      install: (_) async {
        installs++;
        return false;
      },
    );
    await controller.check();
    expect(controller.stage, UpdateStage.available);
    await controller.update();
    expect(installs, 1);
    expect(controller.stage, UpdateStage.available);
    expect(controller.error, contains('当前编辑'));
    await controller.update();
    expect(installs, 2);
    controller.dispose();
  });

  test('the displayed version matches the package version', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: $appVersion+'),
    );
  });

  test('live GitHub stable release check and verified download', () async {
    final updater = GithubUpdateClient();
    File? file;
    try {
      final latest = await updater.check(current: '1.4.0');
      expect(latest, isNotNull);
      file = await updater.download(latest!, (_) {});
      await GithubUpdateClient.verifyInstaller(file, latest);
      expect(await file.length(), latest.size);
    } finally {
      if (file != null) await file.parent.delete(recursive: true);
      updater.dispose();
    }
  }, skip: !const bool.fromEnvironment('LIVE_UPDATE_CHECK'));
}
