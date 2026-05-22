import 'package:flutter_test/flutter_test.dart';

class FakeFeedRepository {
  Future<List<String>> homeFeed() async => ['post_1', 'post_2'];
}

void main() {
  test('repository mock returns list', () async {
    final repo = FakeFeedRepository();
    final posts = await repo.homeFeed();
    expect(posts.length, 2);
  });
}
