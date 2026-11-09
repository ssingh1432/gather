import 'package:flutter/material.dart';

/// Allowed profile themes. Keys must match the users_profile_theme_check
/// constraint in migration 123.
class ProfileThemes {
  ProfileThemes._();

  static const Map<String, Color> accents = {
    'default': Color(0xFF6C5CE7),
    'ocean': Color(0xFF0984E3),
    'forest': Color(0xFF00A86B),
    'sunset': Color(0xFFE17055),
    'rose': Color(0xFFE84393),
    'midnight': Color(0xFF2D3436),
  };

  static const Map<String, String> labels = {
    'default': 'Default',
    'ocean': 'Ocean',
    'forest': 'Forest',
    'sunset': 'Sunset',
    'rose': 'Rose',
    'midnight': 'Midnight',
  };

  /// Accent for [key], or null for the app default (keeps current look).
  static Color? accentFor(String? key) => (key == null || key == 'default') ? null : accents[key];
}
