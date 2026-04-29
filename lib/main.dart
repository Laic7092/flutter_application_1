import 'dart:io';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_web/webview_flutter_web.dart';

import 'modules/opds/opds_module.dart';
import 'services/book_bridge_service.dart';
import 'utils/proxy_utils.dart';

void main() {
  if (kIsWeb) {
    WebViewPlatform.instance = WebWebViewPlatform();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter WebView Bridge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainPage(),
      builder: (context, child) {
        if (kIsWeb && child != null) {
          return PointerInterceptor(child: child);
        }
        return child ?? const SizedBox();
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _showOpds = false;

  void _toggleOpds() {
    setState(() {
      _showOpds = !_showOpds;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _showOpds
        ? OpdsModule(onBookSelect: _handleBookSelect)
        : WebViewPage(onOpenLibrary: _toggleOpds);
  }

  void _handleBookSelect(String bookUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookDownloadPage(bookUrl: bookUrl),
      ),
    );
  }
}

class WebViewPage extends StatefulWidget {
  final VoidCallback? onOpenLibrary;

  const WebViewPage({super.key, this.onOpenLibrary});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController controller;
  late final BookBridgeService _bookBridgeService;

  @override
  void initState() {
    super.initState();
    controller = WebViewController();
    
    if (!kIsWeb) {
      controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    }
    
    _bookBridgeService = BookBridgeService(
      controller: controller,
      onBookDownload: _handleBookDownload,
    );
    _bookBridgeService.setupJavaScriptChannel(controller);
    
    controller.loadRequest(Uri.parse('https://laic7092.github.io/book/'));
  }

  void _handleBookDownload(String url, String filename, void Function(bool, Uint8List?) onComplete) async {
    final bytes = await ProxyUtils.downloadWithProxy(url);
    
    if (bytes != null) {
      onComplete(true, bytes);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载完成: $filename')),
        );
      }
    } else {
      onComplete(false, null);
    }
  }

  void _showDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return PointerInterceptor(
          child: AlertDialog(
            title: const Text('提示'),
            content: const Text('这是一个原生弹框！'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                PointerInterceptor(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.blue,
                    ),
                    onPressed: _showDialog,
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(height: 10),
                PointerInterceptor(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.green,
                    ),
                    onPressed: widget.onOpenLibrary,
                    child: const Icon(Icons.library_books, color: Colors.white, size: 28),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BookDownloadPage extends StatefulWidget {
  final String bookUrl;

  const BookDownloadPage({super.key, required this.bookUrl});

  @override
  State<BookDownloadPage> createState() => _BookDownloadPageState();
}

class _BookDownloadPageState extends State<BookDownloadPage> {
  bool _isDownloading = false;
  double _progress = 0;
  String _errorMessage = '';

  Future<void> _downloadBook() async {
    setState(() {
      _isDownloading = true;
      _progress = 0;
      _errorMessage = '';
    });

    try {
      final bytes = await ProxyUtils.downloadWithProxy(widget.bookUrl);
      final filename = widget.bookUrl.split('/').last;
      
      if (bytes != null) {
        if (kIsWeb) {
          _downloadFileWeb(bytes, filename);
        } else {
          _downloadFileNative(bytes, filename);
        }
        
        setState(() {
          _progress = 100;
          _isDownloading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('下载成功！')),
          );
        }
      } else {
        throw Exception('下载失败');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isDownloading = false;
      });
    }
  }

  void _downloadFileWeb(Uint8List bytes, String filename) {
    if (!kIsWeb) return;
    final htmlBlob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(htmlBlob);
    html.AnchorElement(href: url)
      ..download = filename
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _downloadFileNative(Uint8List bytes, String filename) {
    final downloadsDir = Directory.systemTemp;
    final file = File('${downloadsDir.path}/$filename');
    file.writeAsBytesSync(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载书籍'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('书籍地址: ${widget.bookUrl}'),
              const SizedBox(height: 20),
              
              if (_isDownloading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress / 100),
                Text('下载进度: ${_progress.toInt()}%'),
              ] else if (_errorMessage.isNotEmpty) ...[
                Text('错误: $_errorMessage', style: const TextStyle(color: Colors.red)),
              ] else ...[
                ElevatedButton(
                  onPressed: _downloadBook,
                  child: const Text('下载书籍'),
                ),
              ],
              
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}