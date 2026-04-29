import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

import '../../utils/proxy_utils.dart';

class OpdsModule extends StatefulWidget {
  final ValueChanged<String>? onBookSelect;

  const OpdsModule({super.key, this.onBookSelect});

  @override
  State<OpdsModule> createState() => _OpdsModuleState();
}

class _OpdsModuleState extends State<OpdsModule> {
  final OpdsService _opdsService = OpdsService();
  List<Map<String, String>> _catalogs = [];
  List<Map<String, dynamic>> _books = [];
  String _selectedCatalog = '';
  String _searchQuery = '';
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _catalogs = _opdsService.getDefaultCatalogs();
    if (_catalogs.isNotEmpty) {
      _selectedCatalog = _catalogs[0]['url'] ?? '';
    }
  }

  @override
  void dispose() {
    _opdsService.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final result = await _opdsService.fetchCatalog(_selectedCatalog);
    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _books = List<Map<String, dynamic>>.from(result['entries'] ?? []);
      } else {
        _errorMessage = result['error'] ?? '加载失败';
      }
    });
  }

  Future<void> _searchBooks() async {
    if (_searchQuery.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final result = await _opdsService.searchBooks(_selectedCatalog, _searchQuery);
    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _books = List<Map<String, dynamic>>.from(result['entries'] ?? []);
      } else {
        _errorMessage = result['error'] ?? '搜索失败';
      }
    });
  }

  void _handleBookTap(Map<String, dynamic> book) {
    final links = book['links'] as List? ?? [];
    
    String? bookUrl;
    String? subCatalogUrl;
    
    for (var link in links) {
      final type = link['type'] as String? ?? '';
      final href = link['href'] as String? ?? '';
      
      if (type.contains('application/epub') || type.contains('application/pdf')) {
        bookUrl = href;
      } else if (href.isNotEmpty) {
        subCatalogUrl = href;
      }
    }

    if (bookUrl != null && widget.onBookSelect != null) {
      widget.onBookSelect!(bookUrl);
    } else if (subCatalogUrl != null) {
      _loadSubCatalog(subCatalogUrl);
    } else {
      _showBookDetail(book);
    }
  }

  Future<void> _loadSubCatalog(String url) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final result = await _opdsService.fetchCatalog(url);
    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _books = List<Map<String, dynamic>>.from(result['entries'] ?? []);
      } else {
        _errorMessage = result['error'] ?? '加载失败';
      }
    });
  }

  void _showBookDetail(Map<String, dynamic> book) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(book['title'] ?? '未知书籍'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('作者: ${book['author'] ?? '未知'}'),
                const SizedBox(height: 8),
                Text('简介: ${book['summary'] ?? '暂无简介'}'),
                const SizedBox(height: 8),
                Text('更新时间: ${book['updated'] ?? '未知'}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPDS 开放图书馆'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedCatalog,
                  items: _catalogs.map((catalog) {
                    return DropdownMenuItem(
                      value: catalog['url'],
                      child: Text(catalog['name'] ?? ''),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCatalog = value ?? '';
                    });
                  },
                  decoration: const InputDecoration(labelText: '选择图书馆'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: '搜索书籍',
                          hintText: '输入书名或作者',
                        ),
                        onChanged: (value) => _searchQuery = value,
                        onSubmitted: (value) => _searchBooks(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _searchBooks,
                      child: const Text('搜索'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _loadCatalog,
                  child: const Text('加载目录'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage))
                    : ListView.builder(
                        itemCount: _books.length,
                        itemBuilder: (context, index) {
                          final book = _books[index];
                          return ListTile(
                            title: Text(book['title'] ?? '未知'),
                            subtitle: Text(book['author'] ?? '未知作者'),
                            trailing: const Icon(Icons.arrow_forward),
                            onTap: () => _handleBookTap(book),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class OpdsService {
  final http.Client _client = http.Client();

  Map<String, String> _defaultHeaders = {
    'Accept': 'application/atom+xml, application/xml, text/xml',
    'User-Agent': 'FlutterOPDSClient/1.0.0',
  };

  Future<Map<String, dynamic>> fetchCatalog(String url) async {
    try {
      final response = await _client.get(Uri.parse(url), headers: _defaultHeaders);
      
      if (response.statusCode == 200) {
        return _parseOpdsFeed(response.body);
      } else {
        throw Exception('HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> searchBooks(String url, String query) async {
    try {
      final encodedQuery = Uri.encodeQueryComponent(query);
      final searchUrl = url.contains('?') 
          ? '$url&q=$encodedQuery'
          : '$url?q=$encodedQuery';
      
      final response = await _client.get(Uri.parse(searchUrl), headers: _defaultHeaders);
      
      if (response.statusCode == 200) {
        return _parseOpdsFeed(response.body);
      } else {
        throw Exception('HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> downloadBook(String url) async {
    final bytes = await ProxyUtils.downloadWithProxy(url);
    
    if (bytes != null) {
      return {
        'success': true,
        'bytes': bytes,
        'contentLength': bytes.length,
      };
    } else {
      return {
        'success': false,
        'error': '下载失败',
      };
    }
  }

  Map<String, dynamic> _parseOpdsFeed(String xmlString) {
    try {
      final document = xml.XmlDocument.parse(xmlString);
      final List<Map<String, dynamic>> entries = [];
      final List<Map<String, dynamic>> links = [];

      final feedElement = document.findElements('feed').firstOrNull;
      String title = 'Unknown Feed';
      String subtitle = '';

      if (feedElement != null) {
        title = feedElement.findElements('title').firstOrNull?.text ?? 'Unknown Feed';
        subtitle = feedElement.findElements('subtitle').firstOrNull?.text ?? '';

        for (final entryElement in feedElement.findElements('entry')) {
          entries.add(_parseEntryElement(entryElement));
        }

        for (final linkElement in feedElement.findElements('link')) {
          links.add(_parseLinkElement(linkElement));
        }
      }

      return {
        'success': true,
        'title': title,
        'subtitle': subtitle,
        'entries': entries,
        'links': links,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Map<String, dynamic> _parseEntryElement(xml.XmlElement entryElement) {
    final List<Map<String, dynamic>> links = [];
    String id = '';
    String title = 'Unknown';
    String author = '';
    String summary = '';
    String updated = '';

    id = entryElement.findElements('id').firstOrNull?.text ?? '';
    title = entryElement.findElements('title').firstOrNull?.text ?? 'Unknown';
    updated = entryElement.findElements('updated').firstOrNull?.text ?? '';

    final authorElement = entryElement.findElements('author').firstOrNull;
    if (authorElement != null) {
      author = authorElement.findElements('name').firstOrNull?.text ?? '';
    }

    summary = entryElement.findElements('summary').firstOrNull?.text ?? '';

    for (final linkElement in entryElement.findElements('link')) {
      links.add(_parseLinkElement(linkElement));
    }

    return {
      'id': id,
      'title': title,
      'author': author,
      'summary': summary,
      'links': links,
      'updated': updated,
    };
  }

  Map<String, dynamic> _parseLinkElement(xml.XmlElement linkElement) {
    return {
      'href': ProxyUtils.convertToProxyUrl(linkElement.getAttribute('href') ?? ''),
      'rel': linkElement.getAttribute('rel') ?? '',
      'type': linkElement.getAttribute('type') ?? '',
      'title': linkElement.getAttribute('title') ?? '',
    };
  }

  List<Map<String, String>> getDefaultCatalogs() {
    return [
      {'name': '轻小说文库(简体)', 'url': '/wenku8/zh_CN'},
      {'name': '轻小说文库(繁体)', 'url': '/wenku8/zh_TW'},
    ];
  }

  void dispose() {
    _client.close();
  }
}