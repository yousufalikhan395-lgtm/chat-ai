import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/bot_model.dart';
import '../services/api_service.dart';
import '../services/asset_naming.dart';
import '../services/asset_store.dart';
import '../services/image_download_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import 'gallery_screen.dart';

String fmtTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
  final _focusNode = FocusNode();
  final _uuid = const Uuid();
  final _assets = AssetStore();

  List<ChatMessage> _messages = [];
  BotModel? _currentBot;
  List<BotModel> _allBots = [];
  bool _streaming = false;
  bool _wasStopped = false;
  File? _pendingImage;
  bool _initialized = false;

  @override void initState() {
    super.initState();
    _init();
  }

  @override void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _assets.retroScan(widget.storage);
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

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImage == null) return;
    if (_currentBot == null || _streaming) return;
    final imagePath = _pendingImage?.path;
    _controller.clear();
    setState(() => _pendingImage = null);
    _runSend(text, imagePath);
  }

  Future<void> _runSend(String text, String? imagePath) async {
    if (_currentBot == null || _streaming) return;
    final userMsg = ChatMessage(id: _uuid.v4(), role: 'user', content: text, imagePath: imagePath);
    final aiMsg = ChatMessage(id: _uuid.v4(), role: 'assistant', content: '');

    setState(() {
      _messages.add(userMsg);
      _messages.add(aiMsg);
      _streaming = true;
      _wasStopped = false;
    });

    final isFirstMsg = _messages.where((m) => m.role == 'user').length <= 1;
    final buf = StringBuffer();

    try {
      final stream = widget.api.sendMessage(
        message: text.isEmpty ? 'Analyze this image' : text,
        model: _currentBot!.model,
        service: _currentBot!.service,
        botId: _currentBot!.botId,
        isImageBot: _currentBot!.isImageBot,
        imageFile: imagePath != null ? File(imagePath) : null,
      );
      await for (final chunk in stream) {
        buf.write(chunk);
        final idx = _messages.length - 1;
        setState(() => _messages[idx] =
            ChatMessage(id: aiMsg.id, role: 'assistant', content: buf.toString(), timestamp: aiMsg.timestamp));
        _scrollDown();
      }
    } catch (e) {
      final idx = _messages.length - 1;
      setState(() => _messages[idx] =
          ChatMessage(id: aiMsg.id, role: 'assistant', content: 'Error: $e', timestamp: aiMsg.timestamp));
    }
    setState(() => _streaming = false);
    _save();

    if (buf.isEmpty && _wasStopped) {
      final idx = _messages.length - 1;
      setState(() => _messages[idx] =
          ChatMessage(id: aiMsg.id, role: 'assistant', content: '⏹ Stopped', timestamp: aiMsg.timestamp));
      _save();
    }

    // Index generated image URLs into the assets gallery (links + local copy).
    final content = buf.toString();
    if (content.isNotEmpty) {
      for (final url in extractAssetUrls(content)) {
        _assets.record(url, messageId: aiMsg.id, chatId: widget.api.currentChatId);
      }
    }

    if (isFirstMsg && widget.api.currentChatId != null && text.isNotEmpty) {
      final title = text.length > 50 ? '${text.substring(0, 47)}...' : text;
      widget.api.updateTitle(widget.api.currentChatId!, title);
    }
  }

  int _userIndexFor(int index) {
    for (int i = index; i >= 0; i--) {
      if (_messages[i].role == 'user') return i;
    }
    return -1;
  }

  Future<void> _retryFrom(int index) async {
    if (_streaming) return;
    final ui = _userIndexFor(index);
    if (ui < 0) return;
    final text = _messages[ui].content;
    final imagePath = _messages[ui].imagePath;
    setState(() => _messages = _messages.sublist(0, ui));
    widget.api.newChat();
    await _runSend(text, imagePath);
  }

  Future<void> _editUserMessage(int index) async {
    if (_streaming) return;
    final msg = _messages[index];
    final newText = await _showEditDialog(msg.content);
    if (newText == null || !mounted) return;
    final edited = newText.trim();
    if (edited.isEmpty && msg.imagePath == null) return;
    setState(() => _messages = _messages.sublist(0, index));
    widget.api.newChat();
    await _runSend(edited, msg.imagePath);
  }

  Future<void> _editAssistantMessage(int index) async {
    if (_streaming || index >= _messages.length) return;
    final msg = _messages[index];
    final newText = await _showEditDialog(msg.content);
    if (newText == null || !mounted) return;
    setState(() {
      _messages[index] = ChatMessage(
        id: msg.id,
        role: msg.role,
        content: newText,
        timestamp: msg.timestamp,
        imagePath: msg.imagePath,
      );
    });
    _save();
  }

  Future<String?> _showEditDialog(String initial) {
    return showDialog<String>(
      context: context,
      builder: (_) => _EditDialog(initial: initial),
    );
  }

  void _showMessageActions(ChatMessage msg, int index) {
    final isUser = msg.role == 'user';
    final hasText = msg.content.trim().isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('MESSAGE ACTIONS', style: eyebrowStyle(context, color: AppColors.muted)),
              ),
            ),
            if (hasText)
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: AppColors.accent),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Clipboard.setData(ClipboardData(text: msg.content));
                  _toast('Copied');
                },
              ),
            if (hasText)
              ListTile(
                leading: const Icon(Icons.share_rounded, color: AppColors.accent),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  SharePlus.instance
                      .share(ShareParams(text: msg.content, title: 'Donkey Chat message'));
                },
              ),
            if (hasText && !_streaming)
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: AppColors.accent),
                title: Text(isUser ? 'Edit & resend' : 'Edit'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  if (isUser) {
                    _editUserMessage(index);
                  } else {
                    _editAssistantMessage(index);
                  }
                },
              ),
            if (!_streaming && (hasText || msg.imagePath != null))
              ListTile(
                leading: const Icon(Icons.refresh_rounded, color: AppColors.accent),
                title: Text(isUser ? 'Resend' : 'Regenerate'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _retryFrom(index);
                },
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _stop() {
    _wasStopped = true;
    widget.api.stopStreaming();
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
      if (sel.botId != _currentBot?.botId) {
        // Switching model always starts a fresh conversation.
        _save();
        widget.api.newChat();
        setState(() {
          _currentBot = sel;
          _messages = [];
        });
      }
      widget.storage.saveBotId(sel.botId);
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _exportChat() {
    if (_messages.isEmpty) {
      _toast('Nothing to export');
      return;
    }
    final botName = _currentBot?.name ?? 'AI';
    final sb = StringBuffer('# $botName\n\n');
    for (final m in _messages) {
      final hasContent = m.content.trim().isNotEmpty;
      if (!hasContent && m.imagePath == null) continue;
      final who = m.role == 'user' ? 'You' : botName;
      sb.writeln('**$who** · ${fmtTime(m.timestamp)}');
      if (hasContent) sb.writeln(m.content);
      if (m.imagePath != null) sb.writeln('*(image attached)*');
      sb.writeln();
    }
    SharePlus.instance.share(ShareParams(text: sb.toString().trim(), title: 'Donkey Chat export'));
  }

  void _openGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GalleryScreen(store: _assets)),
    );
  }

  @override Widget build(BuildContext context) {
    if (!_initialized) return const _BootScreen();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Text.rich(
          TextSpan(
            text: _currentBot?.name ?? 'Donkey Chat',
            style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                letterSpacing: -0.3,
                fontWeight: FontWeight.w600,
                color: AppColors.text),
            children: const [
              TextSpan(text: '.', style: TextStyle(color: AppColors.accent, fontSize: 21)),
            ],
          ),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.swap_horiz), onPressed: _showBotSheet, tooltip: 'Switch model'),
          PopupMenuButton<String>(
            color: AppColors.surface,
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'new') _newChat();
              if (v == 'history') _showHistory();
              if (v == 'images') _openGallery();
              if (v == 'export') _exportChat();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'new',
                  child: _MenuItem(icon: Icons.add_comment_outlined, label: 'New chat')),
              const PopupMenuItem(
                  value: 'history',
                  child: _MenuItem(icon: Icons.history, label: 'History')),
              const PopupMenuItem(
                  value: 'images',
                  child: _MenuItem(icon: Icons.auto_awesome_outlined, label: 'My images')),
              const PopupMenuItem(
                  value: 'export',
                  child: _MenuItem(icon: Icons.ios_share_outlined, label: 'Export chat')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState(onStart: () => _focusNode.requestFocus())
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _MessageBubble(
                      msg: _messages[i],
                      onLongPress: () => _showMessageActions(_messages[i], i),
                    ),
                  ),
          ),
          if (_pendingImage != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.line),
              ),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_pendingImage!, width: 72, height: 72, fit: BoxFit.cover),
                ),
                Positioned(
                  right: -6,
                  top: -6,
                  child: GestureDetector(
                    onTap: () => setState(() => _pendingImage = null),
                    child: const _MiniCloseButton(),
                  ),
                ),
              ]),
            ),
          _InputBar(
            controller: _controller,
            focusNode: _focusNode,
            streaming: _streaming,
            showImageButtons: _currentBot?.supportsImage == true,
            onSend: _send,
            onStop: _stop,
            onGallery: _selectImage,
            onCamera: _pickCamera,
          ),
        ],
      ),
    );
  }

  void _newChat() {
    _save();
    widget.api.newChat();
    setState(() => _messages = []);
  }

  void _showHistory() async {
    final chatId = await Navigator.push<String>(
      context, MaterialPageRoute(builder: (_) => HistoryScreen(api: widget.api)),
    );
    if (chatId != null) {
      final msgs = await widget.storage.loadMessages(chatId);
      setState(() => _messages = msgs);
    }
  }
}

