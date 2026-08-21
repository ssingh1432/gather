import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import 'page_content_composer_screen.dart';
import 'page_visitor_post_repository.dart';

class PageVisitorPostComposerScreen extends StatefulWidget {
  const PageVisitorPostComposerScreen({super.key, required this.pageId, required this.pageName, required this.requireApproval});
  final String pageId;
  final String pageName;
  final bool requireApproval;
  @override State<PageVisitorPostComposerScreen> createState() => _PageVisitorPostComposerScreenState();
}

class _PageVisitorPostComposerScreenState extends State<PageVisitorPostComposerScreen> {
  final _repo = PageVisitorPostRepository();
  final _text = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  XFile? _video;
  final List<PlatformFile> _documents = [];
  String? _eventId;
  List<Map<String, dynamic>> _events = const [];
  bool _loadingEvents = false;
  bool _submitting = false;
  bool _redirectingOwner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectPageManagerToOwnerComposer());
  }

  @override
  void dispose() { _text.dispose(); super.dispose(); }

  Future<void> _redirectPageManagerToOwnerComposer() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null || _redirectingOwner) return;
    try {
      final role = await SupabaseConfig.client
          .from('page_roles')
          .select('role')
          .eq('page_id', widget.pageId)
          .eq('user_id', uid)
          .maybeSingle();
      if (role != null && mounted) {
        setState(() => _redirectingOwner = true);
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => PageContentComposerScreen(pageId: widget.pageId)),
        );
      }
    } catch (_) {
      // RLS remains authoritative. If role lookup is unavailable, keep the
      // visitor composer and let the server reject unauthorized operations.
    }
  }

  String _mimeTypeFor(String name, {String fallback = 'application/octet-stream'}) {
    final extension = name.toLowerCase().split('.').last;
    const types = {'jpg':'image/jpeg','jpeg':'image/jpeg','png':'image/png','gif':'image/gif','webp':'image/webp','mp4':'video/mp4','mov':'video/quicktime','m4v':'video/x-m4v','webm':'video/webm','pdf':'application/pdf','doc':'application/msword','docx':'application/vnd.openxmlformats-officedocument.wordprocessingml.document','txt':'text/plain'};
    return types[extension] ?? fallback;
  }

  bool _isSupported(String mime) => const {'image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime','video/x-m4v','video/webm','application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','text/plain'}.contains(mime);

  String _contentType() {
    if (_images.isNotEmpty) return 'image';
    if (_video != null) return 'video';
    if (_documents.isNotEmpty) return 'document';
    if (_eventId != null) return 'event';
    return 'text';
  }

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage();
    if (!mounted) return;
    if (files.isNotEmpty) setState(() => _images.addAll(files));
  }

  Future<void> _pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f != null && mounted) setState(() => _video = f);
  }

  Future<void> _pickDocuments() async {
    final r = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf','doc','docx','txt']);
    if (!mounted || r == null) return;
    final accepted = <PlatformFile>[];
    var rejected = 0;
    for (final file in r.files) {
      final mime = _mimeTypeFor(file.name);
      if (!_isSupported(mime) || file.bytes == null || file.bytes!.length > PageVisitorPostRepository.maxBytes) { rejected++; continue; }
      accepted.add(file);
    }
    if (accepted.isNotEmpty) setState(() => _documents.addAll(accepted));
    if (rejected > 0) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$rejected file(s) were not added. Supported files must be under 25 MB.')));
  }

  Future<void> _loadEvents() async {
    setState(()=>_loadingEvents=true);
    try { final e=await _repo.listEvents(widget.pageId); if(mounted)setState(()=>_events=e); }
    catch (_) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load Page events.'))); }
    finally { if(mounted)setState(()=>_loadingEvents=false); }
  }

  Future<void> _validateSelectedMedia() async {
    for (final image in _images) {
      final size = await image.length();
      if (size > PageVisitorPostRepository.maxBytes) {
        throw PageVisitorMediaException('${image.name} is larger than the 25 MB limit.');
      }
      final mime = _mimeTypeFor(image.name, fallback: 'image/jpeg');
      if (!_isSupported(mime)) throw PageVisitorMediaException('${image.name} is not a supported Page media type.');
    }
    if (_video != null) {
      final size = await _video!.length();
      if (size > PageVisitorPostRepository.maxBytes) {
        throw PageVisitorMediaException('${_video!.name} is larger than the 25 MB limit.');
      }
      final mime = _mimeTypeFor(_video!.name, fallback: 'video/mp4');
      if (!_isSupported(mime)) throw PageVisitorMediaException('${_video!.name} is not a supported Page media type.');
    }
    for (final document in _documents) {
      final bytes = document.bytes;
      if (bytes == null) throw PageVisitorMediaException('Could not read ${document.name}. Please select it again.');
      if (bytes.isEmpty) throw PageVisitorMediaException('${document.name} is empty.');
      if (bytes.length > PageVisitorPostRepository.maxBytes) {
        throw PageVisitorMediaException('${document.name} is larger than the 25 MB limit.');
      }
      final mime = _mimeTypeFor(document.name);
      if (!_isSupported(mime)) throw PageVisitorMediaException('${document.name} is not a supported Page media type.');
    }
  }

  Future<void> _submit() async {
    if (_submitting || _redirectingOwner) return;
    final hasMedia = _images.isNotEmpty || _video != null || _documents.isNotEmpty;
    if (_text.text.trim().isEmpty && !hasMedia && _eventId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add text, media, or an event.')));
      return;
    }
    setState(()=>_submitting=true);
    String? postId;
    try {
      await _validateSelectedMedia();
      postId=await _repo.createVisitorPost(pageId:widget.pageId,content:_text.text,contentType:_contentType(),eventId:_eventId);
      final media=<Map<String,dynamic>>[];
      for (final image in _images) {
        final bytes = await image.readAsBytes();
        media.add({'type':'image','name':image.name,'url':await _repo.uploadMedia(pageId:widget.pageId,postId:postId,bytes:bytes,mimeType:_mimeTypeFor(image.name,fallback:'image/jpeg'),fileName:image.name)});
      }
      if (_video != null) {
        final bytes = await _video!.readAsBytes();
        media.add({'type':'video','name':_video!.name,'url':await _repo.uploadMedia(pageId:widget.pageId,postId:postId,bytes:bytes,mimeType:_mimeTypeFor(_video!.name,fallback:'video/mp4'),fileName:_video!.name)});
      }
      for (final document in _documents) {
        final bytes=document.bytes!;
        media.add({'type':'document','name':document.name,'url':await _repo.uploadMedia(pageId:widget.pageId,postId:postId,bytes:bytes,mimeType:_mimeTypeFor(document.name),fileName:document.name)});
      }
      if (media.isNotEmpty) await _repo.updateMedia(postId,media);
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.requireApproval?'Submitted for Page review.':'Your post was published.')));Navigator.pop(context,true);}
    } on PageVisitorMediaException catch(e) {
      if(postId!=null){try{await _repo.deleteVisitorPostWithMedia(pageId:widget.pageId,postId:postId);}catch(_) {}}
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));
    } catch(e) {
      if(postId!=null){try{await _repo.deleteVisitorPostWithMedia(pageId:widget.pageId,postId:postId);}catch(_) {}}
      final message = PageVisitorPostRepository.friendlyUnexpectedError(e);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
    } finally { if(mounted)setState(()=>_submitting=false); }
  }

  Widget _attachmentList() => Column(children:[
    for (var i=0;i<_images.length;i++) ListTile(leading:const Icon(Icons.photo),title:Text(_images[i].name),trailing:IconButton(onPressed:()=>setState(()=>_images.removeAt(i)),icon:const Icon(Icons.close))),
    if(_video!=null) ListTile(leading:const Icon(Icons.videocam),title:Text(_video!.name),trailing:IconButton(onPressed:()=>setState(()=>_video=null),icon:const Icon(Icons.close))),
    for (var i=0;i<_documents.length;i++) ListTile(leading:const Icon(Icons.insert_drive_file),title:Text(_documents[i].name),trailing:IconButton(onPressed:()=>setState(()=>_documents.removeAt(i)),icon:const Icon(Icons.close))),
  ]);

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text('Post on ${widget.pageName}')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
      Text('Posting as you on ${widget.pageName}',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700)),
      if(widget.requireApproval)Padding(padding:const EdgeInsets.only(top:8),child:Text('This Page reviews visitor posts before they become public.',style:Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height:16),
      Wrap(spacing:8,runSpacing:8,children:[
        OutlinedButton.icon(onPressed:_pickImages,icon:const Icon(Icons.photo_library_outlined),label:const Text('Images')),
        OutlinedButton.icon(onPressed:_pickVideo,icon:const Icon(Icons.videocam_outlined),label:const Text('Video')),
        OutlinedButton.icon(onPressed:_pickDocuments,icon:const Icon(Icons.attach_file),label:const Text('Files')),
        OutlinedButton.icon(onPressed:(){_loadEvents();},icon:const Icon(Icons.event_outlined),label:const Text('Event')),
      ]),
      const SizedBox(height:12),
      TextField(controller:_text,maxLines:7,maxLength:5000,decoration:const InputDecoration(hintText:'Write something for this Page…',border:OutlineInputBorder())),
      _attachmentList(),
      if (_loadingEvents) const LinearProgressIndicator(),
      if (_events.isNotEmpty) Padding(padding:const EdgeInsets.only(top:8),child:DropdownButtonFormField<String>(initialValue:_eventId,decoration:const InputDecoration(labelText:'Attach an existing Page event',border:OutlineInputBorder()),items:[for(final e in _events)DropdownMenuItem(value:e['id'] as String,child:Text(e['title']?.toString()??'Event'))],onChanged:(v)=>setState(()=>_eventId=v))),
      if (_eventId != null) ListTile(leading:const Icon(Icons.event),title:Text(_events.firstWhere((e)=>e['id']==_eventId,orElse:()=>{'title':'Event'})['title']?.toString()??'Event'),trailing:IconButton(onPressed:()=>setState(()=>_eventId=null),icon:const Icon(Icons.close))),
      const SizedBox(height:20),
      FilledButton.icon(onPressed:_submitting?null:_submit,icon:_submitting?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.send),label:Text(widget.requireApproval?'Submit for review':'Post')),
    ])),
  );
}
