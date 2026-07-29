import SwiftUI
import UIKit
@preconcurrency import GoogleMobileAds

/// Bannière adaptative — jamais sur MapScreen (Global Constraints de ce
/// plan). N'appelle jamais MobileAds.shared.start() elle-même.
///
/// API surface verified 2026-07-23 against the actually-resolved
/// GoogleMobileAds SDK headers (v13.7.0, same xcframework Task 4 inspected)
/// in `GADBannerView.h` / `GADAdSize.h`, not transcribed from the plan's
/// guessed sketch:
/// - `GADBannerView` carries `NS_SWIFT_NAME(BannerView)` — confirmed.
/// - `GADRequest` carries `NS_SWIFT_NAME(Request)`, no `NS_UNAVAILABLE` on a
///   plain `init` — `Request()` compiles, same finding as Task 4's
///   `AdMobInterstitialProvider`.
/// - `-loadRequest:` has no `NS_SWIFT_NAME` override, so the Clang importer
///   drops the `Request` suffix (it matches the parameter type name),
///   producing `func load(_ request: Request?)` in Swift — this is why
///   `banner.load(Request())` below compiles; it is NOT the completion-based
///   `load(with:)` used by `AdMobInterstitialProvider`, a different method.
/// - The plan's sketch called `currentOrientationAnchoredAdaptiveBanner(width:)`
///   (`GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth`), but that
///   C function is marked `GAD_DEPRECATED_MSG_REPLACEMENT_ATTRIBUTE` in this
///   resolved version, replaced by
///   `GADLargeAnchoredAdaptiveBannerAdSizeWithWidth` /
///   `largeAnchoredAdaptiveBanner(width:)`. Used the non-deprecated call
///   here to avoid a build warning; behavior is equivalent (still orientation-
///   aware, still returns the standard ~50-150pt anchored adaptive height).
/// - `UIViewRepresentable` itself is declared
///   `@preconcurrency @MainActor public protocol UIViewRepresentable` in
///   SwiftUI's resolved swiftinterface (confirmed via
///   `SwiftUI.swiftmodule/*.swiftinterface`), so conforming
///   `makeUIView`/`updateUIView` are already MainActor-isolated by the
///   protocol itself — no extra `@MainActor` annotation is needed here,
///   unlike `AdMobInterstitialProvider`'s manually-isolated members (that
///   type doesn't conform to a MainActor-isolated protocol).
///
/// Sizing note: `BannerAdView` self-sizes to the REAL adaptive-banner height
/// Google computes for its own available width, rather than a caller-guessed
/// fixed height — a caller wrapping this in a fixed-height container (as the
/// first UI-polish round did) risks clipping or leaving dead space whenever
/// the actual ad format is taller/shorter than the guess. Width is measured
/// via a `.background`-attached `GeometryReader` rather than making this
/// view's own body a `GeometryReader` — the latter greedily expands to fill
/// all available height in its container (a well-known SwiftUI pitfall),
/// which is exactly wrong for a view meant to report its OWN natural height
/// back to the caller.
///
/// Verified-by-running correction to the original plan sketch: the
/// conditional content MUST have a real `else` branch (`Color.clear` below),
/// not just `if measuredWidth > 0 { ... }` with no `else`. Empirically
/// confirmed on-device (iOS 26.5 Simulator) that when a `Group`'s ViewBuilder
/// content resolves to the "false" case of an `if` with no `else`, SwiftUI
/// never lays out or composites a `.background(GeometryReader { ... })`
/// attached to that group — the `GeometryReader`'s closure is never even
/// invoked, so its `onAppear`/`onChange` never fire and `measuredWidth` can
/// never leave its initial 0, permanently hiding the ad. Isolated with a
/// minimal repro (`Group { if x { Color.blue } }` vs. the same with
/// `else { Color.clear }`) — only the `else` version's `GeometryReader`
/// closure ever ran. Giving the `Group` a real view in both branches sidesteps
/// this: the `.background` now always has concrete content to size against,
/// so the `GeometryReader` reliably measures width from the first render.
struct BannerAdView: View {
    var adUnitID: String = "ca-app-pub-3940256099942544/2934735716" // AdMob's public test adaptive-banner ID — replace once provisioned.