/* ---------------------------------------------------------------- boot --- */

class _BootScreen extends StatelessWidget {
  const _BootScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text.rich(
            const TextSpan(
              text: 'ai chat',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 34,
                  letterSpacing: -1.8,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text),
              children: [TextSpan(text: '.', style: TextStyle(color: AppColors.accent, fontSize: 40))],
            ),
          ),
          const SizedBox(height: 6),
          Text('MAKE ROOM FOR WHAT MATTERS', style: eyebrowStyle(context, color: AppColors.muted)),
          const SizedBox(height: 34),
          const SizedBox(
              width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ),
    );
  }
}

/* ----------------------------------------------------------- empty state --- */

class _EmptyState extends StatelessWidget {
  final VoidCallback onStart;
  const _EmptyState({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.accentGlow, blurRadius: 14, spreadRadius: 2)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('A LITTLE LESS NOISE. A LITTLE MORE LIFE.', style: eyebrowStyle(context))),
          ]),
          const SizedBox(height: 20),
          Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.displaySmall,
              children: [
                const TextSpan(text: 'Say what’s\non your '),
                TextSpan(text: 'mind.', style: serifEm.copyWith(fontSize: 54)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Ask anything. Think things through, draft, plan, or just talk it through — '
            'your conversations stay on this device.',
            style: TextStyle(
                fontFamily: 'Inter', fontSize: 15, height: 1.7, color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Start typing  ↗'),
          ),
          const SizedBox(height: 26),
          const _HeroArt(),
          const SizedBox(height: 16),
          Center(
            child: Text('LONG-PRESS A MESSAGE FOR COPY · EDIT · RETRY',
                style: eyebrowStyle(context, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}

/// The CSS artwork from nice.html — pale sun floating over layered hills.
class _HeroArt extends StatefulWidget {
  const _HeroArt();
  @override
  State<_HeroArt> createState() => _HeroArtState();
}

class _HeroArtState extends State<_HeroArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4500))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(150),
          topRight: Radius.circular(150),
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF384E3B), Color(0xFF1D3329), Color(0xFF10251D)],
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.85),
              radius: 1.1,
              colors: [Color(0xFF839275), Color(0x00839275)],
            ),
          ),
        ),
        Positioned(
          top: 26,
          left: 0,
          right: 0,
          child: Center(
            child: Text('A QUIET PLACE TO THINK',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    letterSpacing: 3,
                    color: AppColors.text.withValues(alpha: 0.72))),
          ),
        ),
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Transform.translate(offset: Offset(0, -10 * _ctrl.value), child: child),
          child: Align(
            alignment: const Alignment(0, -0.62),
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFF2EFCA), Color(0xFFCBD29A)]),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFEDF1B6).withValues(alpha: 0.16), blurRadius: 70, spreadRadius: 8),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -80,
          left: -150,
          right: 60,
          height: 280,
          child: Transform.rotate(
            angle: 0.42,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: const Color(0xFF3A5943),
                    borderRadius: BorderRadius.circular(200))),
          ),
        ),
        Positioned(
          bottom: -90,
          left: 120,
          right: -170,
          height: 300,
          child: Transform.rotate(
            angle: -0.52,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: const Color(0xFF243F31),
                    borderRadius: BorderRadius.circular(200))),
          ),
        ),
        Positioned(
          bottom: -230,
          left: -40,
          right: -40,
          height: 340,
          child: DecoratedBox(
              decoration: BoxDecoration(
                  color: const Color(0xFF142E24), borderRadius: BorderRadius.circular(200))),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 22,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Begin where\nyou are.',
                  style: TextStyle(
                      fontFamily: 'InstrumentSerif', fontSize: 24, height: 1.15, color: AppColors.text)),
              Text('YOUR EVERYDAY, REIMAGINED',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      letterSpacing: 2,
                      color: const Color(0xFFC5D0BB).withValues(alpha: 0.9))),
            ],
          ),
        ),
      ]),
    );
  }
}

