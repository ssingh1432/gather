import 'package:flutter/material.dart';
import '../data/repositories.dart';
import '../../core/supabase_client.dart';
import '../../shared/widgets/reusables.dart';
import 'package:go_router/go_router.dart';

class CommunitiesScreen extends StatefulWidget { const CommunitiesScreen({super.key}); @override State<CommunitiesScreen> createState()=>_C(); }
class _C extends State<CommunitiesScreen>{final repo=CommunityRepository();final q=TextEditingController();Future<List<Map<String,dynamic>>>? f;@override void initState(){super.initState();f=repo.listCommunities();}
@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Communities')),floatingActionButton:FloatingActionButton(onPressed:()=>context.push('/create-community'),child:const Icon(Icons.add)),body:Column(children:[Padding(padding:const EdgeInsets.all(8),child:TextField(controller:q,decoration:InputDecoration(hintText:'Search',suffixIcon:IconButton(icon:const Icon(Icons.search),onPressed:()=>setState(()=>f=repo.listCommunities(q.text.trim()))))),),Expanded(child:FutureBuilder(future:f,builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final data=s.data!;if(data.isEmpty)return const Center(child:Text('No communities'));return ListView(children:data.map((e)=>CommunityCard(community:e,onOpen:()=>context.push('/community?id=${e['id']}'),onJoinLeave:()async{final uid=SupabaseConfig.client.auth.currentUser?.id;if(uid==null)return;await repo.joinCommunity(e['id'],uid);})).toList());}))]));}
