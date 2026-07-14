import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../features/data/repositories.dart';
import '../services/ads_service.dart';

/// A "Sponsored" card matching the feed's card styling, holding a banner
/// ad. Renders nothing (SizedBox.shrink) until the ad actually loads, and
/// nothing forever if loading fails — a broken ad slot should never leave
/// a visible gap or error in the feed.
///
/// [postId] is the approved creator's post this ad is attached to — an
/// impression is only logged (server-side, for manual payout review) once
/// the ad actually renders, not just when the slot is scheduled.
class FeedAdCard extends StatefulWidget {
  const FeedAdCard({super.key, required this.postId});

  final String postId;

  @override
  State<FeedAdCard> createState() => _FeedAdCardState();
}

class _FeedAdCardState extends State<FeedAdCard> {
  BannerAd? _ad;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (AdsService.supportedOnThisPlatform) {
      AdsService.instance.loadBannerAd(
        onLoaded: (ad) {
          if (mounted) setState(() => _ad = ad as BannerAd);
          MonetizationRepository().logAdImpression(widget.postId);
        },
        onFailed: (ad, error) {
          if (mounted) setState(() => _failed = true);
        },
      );
    } else {
      _failed = true;
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (_failed || ad == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Sponsored',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
            ),
          ),
          SizedBox(
            width: ad.size.width.toDouble(),
            height: ad.size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
