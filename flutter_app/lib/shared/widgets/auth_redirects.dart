import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void redirectToLogin(
  BuildContext context, {
  required String redirect,
  String message = 'Please log in or create an account to continue.',
}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  context.go('/login?redirect=${Uri.encodeComponent(redirect)}');
}
