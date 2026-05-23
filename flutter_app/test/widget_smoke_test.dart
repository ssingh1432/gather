import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/auth/forgot_password_screen.dart';
import 'package:gather_app/features/auth/login_screen.dart';
import 'package:gather_app/features/auth/signup_screen.dart';
import 'package:gather_app/features/communities/communities_screen.dart';
import 'package:gather_app/features/home/home_feed_screen.dart';
import 'package:gather_app/features/profile/profile_screen.dart';

void main() {
  testWidgets('auth screens render core fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Login'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: SignupScreen()));
    expect(find.text('Signup'), findsOneWidget);

    await tester.pumpWidget(ForgotPasswordScreen());
    expect(find.text('Forgot Password'), findsWidgets);
  });

  testWidgets('HomeFeedScreen smoke test', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeFeedScreen()));
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('CommunitiesScreen smoke test', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CommunitiesScreen()));
    expect(find.text('Communities'), findsOneWidget);
  });

  testWidgets('ProfileScreen smoke test', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    expect(find.text('My Profile'), findsOneWidget);
  });
}
