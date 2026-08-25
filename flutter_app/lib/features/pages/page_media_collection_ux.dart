/// Page-only media collection interaction rules.
///
/// A post's media preview is one collection entry point. The preview tile
/// that was tapped is not an alternate entry point; the gallery always starts
/// at the first attachment so users get one predictable flow.
int pageMediaCollectionEntryIndex(int tappedIndex) => 0;

const int pageMediaPreviewLimit = 4;

int pageMediaMoreCount(int attachmentCount) {
  if (attachmentCount <= pageMediaPreviewLimit) return 0;
  return attachmentCount - pageMediaPreviewLimit;
}

/// The +More overlay belongs to the same collection entry point as every tile.
int pageMediaMoreEntryIndex(int attachmentCount) =>
    pageMediaMoreCount(attachmentCount) > 0 ? 0 : -1;
