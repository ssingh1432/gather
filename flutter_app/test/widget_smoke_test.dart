import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/auth/login_screen.dart';
import 'package:gather_app/features/auth/signup_screen.dart';
import 'package:gather_app/features/auth/forgot_password_screen.dart';

void main() {
  testWidgets('auth screens render core fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Login'), findsWidgets);

    await tester.pumpWidget(MaterialApp(home: SignupScreen()));
    expect(find.text('Sign Up'), findsWidgets);

    await tester.pumpWidget(ForgotPasswordScreen());
    expect(find.text('Forgot Password'), findsWidgets);
  });
}
