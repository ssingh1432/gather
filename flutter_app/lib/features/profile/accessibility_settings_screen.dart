import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility/accessibility_settings.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/responsive.dart';

/// Accessibility & language preferences (Phase 14).
///
/// Every control here applies live: [GatherApp] listens to
/// [accessibilityProvider] and rebuilds theme, locale and text scaling.
class AccessibilitySettingsScreen extends ConsumerWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final prefs = ref.watch(accessibilityProvider);
    final notifier = ref.read(accessibilityProvider.notifier);
    final percent = (prefs.textScale * 100).round();

    return Scaffold(
      appBar: AppBar(title: Text(l.a11yTitle)),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _Header(l.a11yLanguage),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l.a11yLanguageSystem),
                    selected: prefs.localeCode == null,
                    onSelected: (_) => notifier.setLocale(null),
                  ),
                  for (final code in AppL10n.languageNames.keys)
                    ChoiceChip(
                      // Language names are rendered in their own script and
                      // flagged with their language so screen readers pronounce
                      // them correctly.
                      label: Text(AppL10n.languageNames[code]!, locale: Locale(code)),
                      selected: prefs.localeCode == code,
                      onSelected: (_) => notifier.setLocale(code),
                    ),
                ],
              ),
            ),
            _Header(l.a11yAppearance),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in <(ThemeMode, String)>[
                    (ThemeMode.system, l.a11yThemeSystem),
                    (ThemeMode.light, l.a11yThemeLight),
                    (ThemeMode.dark, l.a11yThemeDark),
                  ])
                    ChoiceChip(
                      label: Text(entry.$2),
                      selected: prefs.themeMode == entry.$1,
                      onSelected: (_) => notifier.setThemeMode(entry.$1),
                    ),
                ],
              ),
            ),
            _Header(l.a11yTextSize),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Text(l.a11yTextSizeHint, style: Theme.of(context).textTheme.bodySmall),
            ),
            Semantics(
              container: true,
              label: l.a11yTextSize,
              child: Slider(
                value: prefs.textScale,
                min: AccessibilityPrefs.minTextScale,
                max: AccessibilityPrefs.maxTextScale,
                divisions: 23,
                label: '$percent%',
                semanticFormatterCallback: (v) => l.a11yTextSizeValue((v * 100).round()),
                onChanged: notifier.setTextScale,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.a11yPreviewTitle, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(l.a11yPreviewBody),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              secondary: const Icon(Icons.contrast),
              title: Text(l.a11yHighContrast),
              subtitle: Text(l.a11yHighContrastSub),
              value: prefs.highContrast,
              onChanged: notifier.setHighContrast,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.format_bold),
              title: Text(l.a11yBoldText),
              subtitle: Text(l.a11yBoldTextSub),
              value: prefs.boldText,
              onChanged: notifier.setBoldText,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.animation),
              title: Text(l.a11yReduceMotion),
              subtitle: Text(l.a11yReduceMotionSub),
              value: prefs.reduceMotion,
              onChanged: notifier.setReduceMotion,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: Text(l.a11yReset),
                  onPressed: prefs.isDefault
                      ? null
                      : () {
                          notifier.reset();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.a11yResetDone)));
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
      );
}
