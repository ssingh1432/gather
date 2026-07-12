import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a profile's website link in an external browser/app. Adds
/// `https://` if the person saved it without a scheme, and shows a
/// SnackBar instead of throwing if nothing can handle the link.
Future<void> openExternalLink(BuildContext context, String url) async {
  final normalized = url.startsWith('http://') || url.startsWith('https://') ? url : 'https://$url';
  final uri = Uri.tryParse(normalized);
  final launched = uri != null && await canLaunchUrl(uri) && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this link.')));
  }
}
