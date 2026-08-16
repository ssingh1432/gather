import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/services/media/web_safe_pick.dart';
import '../../shared/widgets/profile_view.dart' show PickedImagePreview;
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'page_local_repository.dart';
import 'pages_theme.dart';

/// Page Settings — edit a page's core info after creation.
///
/// The settings screen is the owner/team control for the public Page identity.
/// Username remains read-only because changing it affects the Page URL/identity.
/// Social links are editable here as part of the same public-profile settings
/// surface so owners do not have to discover an unsupported field elsewhere.
class PageSettingsScreen extends StatefulWidget {
  const PageSettingsScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PageSettingsScreen> createState() => _PageSettingsScreenState();
}

class _PageSettingsScreenState extends State<PageSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = PageRepository();
  final _pageLocalRepo = PageLocalRepository();

  final name = TextEditingController();
  final username = TextEditingController();
  final description = TextEditingController();
  final website = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final location = TextEditingController();
  final country = TextEditingController();
  final businessHoursNote = TextEditingController();
  final facebook = TextEditingController();
  final instagram = TextEditingController();
  final x = TextEditingController();
  final youtube = TextEditingController();
  final tiktok = TextEditingController();

  String pageType = 'business';
  String language = 'en';
  String? categoryId;
  List<Map<String, dynamic>> categories = [];

  String? _logoUrl;
  String? _coverUrl;
  XFile? _logoPick;
  XFile? _coverPick;

  bool _loading = true;
  bool _saving = false;
  bool _canEdit = false;
  bool _isOwner = false;
  bool _isDeactivated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    description.dispose();
    website.dispose();
    phone.dispose();
    email.dispose();
    location.dispose();
    country.dispose();
    businessHoursNote.dispose();
    facebook.dispose();
    instagram.dispose();
    x.dispose();
    youtube.dispose();
    tiktok.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.getPage(widget.pageId),
        _repo.hasPagePermission(widget.pageId, 'manage_settings'),
        _repo.listCategories(),
        _pageLocalRepo.isPageOwner(widget.pageId),
      ]);
      final page = results[0] as Map<String, dynamic>?;
      final canEdit = results[1] as bool;
      final cats = results[2] as List<Map<String, dynamic>>;
      final isOwner = results[3] as bool;
      if (page == null) {
        if (mounted) {
          setState(() {
            _error = 'Page not found.';
            _loading = false;
          });
        }
        return;
      }
      final hours = page['business_hours'];
      final links = page['social_links'];
      final social = links is Map ? Map<String, dynamic>.from(links) : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        name.text = page['name'] as String? ?? '';
        username.text = page['username'] as String? ?? '';
        description.text = page['description'] as String? ?? '';
        website.text = page['website'] as String? ?? '';
        phone.text = page['phone'] as String? ?? '';
        email.text = page['email'] as String? ?? '';
        location.text = page['location'] as String? ?? '';
        country.text = page['country'] as String? ?? '';
        businessHoursNote.text = (hours is Map && hours['note'] is String) ? hours['note'] as String : '';
        facebook.text = social['facebook'] as String? ?? '';
        instagram.text = social['instagram'] as String? ?? '';
        x.text = social['x'] as String? ?? social['twitter'] as String? ?? '';
        youtube.text = social['youtube'] as String? ?? '';
        tiktok.text = social['tiktok'] as String? ?? '';
        pageType = page['page_type'] as String? ?? 'business';
        language = page['language'] as String? ?? 'en';
        categoryId = page['category_id'] as String?;
        _logoUrl = page['logo_url'] as String?;
        _coverUrl = page['cover_url'] as String?;
        categories = cats;
        _canEdit = canEdit;
        _isOwner = isOwner;
        _isDeactivated = page['deactivated_at'] != null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load settings. $e'; _loading = false; });
    }
  }

  Future<void> _pickImage({required bool cover}) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final safe = await materializeIfWeb(picked);
    setState(() {
      if (cover) {
        _coverPick = safe;
      } else {
        _logoPick = safe;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _saving = true; _error = null; });
    try {
      String? newLogoUrl;
      String? newCoverUrl;
      if (_logoPick != null) newLogoUrl = await _repo.uploadLogo(widget.pageId, _logoPick!);
      if (_coverPick != null) newCoverUrl = await _repo.uploadCover(widget.pageId, _coverPick!);

      final Map<String, dynamic> businessHours =
          businessHoursNote.text.trim().isEmpty
              ? <String, dynamic>{}
              : <String, dynamic>{'note': businessHoursNote.text.trim()};

      final socialLinks = <String, String>{
        if (facebook.text.trim().isNotEmpty) 'facebook': facebook.text.trim(),
        if (instagram.text.trim().isNotEmpty) 'instagram': instagram.text.trim(),
        if (x.text.trim().isNotEmpty) 'x': x.text.trim(),
        if (youtube.text.trim().isNotEmpty) 'youtube': youtube.text.trim(),
        if (tiktok.text.trim().isNotEmpty) 'tiktok': tiktok.text.trim(),
      };

      await _repo.updatePage(widget.pageId, {
        'name': name.text.trim(),
        'description': description.text.trim().isEmpty ? null : description.text.trim(),
        'category_id': categoryId,
        'page_type': pageType,
        'website': website.text.trim().isEmpty ? null : website.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'email': email.text.trim().isEmpty ? null : email.text.trim(),
        'location': location.text.trim().isEmpty ? null : location.text.trim(),
        'country': country.text.trim().isEmpty ? null : country.text.trim(),
        'business_hours': businessHours,
        'language': language,
        'social_links': socialLinks,
        if (newLogoUrl != null) 'logo_url': newLogoUrl,
        if (newCoverUrl != null) 'cover_url': newCoverUrl,
      });

      if (!mounted) return;
      setState(() {
        if (newLogoUrl != null) _logoUrl = newLogoUrl;
        if (newCoverUrl != null) _coverUrl = newCoverUrl;
        _logoPick = null;
        _coverPick = null;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page settings saved.')));
    } catch (e) {
      if (mounted) {
        setState(() { _saving = false; _error = 'Could not save changes. $e'; });
      }
    }
  }

  Future<void> _deactivatePage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate Page?'),
        content: const Text(
          'Your Page will be unpublished and hidden from normal visitors. '
          'Its content, followers, team, messages, reviews and settings will be preserved. '
          'You can reactivate it later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deactivate')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _pageLocalRepo.deactivatePage(widget.pageId);
      if (!mounted) return;
      setState(() => _isDeactivated = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page deactivated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not deactivate Page: $e')));
    }
  }

  Future<void> _reactivatePage() async {
    try {
      await _pageLocalRepo.reactivatePage(widget.pageId);
      if (!mounted) return;
      setState(() => _isDeactivated = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page reactivated and published.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reactivate Page: $e')));
    }
  }

  Future<void> _deletePagePermanently() async {
    final confirmation = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete Page?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes the Page and its Page-owned data. This cannot be undone. '
              'If you only want to hide the Page, use Deactivate instead.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmation,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, confirmation.text.trim() == 'DELETE'),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    confirmation.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await _pageLocalRepo.deletePagePermanently(widget.pageId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page permanently deleted.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete Page: $e')));
    }
  }

  Widget _buildLifecycleSection(BuildContext context) {
    if (!_isOwner) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: PageTokens.spaceXl),
        const PageSectionHeader(title: 'Page status'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(PageTokens.spaceMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PageTokens.radiusMd),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isDeactivated ? 'This Page is deactivated' : 'This Page is active',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  _isDeactivated
                      ? 'Visitors cannot discover or interact with the Page. Your Page data is preserved.'
                      : 'The Page is available to visitors according to its publishing and visibility settings.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: PageTokens.spaceMd),
                if (_isDeactivated)
                  OutlinedButton.icon(
                    onPressed: _reactivatePage,
                    icon: const Icon(Icons.public),
                    label: const Text('Reactivate Page'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _deactivatePage,
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: const Text('Deactivate Page'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: PageTokens.spaceLg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(PageTokens.spaceMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PageTokens.radiusMd),
              border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Danger zone', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 6),
                Text(
                  'Permanent deletion removes the Page and its Page-owned records. This cannot be undone.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: PageTokens.spaceMd),
                OutlinedButton.icon(
                  onPressed: _deletePagePermanently,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete Page permanently'),
                  style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page settings', style: TextStyle(fontWeight: FontWeight.w700))),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null && name.text.isEmpty
              ? ErrorRetryState(title: 'Unable to load settings', message: _error!, onRetry: _load)
              : !_canEdit
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(PageTokens.spaceXl),
                        child: Text("You don't have permission to edit this page's settings."),
                      ),
                    )
                  : Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceXxl),
                        children: [
                          PageImagePickerFrame(
                            label: 'Cover image',
                            aspect: 3,
                            circular: false,
                            hasImage: _coverPick != null || _coverUrl != null,
                            preview: _coverPick != null
                                ? PickedImagePreview(bytesFuture: _coverPick!.readAsBytes())
                                : _coverUrl != null
                                    ? Image.network(_coverUrl!, fit: BoxFit.cover)
                                    : null,
                            onTap: () => _pickImage(cover: true),
                            placeholderIcon: Icons.image_outlined,
                          ),
                          const SizedBox(height: PageTokens.spaceMd),
                          PageImagePickerFrame(
                            label: 'Logo',
                            aspect: 1,
                            circular: true,
                            hasImage: _logoPick != null || _logoUrl != null,
                            preview: _logoPick != null
                                ? PickedImagePreview(bytesFuture: _logoPick!.readAsBytes())
                                : _logoUrl != null
                                    ? Image.network(_logoUrl!, fit: BoxFit.cover)
                                    : null,
                            onTap: () => _pickImage(cover: false),
                            placeholderIcon: Icons.storefront,
                          ),
                          const SizedBox(height: PageTokens.spaceXl),
                          TextFormField(
                            controller: name,
                            maxLength: 100,
                            decoration: pageFieldDecoration(context, labelText: 'Page name'),
                            validator: (v) => (v == null || v.trim().length < 2) ? 'Name must be at least 2 characters' : null,
                          ),
                          const SizedBox(height: PageTokens.spaceSm),
                          TextFormField(
                            controller: username,
                            enabled: false,
                            decoration: pageFieldDecoration(
                              context,
                              labelText: 'Username',
                              prefixIcon: const Padding(padding: EdgeInsets.only(left: 12, right: 4), child: Text('@', style: TextStyle(fontWeight: FontWeight.w600))),
                              helperText: "Usernames can't be changed here. Contact support if you need this updated.",
                            ),
                          ),
                          const SizedBox(height: PageTokens.spaceSm),
                          TextFormField(
                            controller: description,
                            maxLength: 500,
                            maxLines: 3,
                            decoration: pageFieldDecoration(context, labelText: 'Description'),
                          ),
                          const SizedBox(height: PageTokens.spaceSm),
                          DropdownButtonFormField<String>(
                            initialValue: pageType,
                            decoration: pageFieldDecoration(context, labelText: 'Page type'),
                            items: kPageTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                            onChanged: (v) => setState(() => pageType = v ?? 'business'),
                          ),
                          const SizedBox(height: PageTokens.spaceSm),
                          DropdownButtonFormField<String?>(
                            initialValue: categoryId,
                            decoration: pageFieldDecoration(context, labelText: 'Category (optional)'),
                            items: <DropdownMenuItem<String?>>[
                              const DropdownMenuItem<String?>(value: null, child: Text('None')),
                              for (final c in categories) DropdownMenuItem<String?>(value: c['id'] as String, child: Text(c['name'] as String)),
                            ],
                            onChanged: (v) => setState(() => categoryId = v),
                          ),
                          const SizedBox(height: PageTokens.spaceMd),
                          const PageSectionHeader(title: 'Contact & details'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                            child: Column(
                              children: [
                                TextFormField(controller: website, keyboardType: TextInputType.url, decoration: pageFieldDecoration(context, labelText: 'Website (optional)', hintText: 'https://...')),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: pageFieldDecoration(context, labelText: 'Phone (optional)')),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: pageFieldDecoration(context, labelText: 'Email (optional)')),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(controller: location, decoration: pageFieldDecoration(context, labelText: 'Location (optional)', hintText: 'e.g. Thamel, Kathmandu')),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(controller: country, decoration: pageFieldDecoration(context, labelText: 'Country (optional)', hintText: 'e.g. Nepal')),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(controller: businessHoursNote, maxLines: 2, decoration: pageFieldDecoration(context, labelText: 'Business hours (optional)', hintText: 'e.g. Sun-Fri 9am-7pm, closed Sat')),
                                const SizedBox(height: PageTokens.spaceSm),
                                DropdownButtonFormField<String>(
                                  initialValue: language,
                                  decoration: pageFieldDecoration(context, labelText: 'Language'),
                                  items: const [
                                    DropdownMenuItem(value: 'en', child: Text('English')),
                                    DropdownMenuItem(value: 'ne', child: Text('नेपाली')),
                                  ],
                                  onChanged: (v) => setState(() => language = v ?? 'en'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: PageTokens.spaceMd),
                          const PageSectionHeader(title: 'Social links'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                            child: Column(
                              children: [
                                TextFormField(controller: facebook, keyboardType: TextInputType.url, decoration: pageFieldDecoration(context, labelText: 'Facebook', hintText: 'https://facebook.com/...')),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(controller: instagram, keyboardType: TextInputType.url, decoration: pageFieldDecoration(context, labelText: 'Instagram', hintText: 'https://instagram.com/...')),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(controller: x, keyboardType: TextInputType.url, decoration: pageFieldDecoration(context, labelText: 'X / Twitter', hintText: 'https://x.com/...')),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(controller: youtube, keyboardType: TextInputType.url, decoration: pageFieldDecoration(context, labelText: 'YouTube', hintText: 'https://youtube.com/...')),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(controller: tiktok, keyboardType: TextInputType.url, decoration: pageFieldDecoration(context, labelText: 'TikTok', hintText: 'https://tiktok.com/@...')),
                              ],
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: PageTokens.spaceMd),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                              child: Text(_error!, style: const TextStyle(color: Colors.red)),
                            ),
                          ],
                          const SizedBox(height: PageTokens.spaceLg),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _saving ? null : _save,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.brandTeal,
                                  foregroundColor: AppColors.onBrandTeal,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
                                ),
                                child: _saving
                                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                                    : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                          _buildLifecycleSection(context),
                        ],
                      ),
                    ),
    );
  }
}
