import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'app_version.dart';

class AppRelease {
  const AppRelease(this.version, this.url, this.size, this.digest);
  final String version, digest;
  final Uri url;
  final int size;

  static List<int> versionParts(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(value);
    if (match == null) throw const FormatException('版本格式无效');
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  bool newerThan(String current) {
    final a = versionParts(version), b = versionParts(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static AppRelease? fromJson(Map<String, dynamic> json, String current) {
    if (json['draft'] != false || json['prerelease'] != false) return null;
    final version = (json['tag_name'] as String).replaceFirst(
      RegExp(r'^v'),
      '',
    );
    versionParts(version);
    final candidate = AppRelease(version, Uri(), 0, '');
    if (!candidate.newerThan(current)) return null;
    final name = 'Good-Day-$version-windows-x64-setup.exe';
    final matches = (json['assets'] as List).where(
      (asset) => asset['name'] == name && asset['state'] == 'uploaded',
    );
    if (matches.length != 1) return null;
    final asset = matches.single;
    final uri = Uri.parse(asset['browser_download_url'] as String);
    final digest = asset['digest'] as String? ?? '';
    final size = asset['size'] as int;
    if (uri.toString() !=
            'https://github.com/MonkeyStar7/Good_Day/releases/download/v$version/$name' ||
        size < 1 ||
        size > 100 * 1024 * 1024 ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('安装包信息不完整，暂不能更新');
    }
    final release = AppRelease(
      version,
      uri,
      size,
      digest.substring(7).toLowerCase(),
    );
    return release.newerThan(current) ? release : null;
  }
}

class GithubUpdateClient {
  GithubUpdateClient({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
    _client.userAgent = 'Good-Day/$appVersion';
  }
  final HttpClient _client;
  static final latest = Uri.parse(
    'https://api.github.com/repos/MonkeyStar7/Good_Day/releases/latest',
  );

  Future<HttpClientResponse> _get(Uri uri) async {
    for (var redirects = 0; redirects < 6; redirects++) {
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          !{
            'api.github.com',
            'github.com',
            'release-assets.githubusercontent.com',
            'objects.githubusercontent.com',
          }.contains(uri.host)) {
        throw const FormatException('更新下载地址无效');
      }
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) throw const FormatException('下载地址无效');
        uri = uri.resolve(location);
        continue;
      }
      return response;
    }
    throw const FormatException('下载跳转过多');
  }

  Future<AppRelease?> check({String current = appVersion}) async {
    final response = await _get(latest);
    if (response.statusCode == 404) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw const HttpException('无法连接 GitHub，请稍后重试');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) throw const FormatException('更新信息过大');
    }
    return AppRelease.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      current,
    );
  }

  Future<File> download(
    AppRelease release,
    void Function(double) progress,
  ) async {
    final directory = await Directory.systemTemp.createTemp('goodday-update-');
    final partial = File(
      '${directory.path}${Platform.pathSeparator}setup.part',
    );
    IOSink? sink;
    try {
      final response = await _get(release.url);
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw const HttpException('安装包下载失败，请重试');
      }
      if (response.contentLength >= 0 &&
          response.contentLength != release.size) {
        throw const FormatException('安装包大小不符');
      }
      sink = partial.openWrite();
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > release.size) throw const FormatException('安装包大小不符');
        sink.add(chunk);
        progress(received / release.size);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await verifyInstaller(partial, release);
      return await partial.rename(
        '${directory.path}${Platform.pathSeparator}Good-Day-${release.version}-windows-x64-setup.exe',
      );
    } catch (_) {
      await sink?.close();
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
  }

  static Future<void> verifyInstaller(File file, AppRelease release) async {
    if (await file.length() != release.size ||
        (await sha256.bind(file.openRead()).first).toString() !=
            release.digest) {
      throw const FormatException('安装包校验失败，请重新下载');
    }
  }

  void dispose() => _client.close(force: true);
}

enum UpdateStage {
  idle,
  checking,
  available,
  downloading,
  installing,
  current,
  failed,
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({GithubUpdateClient? client, required this.install})
    : client = client ?? GithubUpdateClient();
  final GithubUpdateClient client;
  final Future<bool> Function(File) install;
  UpdateStage stage = UpdateStage.idle;
  AppRelease? release;
  String? error;
  double progress = 0;
  bool _disposed = false;
  File? _downloaded;
  bool get busy => {
    UpdateStage.checking,
    UpdateStage.downloading,
    UpdateStage.installing,
  }.contains(stage);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> check() async {
    if (busy || _disposed) return;
    stage = UpdateStage.checking;
    error = null;
    _changed();
    try {
      release = await client.check();
      if (_disposed) return;
      stage = release == null ? UpdateStage.current : UpdateStage.available;
    } catch (_) {
      if (_disposed) return;
      error = '暂时无法检查更新，请检查网络后重试';
      stage = UpdateStage.failed;
    }
    _changed();
  }

  Future<void> update() async {
    if (busy || release == null || _disposed) return;
    try {
      stage = UpdateStage.downloading;
      error = null;
      _changed();
      _downloaded ??= await client.download(release!, (value) {
        progress = value;
        _changed();
      });
      if (_disposed) return;
      await GithubUpdateClient.verifyInstaller(_downloaded!, release!);
      stage = UpdateStage.installing;
      _changed();
      if (!await install(_downloaded!)) {
        error = '请先完成当前编辑或处理提醒，再点击更新';
        stage = UpdateStage.available;
      }
    } catch (_) {
      _downloaded = null;
      error = '更新未完成，原程序和数据仍保留，可重新尝试';
      stage = UpdateStage.available;
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    client.dispose();
    super.dispose();
  }
}
