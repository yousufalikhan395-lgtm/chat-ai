import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'asset_naming.dart';

class ImageDownloadService {
  static bool _busy = false;

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
      await Gal.putImageBytes(res.bodyBytes, name: AssetNaming.galleryFileName(url));
      messenger.showSnackBar(const SnackBar(content: Text('Image saved to gallery')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      _busy = false;
    }
  }
}
