import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';

class CreatePostScreen extends StatefulWidget { const CreatePostScreen({super.key, this.communityId}); final String? communityId; @override State<CreatePostScreen> createState()=>_P(); }
class _P extends State<CreatePostScreen>{final text=TextEditingController();XFile? image;bool loading=false;String? err;@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Create Post')),body:Padding(padding:const EdgeInsets.all(16),child:Column(children:[TextField(controller:text,decoration:const InputDecoration(labelText:'Text content')),TextButton(onPressed:()async{image=await ImagePicker().pickImage(source:ImageSource.gallery);setState((){});}, child:Text(image==null?'Pick image':'Image selected')),if(err!=null) Text(err!,style:const TextStyle(color:Colors.red)),ElevatedButton(onPressed:loading?null:()async{final uid=SupabaseConfig.client.auth.currentUser?.id;if(uid==null)return;if(text.text.trim().isEmpty && image==null){setState(()=>err='Add text or image');return;}setState(()=>loading=true);final created=await SupabaseConfig.client.from('posts').insert({'author_id':uid,'community_id':widget.communityId,'text_content':text.text.trim()}).select().single();if(image!=null){final url=await PostRepository().uploadPostImage(uid,image!);if(url!=null){await PostRepository().addPostMedia(created['id'],url);}}if(mounted)Navigator.pop(context);}, child:const Text('Publish'))]))));}
