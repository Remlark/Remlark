import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// 下载工具：流式下载到文件，报告进度并计算 SHA-256。
class DownloadUtils {
  DownloadUtils._();

  /// 连接超时
  static const connectTimeout = Duration(seconds: 30);

  /// 两次收到数据之间的最长等待时间
  static const idleTimeout = Duration(seconds: 60);

  /// 下载 [url] 到 [output]，返回文件的 SHA-256（小写十六进制）。
  /// [onProgress] 报告已下载与总字节数（总数未知时为 0）。
  /// 下载失败时删除不完整的文件后抛出异常。
  static Future<String> toFile(
    http.Client client,
    String url,
    File output, {
    void Function(int received, int total)? onProgress,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request('GET', Uri.parse(url))..headers.addAll(headers);
    final response = await client.send(request).timeout(connectTimeout);
    if (response.statusCode != 200) {
      // 读完响应体以释放连接
      await response.stream.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final total = response.contentLength ?? 0;
    final hash = Sha256().newHashSink();
    final sink = output.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(idleTimeout)) {
        hash.add(chunk);
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await output.exists()) await output.delete();
      rethrow;
    }
    if (total > 0 && received != total) {
      await output.delete();
      throw HttpException('incomplete download $received/$total', uri: Uri.parse(url));
    }
    hash.close();
    final digest = await hash.hash();
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
