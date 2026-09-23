import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

class ApiService {
  static const String baseUrl = 'https://chatopenai.sboomtools.net';
  static const String verApi = 'v6.2';
  static const String signKey = 'NEWWAY-SM-HUNGMANH-CHATAI';
  static const String package = 'newway.open.chatgpt.ai.chat.bot.free';
  static const String salt = 'AA:41:A5:CB:23:F5:F8:24:32:09:36:41:NW:13:69:69:32:5D:C8:B6:32:CC:47:90:SM:28:0F:3F:40:32:02:FF';
  static const String platform = 'android';
  static const String versionApp = '10.5.3';
  static const String isVip = '1';

  // Upstream WAF blocks non-browser clients (Dart/httpx default UAs get
  // 400/403 on every request). Send browser-like headers on ALL requests,
  // mirroring the web fix.
  static const Map<String, String> upstreamHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  String? _token;
  String? _chatId;

  String _sign(String msg) {
    final content = '$salt&$msg&$package';
    return hmacSha256(signKey, content);
  }

  static String hmacSha256(String key, String content) {
    final hmac = Hmac(sha256, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(content));
    return digest.toString();
  }

  Map<String, String> get _headers => {
    ...upstreamHeaders,
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  String _safeSnippet(String body, [int max = 300]) =>
      body.length <= max ? body : body.substring(0, max);

  Future<void> auth() async {
    final uuid = const Uuid().v4();
    final r = await http.post(
      Uri.parse('$baseUrl/api/user/identifier'),
      headers: {...upstreamHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'uuid': uuid, 'platform': platform}),
    );
    if (r.statusCode == 403 || r.statusCode == 400) {
      throw Exception('Auth blocked (${r.statusCode}): ${_safeSnippet(r.body)}');
    }
    final data = jsonDecode(r.body);
    if (data['code'] != 200) throw Exception(data['message'] ?? 'Auth failed');
    _token = data['data']['token'];
  }

  Future<List<Map<String, dynamic>>> fetchBots() async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/$verApi/general/services_v2'),
      headers: _headers,
    );
    if (r.statusCode == 403 || r.statusCode == 400) {
      throw Exception('Fetch blocked (${r.statusCode}): ${_safeSnippet(r.body)}');
    }
    final data = jsonDecode(r.body);
    if (data['code'] != 200) throw Exception(data['message'] ?? 'Fetch failed');
    final List<Map<String, dynamic>> bots = [];
    for (final section in ['featured_bots', 'official_bots', 'aistore_bots', 'new_tools_bots']) {
      final list = data['data'][section];
      if (list != null) bots.addAll(List<Map<String, dynamic>>.from(list));
    }
    return bots;
  }

  Stream<String> sendMessage({
    required String message,
    required String model,
    required String service,
    required String botId,
    bool isImageBot = false,
    String? chatId,
    File? imageFile,
  }) async* {
    chatId = chatId ?? _chatId;
    final uri = Uri.parse('$baseUrl/api/$verApi/general/completionFast');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..fields['message'] = message
      ..fields['model'] = model
      ..fields['service'] = service
      ..fields['signature'] = _sign(message)
      ..fields['stream'] = isImageBot ? 'false' : 'true'
      ..fields['platform'] = platform
      ..fields['version_app'] = versionApp
      ..fields['is_vip'] = isVip
      ..fields['bot_id'] = botId;

    if (chatId != null) request.fields['chat_id'] = chatId;

    if (imageFile != null) {
      final ext = imageFile.path.split('.').last.toLowerCase();
      final mime = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      request.files.add(
          await http.MultipartFile.fromPath('file', imageFile.path, contentType: MediaType.parse(mime)));
    }

    final streamed = await request.send();
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception('API ${streamed.statusCode}: ${_safeSnippet(body, 300)}');
    }

    final body = await streamed.stream.bytesToString();

    // Try single JSON response (image generation models)
    if (body.isNotEmpty && body[0] == '{') {
      try {
        final root = jsonDecode(body) as Map?;
        final data = root?['data'] as Map?;
        if (data != null && data['content'] != null) {
          _chatId = (data['created_chat'] as Map?)?['_id'] as String?;
          final text = _buildJsonContent(data);
          if (text.isNotEmpty) {
            yield text;
            return;
          }
        }
      } catch (_) {}
    }

    // SSE streaming (text models)
    bool first = true;
    for (final line in body.split('\n')) {
      if (line.isEmpty) continue;
      String raw = line;
      if (raw.startsWith('data: ')) raw = raw.substring(6);
      if (raw == '[DONE]') break;
      try {
        final j = jsonDecode(raw);
        if (first && j.containsKey('_id') && !j.containsKey('text')) {
          _chatId = j['_id'];
          first = false;
          continue;
        }
        first = false;
        if (j['text'] != null && j['text'].toString().isNotEmpty) {
          yield j['text'];
        }
      } catch (_) {}
    }
  }

  // Image models return the image URL(s) in data.mixed_content[].url
  // (and sometimes data.images[]). Preserve upstream order: image first, then text.
  String _buildJsonContent(Map? data) {
    if (data == null) return '';
    final content = data['content']?.toString() ?? '';
    final builder = StringBuffer();
    final mixed = data['mixed_content'];
    if (mixed is List) {
      for (final item in mixed) {
        if (item is Map) {
          final url = item['url']?.toString();
          final text = item['text']?.toString();
          if (url != null && url.isNotEmpty) {
            builder.write('\n$url\n');
          } else if (text != null && text.isNotEmpty) {
            builder.write(text);
          }
        }
      }
    }
    final out = builder.toString().split('\n').where((l) => l.isNotEmpty).join('\n');
    if (out.isEmpty) {
      final images = data['images'];
      if (images is List) {
        return images.map((u) => u.toString()).where((u) => u.isNotEmpty).join('\n');
      }
      return content;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> getConversations({int page = 1}) async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/conversations?page=$page'),
      headers: _headers,
    );
    return _parseList(r);
  }

  Future<void> deleteConversation(String chatId) async {
    final r = await http.delete(
      Uri.parse('$baseUrl/api/conversation'),
      headers: _headers,
      body: {'chat_id': chatId},
    );
    _check(r);
  }

  Future<void> updateTitle(String chatId, String title) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/update-conversation'),
      headers: _headers,
      body: {'chat_id': chatId, 'title': title},
    );
    _check(r);
  }

  void newChat() => _chatId = null;
  String? get currentChatId => _chatId;
  bool get isAuthed => _token != null;

  List<Map<String, dynamic>> _parseList(http.Response r) {
    final data = jsonDecode(r.body);
    if (data['code'] != 200) throw Exception(data['message'] ?? 'Failed');
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  }

  void _check(http.Response r) {
    final data = jsonDecode(r.body);
    if (data['code'] != 200) throw Exception(data['message'] ?? 'Failed');
  }
}
