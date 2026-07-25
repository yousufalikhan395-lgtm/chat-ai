import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

class StorageService {
  static const String _convKey = 'conversations_';

  Future<void> saveMessages(String chatId, List<ChatMessage> msgs) async {
    final prefs = await SharedPreferences.getInstance();
    final json = msgs.map((m) => m.toJson()).toList();
    await prefs.setString('$_convKey$chatId', jsonEncode(json));
  }

  Future<List<ChatMessage>> loadMessages(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_convKey$chatId');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((j) => ChatMessage.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> deleteMessages(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_convKey$chatId');
  }

  Future<List<String>> getSavedChatIds() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    return keys.where((k) => k.startsWith(_convKey)).map((k) => k.substring(_convKey.length)).toList();
  }

  Future<void> saveBotId(String botId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_bot_id', botId);
  }

  Future<String?> loadBotId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_bot_id');
  }
}
