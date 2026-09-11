import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

class ImageDownloadService {
  static bool _busy = false;

  static String _fileName(String url) {
    final uri = Uri.tryParse(url);
    final last = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';
    if (last.contains('.')) {
      final parts = last.split('.');
      final ext = parts.last.split(RegExp(r'[^a-zA-Z0-9]')).first.toLowerCase();
      if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
        return 'ai_image_${DateTime.now().millisecondsSinceEpoch}.$ext';
      }
    }
    final lower = url.toLowerCase();
    if (lower.contains('.png')) return 'ai_image_${DateTime.now().millisecondsSinceEpoch}.png';
    if (lower.contains('.jpg') || lower.contains('.jpeg')) {
      return 'ai_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    }
    if (lower.contains('.webp')) return 'ai_image_${DateTime.now().millisecondsSinceEpoch}.webp';
    if (lower.contains('.gif')) return 'ai_image_${DateTime.now().millisecondsSinceEpoch}.gif';
    return 'ai_image_${DateTime.now().millisecondsSinceEpoch}.png';
  }

  static Future<void> download(BuildContext context, String url) async {
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Downloading image...'), duration: Duration(seconds: 2)));
    try {
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          messenger.showSnackBar(const SnackBar(content: Text('Gallery access denied')));
          return;
        }
      }
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        throw Exception('HTTP ${res.statusCode}');
      }
      await Gal.putImageBytes(res.bodyBytes, name: _fileName(url));
      messenger.showSnackBar(const SnackBar(content: Text('Image saved to gallery')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      _busy = false;
    }
  }
}
