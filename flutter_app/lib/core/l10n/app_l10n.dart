// GENERATED-BY-HAND NOTE: keep `en` and `ne` in sync (enforced by
// test/core/app_l10n_test.dart). Strings use {placeholders} filled by [AppL10n.t].
//
// This is intentionally a lightweight, dependency-free localization layer so
// the app can be translated incrementally: any key missing in a locale falls
// back to English, and any unknown key returns the key itself (never throws).
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';

class AppL10n {
  const AppL10n(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('ne')];

  /// Display names shown in the language picker, each in its own script.
  static const Map<String, String> languageNames = <String, String>{
    'en': 'English',
    'ne': 'नेपाली',
  };

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  static AppL10n of(BuildContext context) =>
      Localizations.of<AppL10n>(context, AppL10n) ?? const AppL10n(Locale('en'));

  static bool isSupportedCode(String? code) => code != null && languageNames.containsKey(code);

  /// Looks up [key] for this locale, substituting `{name}` placeholders.
  String t(String key, [Map<String, Object?> args = const <String, Object?>{}]) {
    var value = strings[locale.languageCode]?[key] ?? strings['en']![key] ?? key;
    args.forEach((name, v) {
      value = value.replaceAll('{$name}', '$v');
    });
    return value;
  }

  String get commonSave => t('common_save');
  String get commonCancel => t('common_cancel');
  String get commonOk => t('common_ok');
  String get commonRetry => t('common_retry');
  String get commonClose => t('common_close');
  String get commonLoading => t('common_loading');
  String get commonError => t('common_error');
  String get navHome => t('nav_home');
  String get navCommunities => t('nav_communities');
  String get navCreatePost => t('nav_create_post');
  String get navSearch => t('nav_search');
  String get navProfile => t('nav_profile');
  String get postLike => t('post_like');
  String get postUnlike => t('post_unlike');
  String get postComment => t('post_comment');
  String get postShare => t('post_share');
  String get postSave => t('post_save');
  String get postUnsave => t('post_unsave');
  String get postMore => t('post_more');
  String get postReplies => t('post_replies');
  String get postDownloads => t('post_downloads');
  String postViewProfile(Object name) => t('post_view_profile', <String, Object?>{'name': name});
  String get postSensitiveHidden => t('post_sensitive_hidden');
  String postLikesCount(Object n) => t('post_likes_count', <String, Object?>{'n': n});
  String postCommentsCount(Object n) => t('post_comments_count', <String, Object?>{'n': n});
  String postRepliesCount(Object n) => t('post_replies_count', <String, Object?>{'n': n});
  String postSharesCount(Object n) => t('post_shares_count', <String, Object?>{'n': n});
  String postDownloadsCount(Object n) => t('post_downloads_count', <String, Object?>{'n': n});
  String get postShowLikers => t('post_show_likers');
  String get postShowSharers => t('post_show_sharers');
  String get postShowDownloaders => t('post_show_downloaders');
  String pollVotesPct(Object pct, Object text, Object votes) => t('poll_votes_pct', <String, Object?>{'pct': pct, 'text': text, 'votes': votes});
  String get audioPlay => t('audio_play');
  String get audioPause => t('audio_pause');
  String get settingsTitle => t('settings_title');
  String get settingsAccessibility => t('settings_accessibility');
  String get settingsAccessibilitySub => t('settings_accessibility_sub');
  String get a11yTitle => t('a11y_title');
  String get a11yLanguage => t('a11y_language');
  String get a11yLanguageSystem => t('a11y_language_system');
  String get a11yAppearance => t('a11y_appearance');
  String get a11yThemeSystem => t('a11y_theme_system');
  String get a11yThemeLight => t('a11y_theme_light');
  String get a11yThemeDark => t('a11y_theme_dark');
  String get a11yTextSize => t('a11y_text_size');
  String get a11yTextSizeHint => t('a11y_text_size_hint');
  String a11yTextSizeValue(Object n) => t('a11y_text_size_value', <String, Object?>{'n': n});
  String get a11yPreviewTitle => t('a11y_preview_title');
  String get a11yPreviewBody => t('a11y_preview_body');
  String get a11yHighContrast => t('a11y_high_contrast');
  String get a11yHighContrastSub => t('a11y_high_contrast_sub');
  String get a11yBoldText => t('a11y_bold_text');
  String get a11yBoldTextSub => t('a11y_bold_text_sub');
  String get a11yReduceMotion => t('a11y_reduce_motion');
  String get a11yReduceMotionSub => t('a11y_reduce_motion_sub');
  String get a11yReset => t('a11y_reset');
  String get a11yResetDone => t('a11y_reset_done');

