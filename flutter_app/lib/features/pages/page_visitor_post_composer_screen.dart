import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  String _type = 'text';
  XFile? _image;
  XFile? _video;
  PlatformFile? _document;
  String? _eventId;
  List<Map<String, dynamic>> _events = const [];
  bool _loadingEvents = false;
  bool _submitting = false;

  @override void dispose() { _text.dispose(); super.dispose(); }

  Future<void> _pickImage() async { final f = await _picker.pickImage(source: ImageSource.gallery); if (f != null && mounted) setState(() { _type='image'; _image=f; _video=null; _document=null; _eventId=null; }); }
  Future<void> _pickVideo() async { final f = await _picker.pickVideo(source: ImageSource.gallery); if (f != null && mounted) setState(() { _type='video'; _video=f; _image=null; _document=null; _eventId=null; }); }
  Future<void> _pickDocument() async { final r = await FilePicker.platform.pickFiles(withData:true, type:FileType.custom, allowedExtensions:['pdf','doc','docx']); final f=r?.files.single; if(f!=null&&mounted)setState((){_type='document';_document=f;_image=null;_video=null;_eventId=null;}); }
  Future<void> _loadEvents() async { setState(()=>_loadingEvents=true); try { final e=await _repo.listEvents(widget.pageId); if(mounted)setState(()=>_events=e); } finally { if(mounted)setState(()=>_loadingEvents=false); } }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(()=>_submitting=true);
    String? postId;
    try {
      postId=await _repo.createVisitorPost(pageId:widget.pageId,content:_text.text,contentType:_type,eventId:_eventId);
      final media=<Map<String,dynamic>>[];
      if(_image!=null) media.add({'type':'image','name':_image!.name,'url':await _repo.uploadMedia(pageId:widget.pageId,postId:postId,bytes:await _image!.readAsBytes(),mimeType:_image!.mimeType??'image/jpeg',fileName:_image!.name)});
      if(_video!=null) media.add({'type':'video','name':_video!.name,'url':await _repo.uploadMedia(pageId:widget.pageId,postId:postId,bytes:await _video!.readAsBytes(),mimeType:_video!.mimeType??'video/mp4',fileName:_video!.name)});
      if(_document!=null){final bytes=_document!.bytes;if(bytes==null)throw ArgumentError('Could not read the selected document.');media.add({'type':'document','name':_document!.name,'url':await _repo.uploadMedia(pageId:widget.pageId,postId:postId,bytes:bytes,mimeType:_document!.mimeType??'application/octet-stream',fileName:_document!.name)});}
      if(media.isNotEmpty)await _repo.updateMedia(postId,media);
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.requireApproval?'Submitted for Page review.':'Your post was published.')));Navigator.pop(context,true);}
    } catch(e) {
      if(postId!=null){try{await _repo.deleteVisitorPost(postId);}catch(_){} }
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not create post: ${e.toString().replaceFirst('Exception: ','')}')));
    } finally { if(mounted)setState(()=>_submitting=false); }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text('Post on ${widget.pageName}')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
      Text('Posting as you on ${widget.pageName}',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700)),
      if(widget.requireApproval)Padding(padding:const EdgeInsets.only(top:8),child:Text('This Page reviews visitor posts before they become public.',style:Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height:16),
      Wrap(spacing:8,children:[
        ChoiceChip(label:const Text('Text'),selected:_type=='text',onSelected:(_){setState(()=>_type='text');}),
        ChoiceChip(label:const Text('Photo'),selected:_type=='image',onSelected:(_)=>_pickImage()),
        ChoiceChip(label:const Text('Video'),selected:_type=='video',onSelected:(_)=>_pickVideo()),
        ChoiceChip(label:const Text('File'),selected:_type=='document',onSelected:(_)=>_pickDocument()),
        ChoiceChip(label:const Text('Event'),selected:_type=='event',onSelected:(_){setState(()=>_type='event');_loadEvents();}),
      ]),
      const SizedBox(height:16),
      TextField(controller:_text,maxLines:7,maxLength:5000,decoration:const InputDecoration(hintText:'Write something for this Page…',border:OutlineInputBorder())),
      if(_image!=null)ListTile(leading:const Icon(Icons.photo),title:Text(_image!.name),trailing:IconButton(onPressed:()=>setState(()=>_image=null),icon:const Icon(Icons.close))),
      if(_video!=null)ListTile(leading:const Icon(Icons.videocam),title:Text(_video!.name),trailing:IconButton(onPressed:()=>setState(()=>_video=null),icon:const Icon(Icons.close))),
      if(_document!=null)ListTile(leading:const Icon(Icons.insert_drive_file),title:Text(_document!.name),trailing:IconButton(onPressed:()=>setState(()=>_document=null),icon:const Icon(Icons.close))),
      if(_type=='event')...[
        _loadingEvents?const LinearProgressIndicator():DropdownButtonFormField<String>(value:_eventId,decoration:const InputDecoration(labelText:'Choose an existing Page event',border:OutlineInputBorder()),items:[for(final e in _events)DropdownMenuItem(value:e['id'] as String,child:Text(e['title']?.toString()??'Event'))],onChanged:(v)=>setState(()=>_eventId=v)),
        const SizedBox(height:8),
        Text('Visitor posts can attach an existing Page event. Event creation remains Page-managed.',style:Theme.of(context).textTheme.bodySmall),
      ],
      const SizedBox(height:20),
      FilledButton.icon(onPressed:_submitting?null:_submit,icon:_submitting?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.send),label:Text(widget.requireApproval?'Submit for review':'Post')),
    ])),
  );
}
