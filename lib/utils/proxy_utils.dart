import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ProxyUtils {
  static String convertToProxyUrl(String url) {
    if (url.startsWith('https://opds.wol.moe/')) {
      return '/wenku8/${url.substring('https://opds.wol.moe/'.length)}';
    }
    return url;
  }

  static Future<Uint8List?> downloadWithProxy(String url) async {
    if (kIsWeb) {
      final proxyUrl = convertToProxyUrl(url);
      return _downloadWeb(proxyUrl);
    } else {
      return _downloadNative(url);
    }
  }

  static Future<Uint8List?> _downloadWeb(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _downloadNative(String url) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final streamedResponse = await client.send(request);

      Uint8List? bytes;

      if (streamedResponse.statusCode >= 300 && streamedResponse.statusCode < 400) {
        // 手动处理重定向（非 Web 端可能用到；Web 端浏览器会自动追随，此分支通常不会进入）
        final redirectUrl = streamedResponse.headers['location'];
        if (redirectUrl != null) {
          final proxyRedirectUrl = convertToProxyUrl(redirectUrl);
          final redirectRequest = http.Request('GET', Uri.parse(proxyRedirectUrl));
          final finalResponse = await client.send(redirectRequest);
          if (finalResponse.statusCode == 200) {
            bytes = await finalResponse.stream.toBytes();
          }
        }
      } else if (streamedResponse.statusCode == 200) {
        bytes = await streamedResponse.stream.toBytes();
      }

      client.close();
      return bytes;
    } catch (_) {
      return null;
    }
  }
}