    /// Plafond demandé pour CETTE instance. Par défaut `maxAdHeight`, la valeur
    /// calibrée pour une bannière ancrée.
    ///
    /// Paramétrable parce qu'un encart intercalé dans une liste de cartes n'a
    /// pas les mêmes contraintes qu'une bande ancrée en bas d'écran : il doit
    /// avoir le gabarit d'une carte, sinon il casse le rythme de la colonne.
    /// N'y mettre que des hauteurs de créative STANDARD (50, 100, 250) — voir
    /// la note sur le liseré dans `maxAdHeight`.
    var maxHeight: CGFloat = BannerAdView.maxAdHeight

    @State private var measuredWidth: CGFloat = 0

    /// Plafond de hauteur de l'emplacement, et **taille demandée à AdMob**.
    ///
    /// Historique : cette valeur était à 150, la borne haute documentée d'un
    /// anchored adaptive banner, et le format demandé était
    /// `largeAnchoredAdaptiveBanner` — qui sert ~100 pt sur iPhone. Vérifié en
    /// simulateur : la créative de test rendue est un 320×100. Sur un écran de
    /// 874 pt, l'encart occupait ~14 % de la hauteur, et les listes en
    /// réservaient 150 (plus la garde de tab bar) : le quart de l'écran
    /// soustrait au contenu en permanence, pour une annonce plus petite que la
    /// réservation.
    ///
    /// Le SDK 13.7 a déprécié les fonctions anchored adaptive *standard* au
    /// profit des variantes `Large...` (`GADAdSize.h:189`), il n'y a donc pas de
    /// « anchored adaptive court » non déprécié à demander. On passe à
    /// `inlineAdaptiveBanner(width:maxHeight:)`, qui n'est pas déprécié et qui
    /// prend un plafond explicite : on garde un format adaptatif pleine largeur
    /// (bien mieux rémunéré que le 320×50 fixe hérité, et correct sur iPad) tout
    /// en choisissant sa hauteur.
    ///
    /// 50 pt, et pas 60 : un plafond plus haut que la créative servie la laisse
    /// centrée dans son emplacement, avec un liseré noir au-dessus et en
    /// dessous — vérifié en simulateur à 60. Un inline adaptive ne rend jamais
    /// plus haut que son plafond, donc caler le plafond sur la hauteur standard
    /// supprime le liseré sans rien rogner.
    static let maxAdHeight: CGFloat = 50

    /// Plafond d'un encart intercalé dans une liste de cartes.
    ///
    /// 100 et pas 120 — qui collerait pourtant de plus près à la hauteur d'une
    /// carte du fil (~150 pt, marges comprises) — pour la raison exposée
    /// au-dessus : un plafond qui ne correspond à AUCUNE hauteur de créative
    /// standard laisse l'annonce centrée entre deux liserés noirs. 100 est une
    /// hauteur servie telle quelle (320×100), donc l'emplacement est rempli
    /// exactement. Les 14 pt de marge de l'encart complètent le reste, et
    /// l'ensemble tombe à ~128 pt : assez proche d'une carte pour que la
    /// colonne garde son rythme, sans bande noire pour l'annoncer.
    static let cardSlotHeight: CGFloat = 100

    /// Espace qu'un écran hôte doit réserver sous son contenu : la hauteur
    /// maximale de l'annonce plus le `padding(12)` de la bulle de verre qui
    /// l'entoure.
    ///
    /// Exposé pour que les écrans cessent de deviner. La constante de 150 qu'ils
    /// portaient en dur se décrivait elle-même comme « une estimation haute
    /// délibérément conservatrice, pas une mesure » — et elle était fausse de
    /// 50 pt. Ici la valeur ne peut pas dériver : c'est celle qu'on demande et
    /// celle qu'on clampe.
    static let reservedHeight: CGFloat = maxAdHeight + 24

