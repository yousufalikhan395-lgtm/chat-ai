import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'asset_naming.dart';
import 'storage_service.dart';

class AssetItem {
  final String url;
  final String? localPath;
  final String messageId;
  final String? chatId;
  final DateTime timestamp;

  const AssetItem({
    required this.url,
    this.localPath,
    required this.messageId,
    this.chatId,
    required this.timestamp,
  });

  AssetItem copyWith({String? localPath}) => AssetItem(
        url: url,
        localPath: localPath ?? this.localPath,
        messageId: messageId,
        chatId: chatId,
        timestamp: timestamp,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'localPath': localPath,
        'messageId': messageId,
        'chatId': chatId,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AssetItem.fromJson(Map<String, dynamic> j) => AssetItem(
        url: j['url'] as String,
        localPath: j['localPath'] as String?,
        messageId: j['messageId'] as String? ?? '',
        chatId: j['chatId'] as String?,
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Persistent index of generated image assets: keeps the source URL plus a
/// local copy under the app documents dir (offline thumbnails / durability).
class AssetStore {
  static const String _key = 'generated_assets';
  static const String _indexedFlag = 'assets_indexed_v1';

  final Map<String, AssetItem> _items = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        for (final j in jsonDecode(raw) as List) {
          final item = AssetItem.fromJson(j as Map<String, dynamic>);
          _items[item.url] = item;
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_items.values.map((e) => e.toJson()).toList()));
  }

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/generated_assets');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Index a generated image URL (deduped). Downloads a local copy in the
  /// background; entry stays valid (url-only) if the download fails.
  Future<void> record(String url,
      {required String messageId, String? chatId}) async {
    await _ensureLoaded();
    if (_items.containsKey(url)) return;
    final item = AssetItem(
      url: url,
      messageId: messageId,
      chatId: chatId,
      timestamp: DateTime.now(),
    );
    _items[url] = item;
    await _persist();
    _downloadCopy(item);
  }

  Future<void> _downloadCopy(AssetItem item) async {
    try {
      final dir = await _dir();
      final name = md5.convert(utf8.encode(item.url)).toString();
      final file = File('${dir.path}/$name.${AssetNaming.extensionOf(item.url)}');
      if (!await file.exists()) {
        final res = await http
            .get(Uri.parse(item.url))
            .timeout(const Duration(seconds: 60));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) return;
        await file.writeAsBytes(res.bodyBytes, flush: true);
      }
      if (_items[item.url]?.localPath != file.path) {
        _items[item.url] = item.copyWith(localPath: file.path);
        await _persist();
      }
    } catch (_) {}
  }

  Future<List<AssetItem>> all() async {
    await _ensureLoaded();
    final list = _items.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<void> remove(String url) async {
    await _ensureLoaded();
    final item = _items.remove(url);
    await _persist();
    final path = item?.localPath;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    await _ensureLoaded();
    for (final item in _items.values) {
      final path = item.localPath;
      if (path != null) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    _items.clear();
    await _persist();
  }

  /// One-time import of image URLs from previously saved conversations.
  Future<void> retroScan(StorageService storage) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_indexedFlag) == true) return;
    await _ensureLoaded();
    try {
      final ids = await storage.getSavedChatIds();
      for (final id in ids) {
        final msgs = await storage.loadMessages(id);
        for (final m in msgs) {
          if (m.role != 'assistant' || m.content.isEmpty) continue;
          for (final url in extractAssetUrls(m.content)) {
            await record(url, messageId: m.id, chatId: id);
          }
        }
      }
    } catch (_) {}
    await prefs.setBool(_indexedFlag, true);
  }
}
