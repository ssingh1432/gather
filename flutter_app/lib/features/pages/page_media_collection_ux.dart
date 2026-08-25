/// Page-only media collection interaction rules.
///
/// A post's media preview is one collection entry point. The preview tile
/// that was tapped is not an alternate entry point; the gallery always starts
/// at the first attachment so users get one predictable flow.
int pageMediaCollectionEntryIndex(int tappedIndex) => 0;
