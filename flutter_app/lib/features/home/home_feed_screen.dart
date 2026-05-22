import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/reusables.dart';

class HomeFeedScreen extends ConsumerStatefulWidget { const HomeFeedScreen({super.key}); @override ConsumerState<HomeFeedScreen> createState()=>_S(); }
class _S extends ConsumerState<HomeFeedScreen>{int page=0;@override Widget build(BuildContext c){final feed=ref.watch(homeFeedProvider(page));return Scaffold(appBar:AppBar(title:const Text('Home')),body:feed.when(data:(posts)=>RefreshIndicator(onRefresh:() async=>setState((){}),child:ListView(children:[if(posts.isEmpty) const ListTile(title:Text('No posts yet')), ...posts.map((p)=>PostCard(post:p,onLike:()async{},onComment:() {},onBookmark:()async{})),TextButton(onPressed:(){setState(()=>page++);}, child: const Text('Load more'))])),error:(e,_)=>Center(child:Text('$e')),loading:()=>const Center(child:CircularProgressIndicator())));}}
