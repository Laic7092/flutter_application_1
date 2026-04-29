import 'dart:io';

void main() async {
  const proxyPort = 5001; // 代理端口，避开前端的5001
  const frontendOrigin = 'http://localhost:5001'; // 前端地址，用于CORS

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, proxyPort);
  print('代理服务器运行在 http://localhost:$proxyPort');
  print('将转发 /wenku8/* 到 https://opds.wol.moe/*，并自动跟随重定向');

  await for (final req in server) {
    // 处理 OPTIONS 预检请求（CORS）
    if (req.method == 'OPTIONS') {
      req.response.headers.add('Access-Control-Allow-Origin', frontendOrigin);
      req.response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS');
      req.response.headers.add('Access-Control-Allow-Headers', '*');
      req.response.statusCode = 204;
      await req.response.close();
      continue;
    }

    final path = req.uri.path;
    
    var targetUri = Uri.https('opds.wol.moe', path);

    try {
      // 手动跟随重定向，获取最终内容
      final finalResp = await _followRedirects(targetUri);

      // 写入响应
      req.response.statusCode = finalResp.statusCode;
      req.response.headers.add('Access-Control-Allow-Origin', frontendOrigin);
      // 复制原响应的 Content-Type 等重要头
      finalResp.headers.forEach((name, values) {
        if (name.toLowerCase() == 'content-type' ||
            name.toLowerCase() == 'content-length') {
          req.response.headers.set(name, values.join(','));
        }
      });
      req.response.add(finalResp.body);
      await req.response.close();
    } catch (e) {
      print('代理错误: $e');
      req.response.statusCode = 500;
      req.response.headers.add('Access-Control-Allow-Origin', frontendOrigin);
      await req.response.close();
    }
  }
}

/// 手动跟随重定向，最多跟随5次，返回最终响应
Future<_FinalResponse> _followRedirects(Uri uri, {int maxRedirects = 5}) async {
  var currentUri = uri;
  for (var i = 0; i < maxRedirects; i++) {
    final client = HttpClient();
    final request = await client.getUrl(currentUri);
    request.followRedirects = false; // 手动控制
    final response = await request.close();

    if (response.statusCode >= 300 && response.statusCode < 400) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location != null) {
        currentUri = currentUri.resolve(location);
        client.close();
        continue;
      }
    }

    // 非重定向响应（200 或其他）
    final bodyBytes = await response.fold<List<int>>(
      [],
      (acc, chunk) => acc..addAll(chunk),
    );
    final headersMap = <String, List<String>>{};
    response.headers.forEach((name, values) => headersMap[name] = values);
    client.close();
    return _FinalResponse(
      statusCode: response.statusCode,
      headers: headersMap,
      body: bodyBytes,
    );
  }
  throw Exception('重定向次数超过限制 ($maxRedirects)');
}

class _FinalResponse {
  final int statusCode;
  final Map<String, List<String>> headers;
  final List<int> body;

  _FinalResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });
}
