import 'package:flutter/material.dart';

import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'file_complaint_screen.dart';

/// Tracks the current user's own legal complaints and appeals — the
/// grievance/appeal side of Phase 4 Nepal legal compliance.
class MyLegalScreen extends StatefulWidget {
  const MyLegalScreen({super.key});

  @override
  State<MyLegalScreen> createState() => _MyLegalScreenState();
}

class _MyLegalScreenState extends State<MyLegalScreen> with SingleTickerProviderStateMixin {
  final _repo = LegalRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<List<Map<String, dynamic>>> _complaints;
  late Future<List<Map<String, dynamic>>> _appeals;