/* --------------------------------------------------------------- input --- */

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool streaming;
  final bool showImageButtons;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onGallery;
  final VoidCallback onCamera;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.streaming,
    required this.showImageButtons,
    required this.onSend,
    required this.onStop,
    required this.onGallery,
    required this.onCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showImageButtons) ...[
                IconButton(
                    onPressed: onGallery,
                    tooltip: 'Gallery',
                    icon: const Icon(Icons.image_outlined, size: 23)),
                IconButton(
                    onPressed: onCamera,
                    tooltip: 'Camera',
                    icon: const Icon(Icons.photo_camera_outlined, size: 22)),
              ],
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 6,
                    cursorColor: AppColors.accent,
                    style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 15, height: 1.4, color: AppColors.text),
                    textInputAction: TextInputAction.send,
                    onSubmitted: streaming ? null : (_) => onSend(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Message...',
                      hintStyle: const TextStyle(
                          fontFamily: 'Inter', fontSize: 15, color: AppColors.muted),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: streaming ? AppColors.surface2 : AppColors.accent,
                shape: CircleBorder(
                    side: streaming ? const BorderSide(color: AppColors.line) : BorderSide.none),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: streaming ? onStop : onSend,
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: Icon(
                      streaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                      size: 24,
                      color: streaming ? AppColors.text : AppColors.onAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------- bubbles --- */

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  final VoidCallback onLongPress;
  const _MessageBubble({required this.msg, required this.onLongPress});

  void _showImage(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (viewerCtx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download',
                onPressed: () => ImageDownloadService.download(viewerCtx, url),
              ),
            ],
          ),
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

  String _preprocess(String text) => text.replaceAllMapped(assetUrlRe, (m) => '![image](${m.group(0)})');

  /// Splits the message on ``` fences so code blocks render as custom
  /// blocks with a copy button; prose between fences stays Markdown.
  List<Widget> _segments(String raw, bool isUser, BuildContext context) {
    final style = _messageStyleSheet(isUser);
    final parts = raw.split('```');
    final out = <Widget>[];
    Widget prose(String data) => MarkdownBody(
          data: _preprocess(data),
          styleSheet: style,
          onTapLink: (_, __, ___) {},
          sizedImageBuilder: (cfg) {
            final url = cfg.uri.toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Stack(children: [
                GestureDetector(
                  onTap: () => _showImage(context, url),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(url,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, p) => p == null
                            ? child
                            : Container(
                                height: 200,
                                color: AppColors.surface2,
                                child: const Center(
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2))),
                        errorBuilder: (_, __, ___) => Container(
                            height: 200,
                            color: AppColors.surface2,
                            child: const Center(child: Icon(Icons.broken_image)))),
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => ImageDownloadService.download(context, url),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.download, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ]),
            );
          },
        );

    for (var i = 0; i < parts.length; i++) {
      if (i.isOdd) {
        var code = parts[i];
        String? lang;
        final nl = code.indexOf('\n');
        if (nl >= 0) {
          final first = code.substring(0, nl).trim();
          if (first.length <= 16 &&
              RegExp(r'^[A-Za-z0-9+#._-]*$').hasMatch(first)) {
            lang = first.isEmpty ? null : first;
            code = code.substring(nl + 1);
          }
        } else if (code.trim().length <= 16 &&
            RegExp(r'^[A-Za-z0-9+#._-]*$').hasMatch(code.trim())) {
          lang = code.trim().isEmpty ? null : code.trim();
          code = '';
        }
        out.add(_CodeBlock(code: code.trimRight(), lang: lang, isUser: isUser));
      } else {
        if (parts[i].trim().isEmpty) continue;
        out.add(prose(parts[i]));
      }
    }
    if (out.isEmpty) out.add(prose(raw));
    return out;
  }

  @override Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final text = msg.content;
    if (text.isEmpty && msg.imagePath == null) return const SizedBox.shrink();

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(22),
      bottomLeft: isUser ? const Radius.circular(22) : const Radius.circular(4),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: onLongPress,
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (msg.imagePath != null)
                    ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(File(msg.imagePath!), height: 160, fit: BoxFit.cover)),
                  if (text.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                      decoration: BoxDecoration(
                        color: isUser ? AppColors.accent : AppColors.surface,
                        borderRadius: radius,
                        border: isUser ? null : Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _segments(text, isUser, context),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 6, right: 6),
              child: Text(
                fmtTime(msg.timestamp),
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    letterSpacing: 1,
                    color: Color(0x8CADB5A6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fenced code block with a language label and a Copy button.
class _CodeBlock extends StatefulWidget {
  final String code;
  final String? lang;
  final bool isUser;
  const _CodeBlock({required this.code, this.lang, required this.isUser});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final blockBg = widget.isUser ? AppColors.onAccent : const Color(0xFF0D120E);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: blockBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.only(left: 14, right: 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(children: [
            Text(
              (widget.lang ?? 'code').toUpperCase(),
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.6,
                  color: AppColors.muted),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _copy,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 14, color: _copied ? AppColors.accent : AppColors.muted),
              label: Text(
                _copied ? 'Copied' : 'Copy',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: _copied ? AppColors.accent : AppColors.muted),
              ),
            ),
          ]),
        ),
        if (widget.code.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.accent),
            ),
          ),
      ]),
    );
  }
}