    /// Hauteur réellement occupée une fois la largeur connue, clampée pour
    /// qu'une créative qui se gonflerait ne dicte pas la mise en page. Observé
    /// concrètement sur le simulateur iOS 26.5 avec les créatives de *test* :
    /// une demande 346×108 revient, sur `didReceiveAd`, avec la `BannerView`
    /// redimensionnée d'elle-même au double (692×216) et annonçant cette taille
    /// comme `intrinsicContentSize`. Sans épinglage, SwiftUI l'honore : l'annonce
    /// déborde, dépasse les marges horizontales et peint par-dessus la tab bar.
    ///
    /// Tant que la largeur est en cours de mesure, on réserve `maxAdHeight`
    /// plutôt que de laisser le remplaçant être vertialement gourmand (un
    /// `Color.clear` nu s'étend à tout ce que le conteneur offre — dans le
    /// `ZStack` aligné en bas de Feed/Cheats, c'est l'écran entier).
    private var slotHeight: CGFloat {
        guard measuredWidth > 0 else { return maxHeight }
        return min(inlineAdaptiveBanner(width: measuredWidth, maxHeight: maxHeight).size.height, maxHeight)
    }

    var body: some View {
        Group {
            if measuredWidth > 0 {
                BannerAdRepresentable(adUnitID: adUnitID, width: measuredWidth, height: slotHeight, maxHeight: maxHeight)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: slotHeight)
        // Belt-and-suspenders: even with the representable's layout size pinned
        // below, the underlying UIKit `BannerView` can still *draw* a creative
        // larger than the slot; clip so nothing escapes the reserved rectangle.
        .clipped()
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        if newValue > 0 { measuredWidth = newValue }
                    }
            }
        )
    }
}

private struct BannerAdRepresentable: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat
    let height: CGFloat

    /// Plafond réellement DEMANDÉ à AdMob. Il vivait ici en dur sur
    /// `BannerAdView.maxAdHeight`, si bien qu'un appelant demandant un
    /// emplacement plus haut réservait la place sans jamais demander l'annonce
    /// qui va avec : l'emplacement faisait 100, la requête 50. Ça ne se voyait
    /// pas parce que la créative de test servie mesure 320×100 quoi qu'on
    /// demande — un vrai inventaire aurait rempli la moitié de l'encart.
    let maxHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Tracks the width we last requested an ad for, so `updateUIView` can tell
    /// a real width change (rotation / resize) apart from the SDK having
    /// mutated `adSize` to the loaded creative's own (possibly inflated) size.
    /// Comparing against `uiView.adSize` instead would re-request on every
    /// update once a test creative reports a doubled size.
    final class Coordinator: NSObject {
        var requestedWidth: CGFloat = 0
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: inlineAdaptiveBanner(width: width > 0 ? width : UIScreen.main.bounds.width, maxHeight: maxHeight))
        banner.adUnitID = adUnitID
        banner.rootViewController = AdPresentationContext.topViewController()
        // Fond transparent, et pas le noir par défaut d'`UIView`.
        //
        // Une créative ne remplit pas toujours l'emplacement adaptatif : la
        // créative de test fait 320 de large quelle que soit la largeur
        // demandée, ce qui laissait deux bandes NOIRES sur les côtés dans
        // l'encart du fil — un rectangle noir au milieu d'une colonne de cartes
        // en verre. Transparent, l'espace non couvert laisse voir le verre de
        // l'encart au lieu de le trouer.
        banner.backgroundColor = .clear
        banner.load(Request())
        context.coordinator.requestedWidth = width
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // Re-adapt when the available width actually changes (rotation,
        // iPad Split View resize, sidebar collapse/expand) — this also
        // closes a second, related gap the same review flagged: the
        // previous updateUIView was a no-op, so the banner never
        // re-adapted after creation.
        guard width > 0, width != context.coordinator.requestedWidth else { return }
        uiView.adSize = inlineAdaptiveBanner(width: width, maxHeight: maxHeight)
        uiView.load(Request())
        context.coordinator.requestedWidth = width
    }

    // Pin the SwiftUI layout size to the *requested* adaptive slot. Without
    // this, SwiftUI sizes the representable from the UIKit view's
    // `intrinsicContentSize`, which the loaded creative can inflate well beyond
    // the requested banner size — the direct cause of the overflow regression.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BannerView, context: Context) -> CGSize? {
        CGSize(width: width, height: height)
    }
}
