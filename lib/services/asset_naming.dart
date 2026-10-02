const List<String> _imageExts = ['png', 'jpg', 'jpeg', 'webp', 'gif'];

/// Extracts image URLs from message/markdown text (png/jpg/jpeg/webp/gif).
/// Excludes `)` so markdown `![image](url)` links are captured cleanly.
final RegExp assetUrlRe = RegExp(
  r'https?://[^\s\)]+?\.(?:png|jpg|jpeg|webp|gif)(?:\?[^\s\)]*)?',
  caseSensitive: false,
);

List<String> extractAssetUrls(String text) =>
    assetUrlRe.allMatches(text).map((m) => m.group(0)!).toSet().toList();

class AssetNaming {
  /// Extension for an image URL, defaulting to 'png' when unknown.
  static String extensionOf(String url) {
    final uri = Uri.tryParse(url);
    final last = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';
    if (last.contains('.')) {
      final ext = last.split('.').last.split(RegExp(r'[^a-zA-Z0-9]')).first.toLowerCase();
      if (_imageExts.contains(ext)) return ext;
    }
    final lower = url.toLowerCase();
    for (final ext in _imageExts) {
      if (lower.contains('.$ext')) return ext == 'jpeg' ? 'jpg' : ext;
    }
    return 'png';
  }

  /// Timestamped gallery filename: ai_image_<millis>.<ext>
  static String galleryFileName(String url) =>
      'ai_image_${DateTime.now().millisecondsSinceEpoch}.${extensionOf(url)}';
}
