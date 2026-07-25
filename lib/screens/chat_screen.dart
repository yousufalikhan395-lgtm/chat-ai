import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/bot_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class ChatScreen extends StatefulWidget {
  final ApiService api;
  final StorageService storage;
  const ChatScreen({super.key, required this.api, required this.storage});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  final _scrollCtrl = ScrollController();
  final _uuid = const Uuid();

  List<ChatMessage> _messages = [];
  BotModel? _currentBot;
  List<BotModel> _allBots = [];
  bool _loading = false;
  bool _streaming = false;
  File? _pendingImage;
  bool _initialized = false;

  @override void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await widget.api.auth();
      final bots = await widget.api.fetchBots();
      final lastId = await widget.storage.loadBotId();
      _allBots = bots.map((b) => BotModel.fromJson(b)).toList();
      if (lastId != null) {
        _currentBot = _allBots.cast<BotModel?>().firstWhere((b) => b!.botId == lastId, orElse: () => null);
      }
      _currentBot ??= _allBots.isNotEmpty ? _allBots[0] : null;
      setState(() => _initialized = true);
    } catch (e) {
      setState(() => _initialized = true);
      _showError('Init failed: $e');
    }
  }

  void _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImage == null) return;
    if (_currentBot == null) return;

    final userMsg = ChatMessage(id: _uuid.v4(), role: 'user', content: text, imagePath: _pendingImage?.path);
    final aiMsg = ChatMessage(id: _uuid.v4(), role: 'assistant', content: '');

    setState(() {
      _messages.add(userMsg);
      _messages.add(aiMsg);
      _controller.clear();
      _streaming = true;
      _pendingImage = null;
    });

    final isFirstMsg = _messages.where((m) => m.role == 'user').length <= 1;

    try {
      final imageFile = userMsg.imagePath != null ? File(userMsg.imagePath!) : null;
      final stream = widget.api.sendMessage(
        message: text.isEmpty ? 'Analyze this image' : text,
        model: _currentBot!.model,
        service: _currentBot!.service,
        botId: _currentBot!.botId,
        imageFile: imageFile,
      );
      final buf = StringBuffer();
      await for (final chunk in stream) {
        buf.write(chunk);
        final idx = _messages.length - 1;
        setState(() => _messages[idx] = ChatMessage(id: aiMsg.id, role: 'assistant', content: buf.toString()));
        _scrollDown();
      }
    } catch (e) {
      final idx = _messages.length - 1;
      setState(() => _messages[idx] = ChatMessage(id: aiMsg.id, role: 'assistant', content: 'Error: $e'));
    }
    setState(() => _streaming = false);
    _save();

    if (isFirstMsg && widget.api.currentChatId != null && text.isNotEmpty) {
      final title = text.length > 50 ? '${text.substring(0, 47)}...' : text;
      widget.api.updateTitle(widget.api.currentChatId!, title);
    }
  }

  void _save() {
    if (widget.api.currentChatId != null) {
      widget.storage.saveMessages(widget.api.currentChatId!, _messages);
    }
  }

  void _selectImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x != null) setState(() => _pendingImage = File(x.path));
  }

  void _pickCamera() async {
    final x = await _picker.pickImage(source: ImageSource.camera);
    if (x != null) setState(() => _pendingImage = File(x.path));
  }

  void _showBotSheet() async {
    final sel = await showModalBottomSheet<BotModel>(
      context: context,
      builder: (_) => _BotListSheet(bots: _allBots, current: _currentBot),
    );
    if (sel != null) {
      setState(() => _currentBot = sel);
      widget.storage.saveBotId(sel.botId);
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override Widget build(BuildContext context) {
    if (!_initialized) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentBot?.name ?? 'AI Chat', style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.swap_horiz), onPressed: _showBotSheet),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'new') _newChat();
              if (v == 'history') _showHistory();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('New chat')),
              const PopupMenuItem(value: 'history', child: Text('History')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _messages.isEmpty
            ? const Center(child: Text('Send a message to start', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                controller: _scrollCtrl,
                padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.of(context).viewInsets.bottom),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
              ),
          ),
          if (_pendingImage != null) Container(
            height: 80, color: Colors.grey[100],
            child: Stack(children: [
              Image.file(_pendingImage!, width: 80, height: 80, fit: BoxFit.cover),
              Positioned(right: 4, top: 4, child: GestureDetector(
                onTap: () => setState(() => _pendingImage = null),
                child: const CircleAvatar(radius: 12, child: Icon(Icons.close, size: 14)),
              )),
            ]),
          ),
          Container(
            color: Theme.of(context).cardColor,
            child: SafeArea(
              child: Row(children: [
                if (_currentBot?.supportsImage == true) ...[
                  IconButton(icon: const Icon(Icons.image), onPressed: _selectImage),
                  IconButton(icon: const Icon(Icons.camera_alt), onPressed: _pickCamera),
                ],
                Expanded(child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _streaming ? null : (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Message...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                )),
                IconButton(
                  icon: _streaming ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                  onPressed: _streaming ? null : _send,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _newChat() {
    widget.api.newChat();
    setState(() => _messages = []);
  }

  void _showHistory() async {
    final chatId = await Navigator.push<String>(
      context, MaterialPageRoute(builder: (_) => _HistoryScreen(api: widget.api)),
    );
    if (chatId != null) {
      final msgs = await widget.storage.loadMessages(chatId);
      setState(() => _messages = msgs);
    }
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  const _MessageBubble({required this.msg});

  static final _imgUrlRe = RegExp(
    r'https?://[^\s]+?\.(?:png|jpg|jpeg|webp|gif)(?:\?[^\s]*)?',
    caseSensitive: false,
  );

  void _showImage(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(url, fit: BoxFit.contain,
                loadingBuilder: (_, child, p) => p == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _preprocess(String text) {
    return text.replaceAllMapped(_imgUrlRe, (m) => '![image](${m.group(0)})');
  }

  @override Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final text = msg.content;
    if (text.isEmpty && msg.imagePath == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          if (msg.imagePath != null)
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(msg.imagePath!), height: 150, fit: BoxFit.cover)),
          if (text.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? (isDark ? Colors.blue[800] : Colors.blue[100]) : (isDark ? Colors.grey[800] : Colors.grey[200]),
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isUser ? const Radius.circular(4) : null,
                  bottomLeft: !isUser ? const Radius.circular(4) : null,
                ),
              ),
              child: MarkdownBody(
                data: _preprocess(text),
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                  a: TextStyle(color: isDark ? Colors.lightBlue[200] : Colors.blue),
                  code: TextStyle(backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300], fontSize: 13, color: isDark ? Colors.green[200] : Colors.black87),
                  codeblockDecoration: BoxDecoration(color: isDark ? Colors.grey[850] : Colors.grey[300], borderRadius: BorderRadius.circular(8)),
                  listBullet: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(left: BorderSide(width: 3, color: isDark ? Colors.grey[600]! : Colors.grey[400]!)),
                    color: isDark ? Colors.grey[850] : Colors.grey[100],
                  ),
                ),
                imageBuilder: (uri, title, alt) {
                  final url = uri.toString();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: GestureDetector(
                      onTap: () => _showImage(context, url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(url, height: 200, width: double.infinity, fit: BoxFit.contain,
                          loadingBuilder: (_, child, p) {
                            if (p == null) return child;
                            return Container(height: 200, color: isDark ? Colors.grey[850] : Colors.grey[300], child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
                          },
                          errorBuilder: (_, __, ___) => Container(height: 200, color: isDark ? Colors.grey[850] : Colors.grey[300], child: const Center(child: Icon(Icons.broken_image))),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class _BotListSheet extends StatelessWidget {
  final List<BotModel> bots;
  final BotModel? current;
  const _BotListSheet({required this.bots, required this.current});

  @override Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Select Model', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      const Divider(height: 1),
      SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: ListView.separated(
          itemCount: bots.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final b = bots[i];
              return ListTile(
                selected: b.botId == current?.botId,
                title: Text(b.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text('${b.service} / ${b.model}', style: const TextStyle(fontSize: 11)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (b.supportsImage) const Icon(Icons.image, size: 16, color: Colors.grey),
                  if (b.isVip) const Icon(Icons.star, color: Colors.amber, size: 16),
                ]),
                onTap: () => Navigator.pop(context, b),
              );
          },
        ),
      ),
    ]);
  }
}

class _HistoryScreen extends StatefulWidget {
  final ApiService api;
  const _HistoryScreen({required this.api});
  @override State<_HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<_HistoryScreen> {
  List<Map<String, dynamic>> _convs = [];

  @override void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final convs = await widget.api.getConversations();
      setState(() => _convs = convs);
    } catch (_) {}
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat History')),
      body: _convs.isEmpty
        ? const Center(child: Text('No conversations'))
        : ListView.builder(
            itemCount: _convs.length,
            itemBuilder: (_, i) {
              final c = _convs[i];
              return ListTile(
                title: Text(c['title']?.toString() ?? 'Chat ${c['_id']?.toString().substring(0, 8)}'),
                onTap: () => Navigator.pop(context, c['_id']?.toString()),
              );
            },
          ),
    );
  }
}
