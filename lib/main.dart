import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'screens/chat_screen.dart';
import 'theme.dart';

void main() => runApp(const ChatApp());

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Donkey Chat',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      home: _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  @override State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final _api = ApiService();
  final _storage = StorageService();

  @override Widget build(BuildContext context) {
    return ChatScreen(api: _api, storage: _storage);
  }
}
