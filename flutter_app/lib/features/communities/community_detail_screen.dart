import 'package:flutter/material.dart';
import '../../features/data/repositories.dart';
import '../../core/supabase_client.dart';
import '../../shared/widgets/reusables.dart';

class CommunityDetailScreen extends StatefulWidget { const CommunityDetailScreen({super.key, this.communityId=''}); final String communityId; @override State<CommunityDetailScreen> createState()=>_D(); }
class _D extends State<CommunityDetailScreen>{final repo=FeedRepository(); final postCtrl=TextEditingController();@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Community')),body:Column(children:[Padding(padding:const EdgeInsets.all(8),child:TextField(controller:postCtrl,decoration:const InputDecoration(labelText:'Create post text'))),ElevatedButton(onPressed:()async{final uid=SupabaseConfig.client.auth.currentUser?.id; if(uid==null)return;await PostRepository().createPost({'author_id':uid,'community_id':widget.communityId,'text_content':postCtrl.text.trim()});setState((){});},child:const Text('Post')),Expanded(child:FutureBuilder(future:repo.communityFeed(widget.communityId),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final ps=s.data!;if(ps.isEmpty)return const Text('No posts');return ListView(children:ps.map((p)=>PostCard(post:p,onLike:(){},onComment:(){},onBookmark:(){})).toList());}))]));}
