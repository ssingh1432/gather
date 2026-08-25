import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/pages/page_media_collection_ux.dart';

void main() {
  test('every Page media tile uses the first attachment as gallery entry', () {
    expect(pageMediaCollectionEntryIndex(0), 0);
    expect(pageMediaCollectionEntryIndex(1), 0);
    expect(pageMediaCollectionEntryIndex(2), 0);
    expect(pageMediaCollectionEntryIndex(999), 0);
  });

  test('Page +More appears only beyond the four-item preview limit', () {
    expect(pageMediaMoreCount(1), 0);
    expect(pageMediaMoreCount(4), 0);
    expect(pageMediaMoreCount(5), 1);
    expect(pageMediaMoreCount(9), 5);
  });

  test('+More uses the same gallery entry point as the media collection', () {
    expect(pageMediaMoreEntryIndex(4), -1);
    expect(pageMediaMoreEntryIndex(5), 0);
    expect(pageMediaMoreEntryIndex(20), 0);
  });
}
