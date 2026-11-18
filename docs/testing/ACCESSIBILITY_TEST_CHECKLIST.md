# Accessibility Test Checklist (Phase 14)

Automated: `test/core/accessibility_settings_test.dart`, `accessible_theme_test.dart`, `app_l10n_test.dart`.
Manual, per release, on Android (TalkBack), iOS (VoiceOver) and Web (NVDA/Chrome):
- [ ] Every icon-only button has a label; images that carry meaning have alt text
- [ ] Reading order matches visual order on Home, Post detail, Profile, Settings, Admin
- [ ] Text scale 200%: no overflow or clipped actions
- [ ] High contrast mode: ≥ 4.5:1 for text, ≥ 3:1 for controls; state not conveyed by colour alone (errors, likes, online status)
- [ ] Keyboard (Web/desktop): Tab order, visible focus, Esc closes dialogs, Enter submits
- [ ] Touch targets ≥ 48 dp
- [ ] Reduced motion respected; video does not autoplay with sound
- [ ] Nepali (ne) strings present on every screen, no mixed-language leftovers, Devanagari renders with proper font and line height
- [ ] Dark mode: contrast and focus indicators verified
- [ ] Forms announce validation errors; password rules readable by screen reader
