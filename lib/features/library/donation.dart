// The optional "buy me a coffee" link. It is a deliberate DESIGN CONSTRAINT,
// not a feature: the link NEVER gates content, removes no ads, and unlocks
// nothing — so it stays clear of Apple's IAP rules (US external links) and fits
// Google Play's peer-to-peer tip exception, and it never conflicts with the
// CC0/CC-BY/CC-BY-SA content we bundle. See docs/LIBRARIES_AND_TAB_SCOPING.md
// §1.8.
//
// It ships DISABLED. Turning it on later is a one-line change here (set
// [enabled] + [url]) with NO other app edits — the tile reads this config.

class DonationConfig {
  /// Whether to show the "Support the developer" tile.
  final bool enabled;

  /// External donation URL (Ko-fi / Buy Me a Coffee / PayPal). Opened in the
  /// browser — never in-app billing.
  final String url;

  const DonationConfig({this.enabled = false, this.url = ''});

  /// Shown only when explicitly enabled AND a URL is set.
  bool get isActive => enabled && url.isNotEmpty;
}

/// The app's donation configuration. Off until a URL is set — flipping this on
/// is the entire change needed to add the coffee link.
const DonationConfig kDonation = DonationConfig();
