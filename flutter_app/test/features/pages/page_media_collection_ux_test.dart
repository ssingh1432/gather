import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/pages/page_media_collection_ux.dart';

void main() {
  test('every Page media tile uses the first attachment as gallery entry', () {
    expect(pageMediaCollectionEntryIndex(0), 0);
    expect(pageMediaCollectionEntryIndex(1), 0);
    expect(pageMediaCollectionEntryIndex(2), 0);
    expect(pageMediaCollectionEntryIndex(999), 0);
  });
}
