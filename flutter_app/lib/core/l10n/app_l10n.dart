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
  String get setPrivacy => t('set_privacy');
  String get setPrivateAccount => t('set_private_account');
  String get setPrivateAccountSub => t('set_private_account_sub');
  String get setWhoPosts => t('set_who_posts');
  String get setWhoFriends => t('set_who_friends');
  String get setWhoMessage => t('set_who_message');
  String get setWhoMention => t('set_who_mention');
  String get setActivityStatus => t('set_activity_status');
  String get setActivityStatusSub => t('set_activity_status_sub');
  String get setReadReceipts => t('set_read_receipts');
  String get setReadReceiptsSub => t('set_read_receipts_sub');
  String get setWhoSearch => t('set_who_search');
  String get setLastSeen => t('set_last_seen');
  String get setLastSeenSub => t('set_last_seen_sub');
  String get setScheduledPosts => t('set_scheduled_posts');
  String get setBlocked => t('set_blocked');
  String get setMuted => t('set_muted');
  String get setRestricted => t('set_restricted');
  String get setSafeSearch => t('set_safe_search');
  String get setSafeSearchSub => t('set_safe_search_sub');
  String get setChildSafety => t('set_child_safety');
  String get setChildSafetySub => t('set_child_safety_sub');
  String get setDataPrivacyHeader => t('set_data_privacy_header');
  String get setDataConsent => t('set_data_consent');
  String get setDataConsentSub => t('set_data_consent_sub');
  String get setGrievances => t('set_grievances');
  String get setGrievancesSub => t('set_grievances_sub');
  String get setModerationHistory => t('set_moderation_history');
  String get setModerationHistorySub => t('set_moderation_history_sub');
  String get setHelp => t('set_help');
  String get setLegal => t('set_legal');
  String get setPrivacyPolicy => t('set_privacy_policy');
  String get setTerms => t('set_terms');
  String get setGuidelines => t('set_guidelines');
  String get setCookie => t('set_cookie');
  String get setCopyright => t('set_copyright');
  String get setLawEnforcement => t('set_law_enforcement');
  String get setNotifications => t('set_notifications');
  String get setNotifLikes => t('set_notif_likes');
  String get setNotifComments => t('set_notif_comments');
  String get setNotifFriendRequests => t('set_notif_friend_requests');
  String get setNotifMentions => t('set_notif_mentions');
  String get setNotifMessages => t('set_notif_messages');
  String get setNotifCommunity => t('set_notif_community');
  String get setNotifModeration => t('set_notif_moderation');
  String get setNotifModerationSub => t('set_notif_moderation_sub');
  String get setNotifAnnouncements => t('set_notif_announcements');
  String get setNotifAnnouncementsSub => t('set_notif_announcements_sub');
  String get setNotifSecurity => t('set_notif_security');
  String get setNotifSecuritySub => t('set_notif_security_sub');
  String get setAccount => t('set_account');
  String get setChangeUsername => t('set_change_username');
  String get setGetVerified => t('set_get_verified');
  String get setSecurityDevices => t('set_security_devices');
  String get setSecurityDevicesSub => t('set_security_devices_sub');
  String get setChangePassword => t('set_change_password');
  String get setVerifyPhone => t('set_verify_phone');
  String get setDeactivate => t('set_deactivate');
  String get setDeactivateQ => t('set_deactivate_q');
  String get setDeactivateBtn => t('set_deactivate_btn');
  String get authLogin => t('auth_login');
  String get authContinueGoogle => t('auth_continue_google');
  String get authOr => t('auth_or');
  String get authEmail => t('auth_email');
  String get authPassword => t('auth_password');
  String get authRemember => t('auth_remember');
  String get authForgot => t('auth_forgot');
  String get authNoAccount => t('auth_no_account');
  String get authRequired => t('auth_required');
  String get authRequiredSignup => t('auth_required_signup');
  String get authPhoneInvalid => t('auth_phone_invalid');
  String get authPwMismatch => t('auth_pw_mismatch');
  String get authAgreeTerms => t('auth_agree_terms');
  String get authWelcome => t('auth_welcome');
  String get authCreateAccount => t('auth_create_account');
  String get authUsername => t('auth_username');
  String get authMobileOptional => t('auth_mobile_optional');
  String get authPwHelper => t('auth_pw_helper');
  String get authConfirmPw => t('auth_confirm_pw');
  String get authHaveAccount => t('auth_have_account');
  String get authEnterEmail => t('auth_enter_email');
  String get authResetTitle => t('auth_reset_title');
  String get authResetSent => t('auth_reset_sent');
  String get authBackLogin => t('auth_back_login');
  String get authResetPrompt => t('auth_reset_prompt');
  String get authSendReset => t('auth_send_reset');
  String get setDeactivateBody => t('set_deactivate_body');

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
      'set_privacy': 'Privacy',
      'set_private_account': 'Private account',
      'set_private_account_sub': 'Only approved followers can see your posts',
      'set_who_posts': 'Who can see your posts by default',
      'set_who_friends': 'Who can see your friends list',
      'set_who_message': 'Who can message you',
      'set_who_mention': 'Who can @mention or tag you',
      'set_activity_status': 'Show activity status',
      'set_activity_status_sub': 'Let friends see when you’re active on Gather',
      'set_read_receipts': 'Read receipts',
      'set_read_receipts_sub': 'Let others see when you’ve read their messages',
      'set_who_search': 'Who can find you in search',
      'set_last_seen': 'Show last seen',
      'set_last_seen_sub': 'Let friends see when you were last active',
      'set_scheduled_posts': 'Scheduled posts',
      'set_blocked': 'Blocked accounts',
      'set_muted': 'Muted accounts',
      'set_restricted': 'Restricted accounts',
      'set_safe_search': 'Safe search',
      'set_safe_search_sub': 'Hide posts marked as sensitive content from your feed',
      'set_child_safety': 'Child safety mode',
      'set_child_safety_sub': 'Locks safe search on and limits messages to friends only',
      'set_data_privacy_header': 'Data & Privacy',
      'set_data_consent': 'Data, consent & account deletion',
      'set_data_consent_sub': 'Download your data, review consent history, or delete your account',
      'set_grievances': 'Grievances & legal requests',
      'set_grievances_sub': 'File or track a complaint, illegal content report, or appeal',
      'set_moderation_history': 'Moderation history',
      'set_moderation_history_sub': 'Warnings, strikes, suspensions or bans on your account — and appeals',
      'set_help': 'Help & Feedback',
      'set_legal': 'Legal & Policies',
      'set_privacy_policy': 'Privacy Policy',
      'set_terms': 'Terms of Service',
      'set_guidelines': 'Community Guidelines',
      'set_cookie': 'Cookie Policy',
      'set_copyright': 'Copyright & IP Policy',
      'set_law_enforcement': 'Law Enforcement Requests',
      'set_notifications': 'Notifications',
      'set_notif_likes': 'Likes',
      'set_notif_comments': 'Comments',
      'set_notif_friend_requests': 'Friend requests',
      'set_notif_mentions': 'Mentions',
      'set_notif_messages': 'Messages',
      'set_notif_community': 'Community activity',
      'set_notif_moderation': 'Moderation & appeal updates',
      'set_notif_moderation_sub': 'Reports you filed, appeals you filed, and actions on your account',
      'set_notif_announcements': 'Announcements',
      'set_notif_announcements_sub': 'Broadcasts sent by Gather admins',
      'set_notif_security': 'Security & login alerts',
      'set_notif_security_sub': 'Always on to keep your account safe — can’t be turned off',
      'set_account': 'Account',
      'set_change_username': 'Change username',
      'set_get_verified': 'Get verified',
      'set_security_devices': 'Security & devices',
      'set_security_devices_sub': 'Two-factor authentication, signed-in devices',
      'set_change_password': 'Change password',
      'set_verify_phone': 'Verify phone number',
      'set_deactivate': 'Deactivate account',
      'set_deactivate_q': 'Deactivate account?',
      'set_deactivate_btn': 'Deactivate',
      'auth_login': 'Login',
      'auth_continue_google': 'Continue with Google',
      'auth_or': 'or',
      'auth_email': 'Email',
      'auth_password': 'Password',
      'auth_remember': 'Remember me',
      'auth_forgot': 'Forgot password?',
      'auth_no_account': 'Don\'t have an account? Sign up',
      'auth_required': 'Email and password are required.',
      'auth_required_signup': 'Username, email, and password are required.',
      'auth_phone_invalid': 'Enter a valid 10-digit mobile number (e.g. 98XXXXXXXX), or leave it blank.',
      'auth_pw_mismatch': 'Passwords do not match.',
      'auth_agree_terms': 'Please agree to the Privacy Policy and Terms of Service to continue.',
      'auth_welcome': 'Welcome to Gather!',
      'auth_create_account': 'Create account',
      'auth_username': 'Username',
      'auth_mobile_optional': 'Mobile number (optional)',
      'auth_pw_helper': 'At least 8 characters, with upper, lower case and a number',
      'auth_confirm_pw': 'Confirm password',
      'auth_have_account': 'Already have an account? Log in',
      'auth_enter_email': 'Enter your email address.',
      'auth_reset_title': 'Reset password',
      'auth_reset_sent': 'If an account exists for that email, a reset link is on its way.',
      'auth_back_login': 'Back to login',
      'auth_reset_prompt': 'Enter your account email and we will send you a reset link.',
      'auth_send_reset': 'Send reset link',
      'set_deactivate_body': 'Your profile and posts will be hidden from other people on Gather. Contact support to reactivate. This won\'t delete your data.',
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
      'set_privacy': 'गोपनीयता',
      'set_private_account': 'निजी खाता',
      'set_private_account_sub': 'स्वीकृत फलोअरहरूले मात्र तपाईंका पोस्ट हेर्न सक्छन्',
      'set_who_posts': 'तपाईंका पोस्ट पूर्वनिर्धारित रूपमा कसले हेर्न सक्छ',
      'set_who_friends': 'तपाईंको साथीहरूको सूची कसले हेर्न सक्छ',
      'set_who_message': 'तपाईंलाई कसले सन्देश पठाउन सक्छ',
      'set_who_mention': 'तपाईंलाई कसले @उल्लेख वा ट्याग गर्न सक्छ',
      'set_activity_status': 'सक्रियता स्थिति देखाउनुहोस्',
      'set_activity_status_sub': 'साथीहरूले तपाईं Gather मा कहिले सक्रिय हुनुहुन्छ हेर्न सक्छन्',
      'set_read_receipts': 'पढेको जनाउ',
      'set_read_receipts_sub': 'अरूले तपाईंले सन्देश कहिले पढ्नुभयो भनी हेर्न सक्छन्',
      'set_who_search': 'खोजीमा तपाईंलाई कसले भेट्टाउन सक्छ',
      'set_last_seen': 'अन्तिम पटक देखिएको देखाउनुहोस्',
      'set_last_seen_sub': 'साथीहरूले तपाईं अन्तिम पटक कहिले सक्रिय हुनुहुन्थ्यो हेर्न सक्छन्',
      'set_scheduled_posts': 'तालिकाबद्ध पोस्टहरू',
      'set_blocked': 'ब्लक गरिएका खाताहरू',
      'set_muted': 'म्यूट गरिएका खाताहरू',
      'set_restricted': 'सीमित गरिएका खाताहरू',
      'set_safe_search': 'सुरक्षित खोज',
      'set_safe_search_sub': 'संवेदनशील भनी चिनो लगाइएका पोस्टहरू फिडबाट लुकाउनुहोस्',
      'set_child_safety': 'बाल सुरक्षा मोड',
      'set_child_safety_sub': 'सुरक्षित खोज खुला राख्छ र सन्देश साथीहरूमा मात्र सीमित गर्छ',
      'set_data_privacy_header': 'डाटा र गोपनीयता',
      'set_data_consent': 'डाटा, सहमति र खाता मेटाउने',
      'set_data_consent_sub': 'आफ्नो डाटा डाउनलोड गर्नुहोस्, सहमतिको इतिहास हेर्नुहोस्, वा खाता मेटाउनुहोस्',
      'set_grievances': 'उजुरी र कानुनी अनुरोधहरू',
      'set_grievances_sub': 'उजुरी, गैरकानुनी सामग्रीको रिपोर्ट वा पुनरावेदन दर्ता वा ट्र्याक गर्नुहोस्',
      'set_moderation_history': 'मोडरेसन इतिहास',
      'set_moderation_history_sub': 'तपाईंको खातामा चेतावनी, स्ट्राइक, निलम्बन वा प्रतिबन्ध — र पुनरावेदनहरू',
      'set_help': 'सहायता र प्रतिक्रिया',
      'set_legal': 'कानुनी र नीतिहरू',
      'set_privacy_policy': 'गोपनीयता नीति',
      'set_terms': 'सेवाका सर्तहरू',
      'set_guidelines': 'समुदाय दिशानिर्देश',
      'set_cookie': 'कुकी नीति',
      'set_copyright': 'प्रतिलिपि अधिकार र बौद्धिक सम्पत्ति नीति',
      'set_law_enforcement': 'कानून कार्यान्वयन निकायका अनुरोधहरू',
      'set_notifications': 'सूचनाहरू',
      'set_notif_likes': 'मन पराएको',
      'set_notif_comments': 'टिप्पणीहरू',
      'set_notif_friend_requests': 'साथी अनुरोधहरू',
      'set_notif_mentions': 'उल्लेखहरू',
      'set_notif_messages': 'सन्देशहरू',
      'set_notif_community': 'समुदायका गतिविधि',
      'set_notif_moderation': 'मोडरेसन र पुनरावेदन अपडेटहरू',
      'set_notif_moderation_sub': 'तपाईंले दर्ता गरेका रिपोर्ट, पुनरावेदन र तपाईंको खातामाथिका कारबाही',
      'set_notif_announcements': 'घोषणाहरू',
      'set_notif_announcements_sub': 'Gather प्रशासकहरूले पठाएका सन्देशहरू',
      'set_notif_security': 'सुरक्षा र लगइन अलर्टहरू',
      'set_notif_security_sub': 'खाता सुरक्षित राख्न सधैं सक्रिय — बन्द गर्न मिल्दैन',
      'set_account': 'खाता',
      'set_change_username': 'प्रयोगकर्ता नाम परिवर्तन',
      'set_get_verified': 'प्रमाणित हुनुहोस्',
      'set_security_devices': 'सुरक्षा र यन्त्रहरू',
      'set_security_devices_sub': 'दुई-चरणीय प्रमाणीकरण, लगइन भएका यन्त्रहरू',
      'set_change_password': 'पासवर्ड परिवर्तन',
      'set_verify_phone': 'फोन नम्बर प्रमाणित गर्नुहोस्',
      'set_deactivate': 'खाता निष्क्रिय गर्नुहोस्',
      'set_deactivate_q': 'खाता निष्क्रिय गर्ने?',
      'set_deactivate_btn': 'निष्क्रिय गर्नुहोस्',
      'auth_login': 'लगइन',
      'auth_continue_google': 'Google सँग जारी राख्नुहोस्',
      'auth_or': 'वा',
      'auth_email': 'इमेल',
      'auth_password': 'पासवर्ड',
      'auth_remember': 'मलाई सम्झनुहोस्',
      'auth_forgot': 'पासवर्ड बिर्सनुभयो?',
      'auth_no_account': 'खाता छैन? साइन अप गर्नुहोस्',
      'auth_required': 'इमेल र पासवर्ड आवश्यक छ।',
      'auth_required_signup': 'प्रयोगकर्ता नाम, इमेल र पासवर्ड आवश्यक छ।',
      'auth_phone_invalid': 'मान्य १०-अङ्कको मोबाइल नम्बर (जस्तै 98XXXXXXXX) राख्नुहोस्, वा खाली छोड्नुहोस्।',
      'auth_pw_mismatch': 'पासवर्डहरू मेल खाएनन्।',
      'auth_agree_terms': 'जारी राख्न कृपया गोपनीयता नीति र सेवाका सर्तहरूमा सहमत हुनुहोस्।',
      'auth_welcome': 'Gather मा स्वागत छ!',
      'auth_create_account': 'खाता बनाउनुहोस्',
      'auth_username': 'प्रयोगकर्ता नाम',
      'auth_mobile_optional': 'मोबाइल नम्बर (ऐच्छिक)',
      'auth_pw_helper': 'कम्तीमा ८ अक्षर, ठूलो र सानो अक्षर तथा एउटा अङ्क सहित',
      'auth_confirm_pw': 'पासवर्ड पुष्टि गर्नुहोस्',
      'auth_have_account': 'पहिले नै खाता छ? लगइन गर्नुहोस्',
      'auth_enter_email': 'आफ्नो इमेल ठेगाना राख्नुहोस्।',
      'auth_reset_title': 'पासवर्ड रिसेट',
      'auth_reset_sent': 'यो इमेलसँग खाता भएमा रिसेट लिङ्क पठाइँदै छ।',
      'auth_back_login': 'लगइनमा फर्कनुहोस्',
      'auth_reset_prompt': 'आफ्नो खाताको इमेल राख्नुहोस्, हामी रिसेट लिङ्क पठाउँछौं।',
      'auth_send_reset': 'रिसेट लिङ्क पठाउनुहोस्',
      'set_deactivate_body': 'तपाईंको प्रोफाइल र पोस्टहरू Gather मा अरूबाट लुकाइनेछन्। पुनः सक्रिय गर्न सहायतामा सम्पर्क गर्नुहोस्। यसले तपाईंको डाटा मेटाउँदैन।',
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
