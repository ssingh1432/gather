import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../shared/services/media/web_safe_pick.dart';
import '../../shared/widgets/profile_view.dart' show PickedImagePreview;
import '../data/repositories.dart';
import 'pages_theme.dart';

/// Step 3 — Page Creation.
///
/// The page is created as `status: 'draft'` first, then the user lands on
/// the page preview screen to review it exactly as the public would see it
/// before publishing — this satisfies "Preview Before Publishing" without
/// needing a separate preview-only data path, since draft/published is
/// already the real lifecycle the schema uses (migration 072).
class CreatePageScreen extends StatefulWidget {
  const CreatePageScreen({super.key});
  @override
  State<CreatePageScreen> createState() => _CreatePageScreenState();
}

class _CreatePageScreenState extends State<CreatePageScreen> {
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
  bool loadingCategories = true;

  XFile? logoPick;
  XFile? coverPick;

  Timer? _usernameDebounce;
  bool? _usernameAvailable;
  bool _checkingUsername = false;

  String? err;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    if (SupabaseConfig.currentUserId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login?redirect=${Uri.encodeComponent('/create-page')}');
      });
    }
    username.addListener(_onUsernameChanged);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _repo.listCategories();
      if (mounted) {
        setState(() {
          categories = cats;
          loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loadingCategories = false);
    }
  }

  void _onUsernameChanged() {
    _usernameDebounce?.cancel();
    final value = _normalizeUsername(username.text);
    if (value.length < 3) {
      setState(() {
        _usernameAvailable = null;
        _checkingUsername = false;
      });
      return;
    }
    setState(() => _checkingUsername = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 400), () async {
      final available = await _repo.isUsernameAvailable(value);
      if (mounted && _normalizeUsername(username.text) == value) {
        setState(() {
          _usernameAvailable = available;
          _checkingUsername = false;
        });
      }
    });
  }

  String _normalizeUsername(String raw) => raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');

  @override
  void dispose() {
    username.removeListener(_onUsernameChanged);
    _usernameDebounce?.cancel();
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

  Future<void> _pickImage({required bool cover}) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final safe = await materializeIfWeb(picked);
    setState(() {
      if (cover) {
        coverPick = safe;
      } else {
        logoPick = safe;
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final normalizedUsername = _normalizeUsername(username.text);
    if (_usernameAvailable == false) {
      setState(() => err = 'That username is taken or reserved. Try another.');
      return;
    }
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) {
      context.go('/login?redirect=${Uri.encodeComponent('/create-page')}');
      return;
    }

    setState(() {
      loading = true;
      err = null;
    });

    try {
      final Map<String, dynamic> businessHours = businessHoursNote.text.trim().isEmpty
          ? <String, dynamic>{}
          : <String, dynamic>{'note': businessHoursNote.text.trim()};
      final page = await _repo.createPage({
        'username': normalizedUsername,
        'name': name.text.trim(),
        'category_id': categoryId,
        'page_type': pageType,
        'description': description.text.trim().isEmpty ? null : description.text.trim(),
        'website': website.text.trim().isEmpty ? null : website.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'email': email.text.trim().isEmpty ? null : email.text.trim(),
        'location': location.text.trim().isEmpty ? null : location.text.trim(),
        'country': country.text.trim().isEmpty ? null : country.text.trim(),
        'business_hours': businessHours,
        'language': language,
        'owner_id': uid,
        'created_by': uid,
        // status defaults to 'draft' in the DB — left unset here so the
        // preview screen is always the next stop, never straight to public.
      });
      final pageId = page['id'].toString();

      String? logoUrl;
      String? coverUrl;
      if (logoPick != null) logoUrl = await _repo.uploadLogo(pageId, logoPick!);
      if (coverPick != null) coverUrl = await _repo.uploadCover(pageId, coverPick!);
      if (logoUrl != null || coverUrl != null) {
        await _repo.updatePage(pageId, {
          if (logoUrl != null) 'logo_url': logoUrl,
          if (coverUrl != null) 'cover_url': coverUrl,
        });
      }

      if (!mounted) return;
      context.pushReplacement('/page-preview?id=$pageId');
    } catch (e) {
      final message = e.toString().contains('reserved') || e.toString().contains('conflicts with an existing profile handle')
          ? 'That username is taken or reserved. Try another.'
          : e.toString().contains('duplicate key') || e.toString().contains('pages_username_key')
              ? 'That username is already taken. Try another.'
              : 'Could not create page. $e';
      setState(() => err = message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Page', style: TextStyle(fontWeight: FontWeight.w700))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceXxl),
          children: [
            PageImagePickerFrame(
              label: 'Cover image (optional)',
              aspect: 3,
              circular: false,
              hasImage: coverPick != null,
              preview: coverPick != null ? PickedImagePreview(bytesFuture: coverPick!.readAsBytes()) : null,
              onTap: () => _pickImage(cover: true),
              placeholderIcon: Icons.image_outlined,
            ),
            const SizedBox(height: PageTokens.spaceMd),
            PageImagePickerFrame(
              label: 'Logo (optional)',
              aspect: 1,
              circular: true,
              hasImage: logoPick != null,
              preview: logoPick != null ? PickedImagePreview(bytesFuture: logoPick!.readAsBytes()) : null,
              onTap: () => _pickImage(cover: false),
              placeholderIcon: Icons.storefront,
            ),
            const SizedBox(height: PageTokens.spaceXl),
            TextFormField(
              controller: name,
              maxLength: 100,
              decoration: pageFieldDecoration(context, labelText: 'Page name', hintText: 'e.g. Himalayan Coffee House'),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Name must be at least 2 characters' : null,
            ),
            const SizedBox(height: PageTokens.spaceSm),
            TextFormField(
              controller: username,
              maxLength: 30,
              decoration: pageFieldDecoration(
                context,
                labelText: 'Username',
                hintText: 'e.g. himalayan_coffee',
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 12, right: 4), child: Text('@', style: TextStyle(fontWeight: FontWeight.w600))),
                suffixIcon: _checkingUsername
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : _usernameAvailable == true
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : _usernameAvailable == false
                            ? const Icon(Icons.cancel, color: Colors.red)
                            : null,
                helperText: _usernameAvailable == false
                    ? 'Taken, reserved, or conflicts with an existing profile handle'
                    : _usernameAvailable == true
                        ? 'Available'
                        : 'Lowercase letters, numbers, underscore — 3-30 characters',
                helperStyle: TextStyle(color: _usernameAvailable == false ? Colors.red : (_usernameAvailable == true ? Colors.green : null)),
              ),
              validator: (v) => _normalizeUsername(v ?? '').length < 3 ? 'Username must be at least 3 characters' : null,
            ),
            const SizedBox(height: PageTokens.spaceSm),
            TextFormField(
              controller: description,
              maxLength: 500,
              maxLines: 3,
              decoration: pageFieldDecoration(context, labelText: 'Description', hintText: 'What does this page represent?'),
            ),
            const SizedBox(height: PageTokens.spaceSm),
            DropdownButtonFormField<String>(
              initialValue: pageType,
              decoration: pageFieldDecoration(context, labelText: 'Page type'),
              items: kPageTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => pageType = v ?? 'business'),
            ),
            const SizedBox(height: PageTokens.spaceSm),
            loadingCategories
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator())
                : DropdownButtonFormField<String?>(
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
            if (err != null) ...[
              const SizedBox(height: PageTokens.spaceMd),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                child: Text(err!, style: const TextStyle(color: Colors.red)),
              ),
            ],
            const SizedBox(height: PageTokens.spaceLg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandTeal,
                    foregroundColor: AppColors.onBrandTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
                  ),
                  child: loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                      : const Text('Continue to preview', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