// Top-level so bubbles can build their own stylesheet without a State.
MarkdownStyleSheet _messageStyleSheet(bool isUser) {
  const onAccent = AppColors.onAccent;
  const blockBg = Color(0xFF0D120E);
  return MarkdownStyleSheet(
    p: TextStyle(
        fontFamily: 'Inter', fontSize: 15, height: 1.55, color: isUser ? onAccent : AppColors.text),
    strong: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 15.5,
        color: isUser ? onAccent : AppColors.text),
    em: TextStyle(
        fontFamily: 'InstrumentSerif',
        fontStyle: FontStyle.italic,
        fontSize: 17,
        height: 1.35,
        color: isUser ? onAccent : AppColors.accent),
    a: TextStyle(
        color: isUser ? const Color(0xFF3A5943) : AppColors.accent,
        decoration: TextDecoration.underline,
        decorationColor: isUser ? const Color(0x663A5943) : AppColors.accentGlow),
    code: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 13,
        color: AppColors.accent,
        backgroundColor: isUser ? onAccent : blockBg),
    codeblockPadding: const EdgeInsets.all(14),
    codeblockDecoration: BoxDecoration(
      color: isUser ? onAccent : blockBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    blockquote: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14.5,
        height: 1.55,
        fontStyle: FontStyle.italic,
        color: isUser ? onAccent : AppColors.muted),
    blockquotePadding: const EdgeInsets.only(left: 12),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(width: 3, color: isUser ? const Color(0x4D101711) : AppColors.accent),
      ),
    ),
    listBullet: TextStyle(fontSize: 15, color: isUser ? onAccent : AppColors.accent),
    h1: TextStyle(
        fontFamily: 'Inter',
        fontSize: 23,
        letterSpacing: -0.7,
        fontWeight: FontWeight.w600,
        color: isUser ? onAccent : AppColors.text),
    h2: TextStyle(
        fontFamily: 'Inter',
        fontSize: 19.5,
        letterSpacing: -0.5,
        fontWeight: FontWeight.w600,
        color: isUser ? onAccent : AppColors.text),
    h3: TextStyle(
        fontFamily: 'Inter',
        fontSize: 17,
        letterSpacing: -0.4,
        fontWeight: FontWeight.w600,
        color: isUser ? onAccent : AppColors.text),
    horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
  );
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuItem({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 19, color: AppColors.muted),
      const SizedBox(width: 14),
      Text(label),
    ]);
  }
}

