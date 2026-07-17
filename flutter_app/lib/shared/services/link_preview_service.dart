import 'dart:convert';

import '../../core/supabase_client.dart';

class LinkPreview {
  const LinkPreview({required this.url, this.title, this.description, this.imageUrl, this.siteName});
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
        url: json['url'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        siteName: json['site_name'] as String?,
      );
}

/// The first http(s) URL in a block of text, if any — used to decide
/// whether to offer a link preview while composing.
final _urlPattern = RegExp(r'https?://[^\s]+');

String? firstUrlIn(String text) => _urlPattern.firstMatch(text)?.group(0);

class LinkPreviewService {
  Future<LinkPreview?> fetch(String url) async {
    try {
      final res = await SupabaseConfig.client.functions.invoke('link-preview', body: {'url': url});
      final data = res.data;
      if (data is Map<String, dynamic>) return LinkPreview.fromJson(data);
      if (data is String) return LinkPreview.fromJson(jsonDecode(data) as Map<String, dynamic>);
      return null;
    } catch (_) {
      return null;
    }
  }
}
