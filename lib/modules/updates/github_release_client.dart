import 'package:http/http.dart' as http;

import 'update_release.dart';
import '../../utils/git_credentials/git_credentials.dart';

/// GitHub 更新专用客户端：匿名优先，凭据仅发送到固定仓库的 API。
class GithubReleaseClient extends http.BaseClient {
  GithubReleaseClient({
    http.Client? inner,
    Future<String?> Function()? credentials,
  }) : _inner = inner ?? http.Client(),
       _credentials = credentials ?? GitCredentials().githubToken;
  final http.Client _inner;
  final Future<String?> Function() _credentials;
  static const repository = 'Remlark/Remlark';
  static const apiPath = '/repos/$repository/releases/';
  static const apiRoot = 'https://api.github.com$apiPath';

  /// 校验下载主机，禁止 HTTPS 降级和把 Token 带往重定向目标。
  static bool allowed(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      ((uri.host == 'api.github.com' && uri.path.startsWith(apiPath)) ||
          uri.host == 'release-assets.githubusercontent.com' ||
          uri.host == 'objects.githubusercontent.com' ||
          (uri.host == 'github.com' &&
              uri.path.startsWith('/$repository/releases/')));

  /// 手工跟随有限次数重定向；每次重新构造头部，不继承 Authorization。
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var uri = request.url;
    var authenticated = false;
    String? token;
    for (var hop = 0; hop < 7; hop++) {
      if (!allowed(uri)) throw const UpdateFailure('updates.error.download');
      final api = uri.host == 'api.github.com';
      final next = http.Request('GET', uri)..followRedirects = false;
      next.headers.addAll({
        'Accept': request.headers['Accept'] ?? 'application/vnd.github+json',
        'User-Agent': 'Remlark',
        'X-GitHub-Api-Version': '2022-11-28',
      });
      if (api && authenticated && token != null) {
        next.headers['Authorization'] = 'Bearer $token';
      }
      final response = await _inner
          .send(next)
          .timeout(const Duration(seconds: 25));
      if (api &&
          !authenticated &&
          [401, 403, 404].contains(response.statusCode)) {
        token = await _credentials();
        if (token == null) return response;
        await response.stream.drain<void>().timeout(
          const Duration(seconds: 25),
        );
        authenticated = true;
        continue;
      }
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>().timeout(
          const Duration(seconds: 25),
        );
        if (location == null) {
          throw const UpdateFailure('updates.error.download');
        }
        uri = uri.resolve(location);
        authenticated = false;
        continue;
      }
      return response;
    }
    throw const UpdateFailure('updates.error.download');
  }

  /// 退出时中断当前连接。
  @override
  void close() => _inner.close();
}