class _MiniCloseButton extends StatelessWidget {
  const _MiniCloseButton();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
      child: const Icon(Icons.close, size: 14, color: AppColors.text),
    );
  }
}

/* ------------------------------------------------------------ sheets --- */

class _BotListSheet extends StatelessWidget {
  final List<BotModel> bots;
  final BotModel? current;
  const _BotListSheet({required this.bots, required this.current});

  @override Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SELECT A MODEL', style: eyebrowStyle(context)),
              const SizedBox(height: 5),
              Text('${bots.length} assistants available',
                  style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 13, color: AppColors.muted)),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.line),
              ),
              child: const Text('PRO', style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent)),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Flexible(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: bots.length,
          itemBuilder: (_, i) {
            final b = bots[i];
            final isSel = b.botId == current?.botId;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: isSel ? AppColors.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isSel ? const Color(0x66D5ED9C) : AppColors.line),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Center(
                      child: Text(
                        b.name.isNotEmpty ? b.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent),
                      ),
                    ),
                  ),
                  title: Text(b.name,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                          color: AppColors.text)),
                  subtitle: Text('${b.service} / ${b.model}',
                      style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 11.5, color: AppColors.muted)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (b.supportsImage)
                      const Icon(Icons.image_outlined, size: 16, color: AppColors.muted),
                    if (b.isVip)
                      const Icon(Icons.star_rounded, color: AppColors.accent, size: 17),
                    if (isSel)
                      const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 19),
                  ]),
                  onTap: () => Navigator.pop(context, b),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
    ]);
  }
}

