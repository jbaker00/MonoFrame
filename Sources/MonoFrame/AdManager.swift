import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI

// Debug builds use Google's published TEST ad units so development clicks
// never hit the real account (an AdMob policy violation). Release builds
// use the real units.
enum AdConfig {
    #if DEBUG
    static let bannerUnitID = "ca-app-pub-3940256099942544/2934735716"
    static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    static let bannerUnitID = "ca-app-pub-7871017136061682/1349245848"
    static let interstitialUnitID = "ca-app-pub-7871017136061682/2374552909"
    #endif
}

// Owns the ATT prompt and the Mobile Ads SDK lifecycle.
//
// ATT ordering rules that prevent the "prompt never shows" race:
// 1. requestTrackingAuthorization is only called from activate(), which the
//    app fires on scene-active transitions — never at launch/init, where the
//    prompt is silently dropped because the app isn't active yet.
// 2. If iOS still couldn't display the prompt (status stays .notDetermined),
//    we don't wedge: the next scene activation retries.
// 3. The Ads SDK is not started and no ad is requested until ATT is resolved,
//    so an ad request can never race the consent prompt.
@MainActor
final class AdsManager: NSObject, ObservableObject, GADFullScreenContentDelegate {

    /// True once ATT is resolved and the Ads SDK has started.
    @Published private(set) var isReady = false

    private var isStarting = false
    private var interstitial: GADInterstitialAd?

    // Frequency cap: never on the first send of a session, then at most one
    // interstitial per 3 minutes. Uncapped every-send interstitials are the
    // fastest way to get uninstalled; the banner earns continuously anyway.
    private var hasSkippedFirstSend = false
    private var lastInterstitialShownAt: Date?
    private static let interstitialCooldown: TimeInterval = 180

    /// Idempotent; call on every scene-active transition.
    func activate() {
        // Keeps ATT prompts and "Test Ad" banners out of App Store screenshots.
        guard !CommandLine.arguments.contains("-screenshots") else { return }
        guard !isReady, !isStarting else { return }
        isStarting = true
        Task {
            // Let the active-transition settle; requesting ATT in the same
            // runloop turn the scene becomes active is the classic way the
            // prompt gets dropped.
            try? await Task.sleep(nanoseconds: 400_000_000)

            var status = ATTrackingManager.trackingAuthorizationStatus
            if status == .notDetermined {
                status = await ATTrackingManager.requestTrackingAuthorization()
            }
            if status == .notDetermined {
                // Prompt could not be displayed (app went inactive, etc).
                // Bail out and let the next activation retry.
                isStarting = false
                return
            }

            GADMobileAds.sharedInstance().start(completionHandler: nil)
            isReady = true
            isStarting = false
            loadInterstitial()
        }
    }

    // MARK: - Interstitial

    private func loadInterstitial() {
        guard isReady else { return }
        GADInterstitialAd.load(withAdUnitID: AdConfig.interstitialUnitID,
                               request: GADRequest()) { [weak self] ad, error in
            if let error {
                print("Interstitial failed to load: \(error.localizedDescription)")
                return
            }
            ad?.fullScreenContentDelegate = self
            self?.interstitial = ad
        }
    }

    /// Presents the interstitial if one is ready; the caller's work (the
    /// upload) continues independently either way.
    func showInterstitial() {
        guard isReady else { return }
        if !hasSkippedFirstSend {
            hasSkippedFirstSend = true
            return
        }
        if let last = lastInterstitialShownAt,
           Date().timeIntervalSince(last) < Self.interstitialCooldown {
            return
        }
        guard let interstitial,
              let root = Self.rootViewController() else {
            loadInterstitial()
            return
        }
        interstitial.present(fromRootViewController: root)
        lastInterstitialShownAt = Date()
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in
            self.interstitial = nil
            self.loadInterstitial()   // preload the next one
        }
    }

    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

// MARK: - Banner

struct BannerAdView: UIViewRepresentable {
    let width: CGFloat

    func makeUIView(context: Context) -> GADBannerView {
        let size = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(max(width, 320))
        let banner = GADBannerView(adSize: size)
        banner.adUnitID = AdConfig.bannerUnitID
        banner.rootViewController = AdsManager.rootViewController()
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}

// Only mounted once AdsManager.isReady, so the banner's first ad request
// always happens after ATT is resolved.
struct BannerAdContainer: View {
    @EnvironmentObject private var ads: AdsManager

    var body: some View {
        if ads.isReady {
            GeometryReader { geo in
                BannerAdView(width: geo.size.width)
            }
            .frame(height: 60)
        }
    }
}