  /// Translation tables. Public so tests can verify en/ne parity.
  static const Map<String, Map<String, String>> strings = <String, Map<String, String>>{
    'en': <String, String>{
      'common_save': 'Save',
      'common_cancel': 'Cancel',
      'common_ok': 'OK',
      'common_retry': 'Retry',
      'common_close': 'Close',
      'common_loading': 'Loading…',
      'common_error': 'Something went wrong. Please try again.',
      'nav_home': 'Home',
      'nav_communities': 'Communities',
      'nav_create_post': 'Create Post',
      'nav_search': 'Search',
      'nav_profile': 'Profile',
      'post_like': 'Like',
      'post_unlike': 'Unlike',
      'post_comment': 'Comment',
      'post_share': 'Share',
      'post_save': 'Save',
      'post_unsave': 'Remove from saved',
      'post_more': 'More options',
      'post_replies': 'Replies',
      'post_downloads': 'Downloads',
      'post_view_profile': 'View {name}\'s profile',
      'post_sensitive_hidden': 'Sensitive content is hidden. Double tap to reveal.',
      'post_likes_count': '{n} likes',
      'post_comments_count': '{n} comments',
      'post_replies_count': '{n} replies',
      'post_shares_count': '{n} shares',
      'post_downloads_count': '{n} downloads',
      'post_show_likers': 'Show who liked',
      'post_show_sharers': 'Show who shared',
      'post_show_downloaders': 'Show who downloaded',
      'poll_votes_pct': '{text}, {votes} votes, {pct} percent',
      'audio_play': 'Play audio',
      'audio_pause': 'Pause audio',
      'settings_title': 'Settings',
      'settings_accessibility': 'Accessibility & language',
      'settings_accessibility_sub': 'Text size, contrast, motion and language',
      'a11y_title': 'Accessibility & language',
      'a11y_language': 'Language',
      'a11y_language_system': 'Device default',
      'a11y_appearance': 'Appearance',
      'a11y_theme_system': 'Match device',
      'a11y_theme_light': 'Light',
      'a11y_theme_dark': 'Dark',
      'a11y_text_size': 'Text size',
      'a11y_text_size_hint': 'Make text larger or smaller across the whole app',
      'a11y_text_size_value': '{n} percent',
      'a11y_preview_title': 'Preview',
      'a11y_preview_body': 'This is how text will look across Gather.',
      'a11y_high_contrast': 'High contrast',
      'a11y_high_contrast_sub': 'Stronger colors and borders for easier reading',
      'a11y_bold_text': 'Bold text',
      'a11y_bold_text_sub': 'Show all text in a heavier weight',
      'a11y_reduce_motion': 'Reduce motion',
      'a11y_reduce_motion_sub': 'Fewer animations and screen transitions',
      'a11y_reset': 'Reset to defaults',
      'a11y_reset_done': 'Accessibility settings were reset.',
    },
    'ne': <String, String>{
      'common_save': 'सुरक्षित गर्नुहोस्',
      'common_cancel': 'रद्द गर्नुहोस्',
      'common_ok': 'ठिक छ',
      'common_retry': 'फेरि प्रयास गर्नुहोस्',
      'common_close': 'बन्द गर्नुहोस्',
      'common_loading': 'लोड हुँदैछ…',
      'common_error': 'केही गडबड भयो। कृपया फेरि प्रयास गर्नुहोस्।',
      'nav_home': 'गृहपृष्ठ',
      'nav_communities': 'समुदायहरू',
      'nav_create_post': 'पोस्ट लेख्नुहोस्',
      'nav_search': 'खोज',
      'nav_profile': 'प्रोफाइल',
      'post_like': 'मन पराउनुहोस्',
      'post_unlike': 'मन पराएको हटाउनुहोस्',
      'post_comment': 'टिप्पणी गर्नुहोस्',
      'post_share': 'सेयर गर्नुहोस्',
      'post_save': 'सुरक्षित राख्नुहोस्',
      'post_unsave': 'सुरक्षित गरेको हटाउनुहोस्',
      'post_more': 'थप विकल्पहरू',
      'post_replies': 'जवाफहरू',
      'post_downloads': 'डाउनलोडहरू',
      'post_view_profile': '{name} को प्रोफाइल हेर्नुहोस्',
      'post_sensitive_hidden': 'संवेदनशील सामग्री लुकाइएको छ। हेर्न दुई पटक ट्याप गर्नुहोस्।',
      'post_likes_count': '{n} जनाले मन पराए',
      'post_comments_count': '{n} टिप्पणी',
      'post_replies_count': '{n} जवाफ',
      'post_shares_count': '{n} पटक सेयर',
      'post_downloads_count': '{n} पटक डाउनलोड',
      'post_show_likers': 'कसले मन पराए हेर्नुहोस्',
      'post_show_sharers': 'कसले सेयर गरे हेर्नुहोस्',
      'post_show_downloaders': 'कसले डाउनलोड गरे हेर्नुहोस्',
      'poll_votes_pct': '{text}, {votes} मत, {pct} प्रतिशत',
      'audio_play': 'अडियो चलाउनुहोस्',
      'audio_pause': 'अडियो रोक्नुहोस्',
      'settings_title': 'सेटिङ',
      'settings_accessibility': 'पहुँच र भाषा',
      'settings_accessibility_sub': 'अक्षरको आकार, कन्ट्रास्ट, गति र भाषा',
      'a11y_title': 'पहुँच र भाषा',
      'a11y_language': 'भाषा',
      'a11y_language_system': 'यन्त्रकै भाषा',
      'a11y_appearance': 'स्वरूप',
      'a11y_theme_system': 'यन्त्र अनुसार',
      'a11y_theme_light': 'उज्यालो',
      'a11y_theme_dark': 'अँध्यारो',
      'a11y_text_size': 'अक्षरको आकार',
      'a11y_text_size_hint': 'एपभरि अक्षर ठूला वा साना बनाउनुहोस्',
      'a11y_text_size_value': '{n} प्रतिशत',
      'a11y_preview_title': 'पूर्वावलोकन',
      'a11y_preview_body': 'Gather मा अक्षरहरू यसरी देखिनेछन्।',
      'a11y_high_contrast': 'उच्च कन्ट्रास्ट',
      'a11y_high_contrast_sub': 'पढ्न सजिलोको लागि गाढा रङ र किनाराहरू',
      'a11y_bold_text': 'बाक्लो अक्षर',
      'a11y_bold_text_sub': 'सबै पाठ बाक्लो देखाउँछ',
      'a11y_reduce_motion': 'गति घटाउनुहोस्',
      'a11y_reduce_motion_sub': 'कम एनिमेसन र स्क्रिन ट्रान्जिसन',
      'a11y_reset': 'पूर्वनिर्धारितमा फर्काउनुहोस्',
      'a11y_reset_done': 'पहुँच सेटिङ पूर्वनिर्धारितमा फर्काइयो।',
    },
  };
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  bool isSupported(Locale locale) => AppL10n.isSupportedCode(locale.languageCode);

  @override
  Future<AppL10n> load(Locale locale) => SynchronousFuture<AppL10n>(AppL10n(locale));

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}