class HistoryScreen extends StatefulWidget {
  final ApiService api;
  const HistoryScreen({super.key, required this.api});
  @override State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
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
      appBar: AppBar(titleSpacing: 20, title: Text.rich(TextSpan(
        text: 'History',
        style: const TextStyle(
            fontFamily: 'Inter', fontSize: 17, letterSpacing: -0.3, fontWeight: FontWeight.w600, color: AppColors.text),
        children: const [TextSpan(text: '.', style: TextStyle(color: AppColors.accent, fontSize: 21))],
      ))),
      body: _convs.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('NOTHING YET', style: eyebrowStyle(context, color: AppColors.muted)),
                const SizedBox(height: 8),
                const Text('No conversations', style: TextStyle(fontFamily: 'Inter', color: AppColors.muted)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _convs.length,
              itemBuilder: (_, i) {
                final c = _convs[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.line),
                        ),
                        child: const Icon(Icons.chat_bubble_outline_rounded,
                            size: 18, color: AppColors.accent),
                      ),
                      title: Text(
                        c['title']?.toString() ??
                            'Chat ${c['_id']?.toString().substring(0, 8) ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                            color: AppColors.text),
                      ),
                      subtitle: const Text('Tap to open',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.muted)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                      onTap: () => Navigator.pop(context, c['_id']?.toString()),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/* --------------------------------------------------------------- edit --- */

class _EditDialog extends StatefulWidget {
  final String initial;
  const _EditDialog({required this.initial});
  @override State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _ctrl;

  @override void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context) {
    return AlertDialog(
      title: Text.rich(const TextSpan(
        text: 'Edit message',
        style: TextStyle(
            fontFamily: 'Inter', fontSize: 19, letterSpacing: -0.4, fontWeight: FontWeight.w600, color: AppColors.text),
        children: [TextSpan(text: '.', style: TextStyle(color: AppColors.accent, fontSize: 23))],
      )),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _ctrl,
          maxLines: null,
          minLines: 5,
          autofocus: true,
          cursorColor: AppColors.accent,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 15, height: 1.5, color: AppColors.text),
          decoration: const InputDecoration(hintText: ''),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Save')),
      ],
    );
  }
}
