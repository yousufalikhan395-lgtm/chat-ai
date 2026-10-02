import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/asset_store.dart';
import '../services/image_download_service.dart';
import '../theme.dart';

class GalleryScreen extends StatefulWidget {
  final AssetStore store;
  const GalleryScreen({super.key, required this.store});
  @override State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<AssetItem> _items = [];
  bool _loading = true;

  @override void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.store.all();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  ImageProvider _imageFor(AssetItem item) {
    final local = item.localPath;
    if (local != null && File(local).existsSync()) {
      return FileImage(File(local));
    }
    return NetworkImage(item.url);
  }

  Future<void> _openViewer(AssetItem item) async {
    final removed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _AssetViewer(store: widget.store, item: item)),
    );
    if (removed == true) _load();
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove all images?'),
        content: const Text('Deletes the saved index and local copies. Images already downloaded to your gallery are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove all')),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Text.rich(TextSpan(
          text: _loading ? 'My images' : 'My images (${_items.length})',
          style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              letterSpacing: -0.3,
              fontWeight: FontWeight.w600,
              color: AppColors.text),
          children: const [TextSpan(text: '.', style: TextStyle(color: AppColors.accent, fontSize: 21))],
        )),
        actions: [
          if (!_loading && _items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Remove all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('YOUR COLLECTION', style: eyebrowStyle(context)),
                    const SizedBox(height: 8),
                    const Text('No generated images yet',
                        style: TextStyle(fontFamily: 'Inter', color: AppColors.muted)),
                    const SizedBox(height: 6),
                    const Text('Images you create in chat will live here.',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.muted)),
                  ]),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    return GestureDetector(
                      onTap: () => _openViewer(item),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Image(
                          image: _imageFor(item),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.surface2,
                            child: const Icon(Icons.broken_image, color: AppColors.muted),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AssetViewer extends StatefulWidget {
  final AssetStore store;
  final AssetItem item;
  const _AssetViewer({required this.store, required this.item});
  @override
  State<_AssetViewer> createState() => _AssetViewerState();
}

class _AssetViewerState extends State<_AssetViewer> {
  ImageProvider get _image {
    final local = widget.item.localPath;
    if (local != null && File(local).existsSync()) {
      return FileImage(File(local));
    }
    return NetworkImage(widget.item.url);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _remove() async {
    await widget.store.remove(widget.item.url);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            tooltip: 'Download to gallery',
            onPressed: () => ImageDownloadService.download(context, widget.item.url),
          ),
          IconButton(
            icon: const Icon(Icons.link, color: Colors.white),
            tooltip: 'Copy link',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.item.url));
              _toast('Link copied');
            },
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: 'Share',
            onPressed: () => SharePlus.instance
                .share(ShareParams(text: widget.item.url, title: 'Generated image')),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            tooltip: 'Remove from saved images',
            onPressed: _remove,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image(
            image: _image,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, p) =>
                p == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}
