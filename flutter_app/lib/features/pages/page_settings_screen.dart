import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/services/media/web_safe_pick.dart';
import '../../shared/widgets/profile_view.dart' show PickedImagePreview;
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'pages_theme.dart';

/// Page Settings — edit a page's core info after creation.
///
/// This screen didn't exist before: `manage_settings` was already defined
/// as a page permission (migration 072, "Edit page info, category, contact
/// details, business hours") and already gates the `pages` UPDATE RLS
/// policy, but no screen ever called `updatePage` with anything beyond the
/// create flow's initial insert, the publish-status flip, or the
/// monetization toggle. In practice that meant a page's name, description,
/// category, contact details, and business hours were frozen forever once
/// created. This screen is that missing piece — it uses the same
/// `PageRepository.updatePage` the create flow already relies on, so no
/// backend/RLS changes were needed.
///
/// Username is intentionally read-only here: it's part of the page's
/// public URL/identity and changing it is a bigger decision (broken links,
/// confusion for existing followers) than a settings-screen text field
/// should casually allow. If page owners need that later, it deserves its
/// own explicit, confirmed flow — not bundled into this one.
class PageSettingsScreen extends StatefulWidget {
  const PageSettingsScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PageSettingsScreen> createState() => _PageSettingsScreenState();
}

class _PageSettingsScreenState extends State<PageSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = PageRepository();

  final name = TextEditingController();
  final username = TextEditingController();
  final description = TextEditingController();
  final website = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final location = TextEditingController();
  final country = TextEditingController();
  final businessHoursNote = TextEditingController();

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
      ]);
      final page = results[0] as Map<String, dynamic>?;
      final canEdit = results[1] as bool;
      final cats = results[2] as List<Map<String, dynamic>>;
      if (page == null) {
        if (mounted) setState(() { _error = 'Page not found.'; _loading = false; });
        return;
      }
      final hours = page['business_hours'];
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
        pageType = page['page_type'] as String? ?? 'business';
        language = page['language'] as String? ?? 'en';
        categoryId = page['category_id'] as String?;
        _logoUrl = page['logo_url'] as String?;
        _coverUrl = page['cover_url'] as String?;
        categories = cats;
        _canEdit = canEdit;
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
          businessHoursNote.text.trim().isEmpty ? <String, dynamic>{} : <String, dynamic>{'note': businessHoursNote.text.trim()};

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
                                TextFormField(
                                  controller: website,
                                  keyboardType: TextInputType.url,
                                  decoration: pageFieldDecoration(context, labelText: 'Website (optional)', hintText: 'https://...'),
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(
                                  controller: phone,
                                  keyboardType: TextInputType.phone,
                                  decoration: pageFieldDecoration(context, labelText: 'Phone (optional)'),
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(
                                  controller: email,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: pageFieldDecoration(context, labelText: 'Email (optional)'),
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(
                                  controller: location,
                                  decoration: pageFieldDecoration(context, labelText: 'Location (optional)', hintText: 'e.g. Thamel, Kathmandu'),
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(
                                  controller: country,
                                  decoration: pageFieldDecoration(context, labelText: 'Country (optional)', hintText: 'e.g. Nepal'),
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                TextFormField(
                                  controller: businessHoursNote,
                                  maxLines: 2,
                                  decoration: pageFieldDecoration(context, labelText: 'Business hours (optional)', hintText: 'e.g. Sun-Fri 9am-7pm, closed Sat'),
                                ),
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
                        ],
                      ),
                    ),
    );
  }
}
