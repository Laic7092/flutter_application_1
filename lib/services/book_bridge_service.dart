import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BookBridgeService {
  final WebViewController? _controller;
  final BookBridgeCallback? _onBookDownload;

  BookBridgeService({
    WebViewController? controller,
    BookBridgeCallback? onBookDownload,
  }) : _controller = controller,
       _onBookDownload = onBookDownload;

  void setupJavaScriptChannel(WebViewController controller) {
    if (!kIsWeb) {
      controller.addJavaScriptChannel('BookBridge', onMessageReceived: (message) {
        _handleMessage(message.message);
      });
    } else {
      _injectBridgeScript(controller);
    }
  }

  void _injectBridgeScript(WebViewController controller) {
    Future.delayed(const Duration(seconds: 1), () {
      controller.runJavaScript('''
        window.bookBridge = {
          downloadBook: function(url, filename) {
            return new Promise(function(resolve, reject) {
              const callbackId = 'book_cb_' + Date.now();
              window.bookBridgeCallbacks = window.bookBridgeCallbacks || {};
              window.bookBridgeCallbacks[callbackId] = resolve;
              
              const message = JSON.stringify({
                action: 'downloadBook',
                callbackId: callbackId,
                url: url,
                filename: filename || 'book.epub'
              });
              
              if (window.BookBridge) {
                window.BookBridge.postMessage(message);
              } else {
                console.warn('BookBridge not available');
                resolve({success: false, error: 'Bridge not available'});
              }
            });
          },
          getBookList: function() {
            return new Promise(function(resolve, reject) {
              const callbackId = 'book_cb_' + Date.now();
              window.bookBridgeCallbacks = window.bookBridgeCallbacks || {};
              window.bookBridgeCallbacks[callbackId] = resolve;
              
              const message = JSON.stringify({
                action: 'getBookList',
                callbackId: callbackId
              });
              
              if (window.BookBridge) {
                window.BookBridge.postMessage(message);
              } else {
                resolve({success: false, error: 'Bridge not available'});
              }
            });
          },
          openBook: function(filePath) {
            return new Promise(function(resolve, reject) {
              const callbackId = 'book_cb_' + Date.now();
              window.bookBridgeCallbacks = window.bookBridgeCallbacks || {};
              window.bookBridgeCallbacks[callbackId] = resolve;
              
              const message = JSON.stringify({
                action: 'openBook',
                callbackId: callbackId,
                filePath: filePath
              });
              
              if (window.BookBridge) {
                window.BookBridge.postMessage(message);
              } else {
                resolve({success: false, error: 'Bridge not available'});
              }
            });
          }
        };
        console.log('Book Bridge initialized');
      ''');
    });
  }

  void _handleMessage(String message) {
    try {
      final data = jsonDecode(message);
      final String action = data['action'];
      final String callbackId = data['callbackId'];

      switch (action) {
        case 'downloadBook':
          final String url = data['url'];
          final String filename = data['filename'] ?? 'book.epub';
          _handleDownloadBook(callbackId, url, filename);
          break;
        case 'getBookList':
          _handleGetBookList(callbackId);
          break;
        case 'openBook':
          final String filePath = data['filePath'];
          _handleOpenBook(callbackId, filePath);
          break;
        default:
          _sendError(callbackId, 'Action $action not implemented');
      }
    } catch (e) {
      debugPrint('Error parsing BookBridge message: $e');
    }
  }

  void _handleDownloadBook(String callbackId, String url, String filename) {
    if (_onBookDownload != null) {
      _onBookDownload!(url, filename, (success, data) {
        if (success && data != null) {
          _sendResponse(callbackId, {
            'success': true,
            'filename': filename,
            'size': data.length,
            'base64': base64Encode(data),
          });
        } else {
          _sendError(callbackId, 'Download failed');
        }
      });
    } else {
      _sendError(callbackId, 'Download handler not registered');
    }
  }

  void _handleGetBookList(String callbackId) {
    _sendResponse(callbackId, {
      'success': true,
      'books': [],
    });
  }

  void _handleOpenBook(String callbackId, String filePath) {
    _sendResponse(callbackId, {
      'success': true,
      'message': 'Opening book: $filePath',
    });
  }

  void _sendResponse(String callbackId, Map<String, dynamic> data) {
    if (_controller == null) return;

    final response = jsonEncode(data);
    _controller!.runJavaScript("window.bookBridgeCallbacks['$callbackId']($response)");
  }

  void _sendError(String callbackId, String errorMessage) {
    _sendResponse(callbackId, {
      'success': false,
      'error': errorMessage,
    });
  }
}

typedef BookBridgeCallback = void Function(
  String url,
  String filename,
  void Function(bool success, Uint8List? data) onComplete,
);
