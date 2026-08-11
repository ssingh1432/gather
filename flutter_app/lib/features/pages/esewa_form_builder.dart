import 'dart:convert';

import 'package:http/http.dart' as http;

/// The signed eSewa v2 form fields returned by the esewa-payment edge
/// function's `/init/<id>` endpoint (JSON, not HTML — see
/// esewa_launcher.dart for why).
class EsewaFormFields {
  const EsewaFormFields(this.formUrl, this.fields);
  final String formUrl;
  final Map<String, String> fields;

  String? get successUrl => fields['success_url'];
  String? get failureUrl => fields['failure_url'];
}

class EsewaInitException implements Exception {
  EsewaInitException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fetches the signed form fields for a transaction from [initUrl]
/// (`PageRepository.esewaInitUrl(transactionId)`).
Future<EsewaFormFields> fetchEsewaFields(String initUrl) async {
  final http.Response res;
  try {
    res = await http.get(Uri.parse(initUrl));
  } catch (e) {
    throw EsewaInitException('Could not reach the payment server. Check your connection and try again.');
  }

  Map<String, dynamic> body;
  try {
    body = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {
    throw EsewaInitException('Unexpected response from the payment server.');
  }

  if (res.statusCode != 200) {
    throw EsewaInitException(body['message'] as String? ?? 'Could not start eSewa payment.');
  }

  final rawFields = body['fields'] as Map<String, dynamic>? ?? {};
  final fields = rawFields.map((k, v) => MapEntry(k, v.toString()));
  final formUrl = body['formUrl'] as String?;
  if (formUrl == null || fields.isEmpty) {
    throw EsewaInitException('Payment server returned an incomplete response.');
  }
  return EsewaFormFields(formUrl, fields);
}

/// Builds the tiny auto-submitting HTML form — identical in spirit to
/// what the edge function used to serve directly (see the deprecated
/// /pay/<id> HTML fallback there), just now built on-device so Supabase
/// never has to serve HTML at all.
String buildEsewaFormHtml(EsewaFormFields f) {
  final inputs = f.fields.entries
      .map((e) => '<input type="hidden" name="${e.key}" value="${e.value.replaceAll('"', '&quot;')}">')
      .join('\n');
  return '''
<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Redirecting to eSewa\u2026</title>
<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F4F6F5;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px;text-align:center;}
.card{background:#fff;border-radius:12px;padding:32px;max-width:420px;box-shadow:0 1px 3px rgba(0,0,0,0.1);}
p{color:#4B5563;font-size:15px;line-height:1.5;margin:0 0 20px;}
button{background:#0F766E;color:#fff;border:none;border-radius:8px;padding:14px 28px;font-size:16px;font-weight:600;}</style>
</head>
<body onload="document.forms[0].submit()">
  <div class="card">
    <p>Redirecting to eSewa\u2026</p>
    <form method="POST" action="${f.formUrl}">
      $inputs
      <button type="submit">Continue to eSewa</button>
    </form>
    <p style="margin-top:16px;font-size:13px;">If nothing happens automatically, tap the button above.</p>
  </div>
</body></html>''';
}
