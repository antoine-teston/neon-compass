import AppTrackingTransparency
import Foundation
import Observation

/// Les portes d'entrée de l'app, dans l'ordre où Google les documente.
///
/// **Cet ordre était l'inverse.** L'implémentation d'origine demandait l'ATT
/// AVANT le formulaire RGPD, au premier lancement. Deux conséquences : on
/// brûlait l'unique demande ATT autorisée par installation sur des utilisateurs
/// qui refusaient le consentement trois secondes plus tard, et on la posait au
/// pire moment possible pour un opt-in — avant que l'utilisateur ait vu la
/// moindre valeur.
///
/// L'ordre retenu : disclaimer, puis UMP, puis — à la DEUXIÈME session
/// seulement, et uniquement si le consentement a été accordé — l'explication
/// maison puis la boîte système.
@Observable
@MainActor
final class OnboardingModel {
    private static let disclaimerKey = "hasAcceptedDisclaimer"
    private static let attPromptShownKey = "hasShownATTPrompt"
    private static let consentResolvedKey = "hasResolvedAdConsent"
    private static let consentGrantedKey = "adConsentGranted"
    private static let launchCountKey = "launchCount"

    private let defaults: UserDefaults
    private let consentProvider: ConsentProviding

    var needsDisclaimer: Bool
    private(set) var needsConsentPrompt: Bool
    private(set) var hasShownATTPrompt: Bool
    /// Persisté : à la deuxième session le formulaire n'est plus présenté, mais
    /// on doit encore savoir ce qu'il avait répondu.
    private(set) var consentGranted: Bool
    private(set) var launchCount: Int

    private var hasRegisteredLaunch = false
    private var isExplainerDeferred = false

    init(defaults: UserDefaults = .standard, consentProvider: ConsentProviding = UMPConsentProvider()) {
        self.defaults = defaults
        self.consentProvider = consentProvider
        needsDisclaimer = !defaults.bool(forKey: Self.disclaimerKey)
        needsConsentPrompt = !defaults.bool(forKey: Self.consentResolvedKey)
        hasShownATTPrompt = defaults.bool(forKey: Self.attPromptShownKey)
        consentGranted = defaults.bool(forKey: Self.consentGrantedKey)
        launchCount = defaults.integer(forKey: Self.launchCountKey)
    }

    /// Compte une session, une seule fois par processus.
    ///
    /// SwiftUI peut réévaluer l'expression initiale d'un `@State` et reconstruit
    /// `RootView` souvent : compter dans `init` gonflerait le total et
    /// avancerait la demande ATT au premier lancement, ce qui est exactement le
    /// défaut qu'on corrige. Le garde-fou est ici, pas chez l'appelant.
    func registerLaunch() {
        guard !hasRegisteredLaunch else { return }
        hasRegisteredLaunch = true
        let next = defaults.integer(forKey: Self.launchCountKey) + 1
        defaults.set(next, forKey: Self.launchCountKey)
        launchCount = next
    }

    func acceptDisclaimer() {
        defaults.set(true, forKey: Self.disclaimerKey)
        needsDisclaimer = false
    }

    /// Le booléen rendu par UMP n'est plus jeté.
    ///
    /// `ConsentProviding.requestConsent()` répond « peut-on demander des pubs ».
    /// L'implémentation d'origine l'écrasait avec `_ = try? await`, et c'est
    /// exactement le signal qui permet de ne pas présenter l'ATT après un refus
    /// RGPD. Un échec de lecture vaut un refus : on résout la porte pour ne pas
    /// bloquer l'app, sans accorder quoi que ce soit.
    func requestConsent() async {
        let granted = (try? await consentProvider.requestConsent()) ?? false
        defaults.set(granted, forKey: Self.consentGrantedKey)
        defaults.set(true, forKey: Self.consentResolvedKey)
        consentGranted = granted
        needsConsentPrompt = false
    }

    /// L'explication maison, et donc la boîte système, ne sont proposées qu'à
    /// partir de la deuxième session — quelqu'un qui revient a déjà jugé l'app
    /// utile et accepte bien plus volontiers.
    var needsTrackingExplainer: Bool {
        !hasShownATTPrompt
            && consentGranted
            && launchCount >= 2
            && !isExplainerDeferred
            && !needsDisclaimer
            && !needsConsentPrompt
    }

    /// « Plus tard » : on ne présente rien cette fois, et on redemandera au
    /// prochain lancement. Rien n'est persisté — refuser l'explication n'est pas
    /// refuser le suivi, et n'a donc pas à être définitif.
    func deferTrackingExplainer() {
        isExplainerDeferred = true
    }

    /// La boîte système d'Apple ne s'affiche qu'une fois par installation : un
    /// second appel rend le statut mémorisé, sans dialogue. Le drapeau persisté
    /// sert à ne pas re-proposer NOTRE écran, pas à contourner ce comportement.
    ///
    /// - Important: `requestTrackingAuthorization` échoue en silence si l'app
    ///   n'est pas active. L'appelant doit donc être un moment de premier plan —
    ///   ici, le bouton d'une feuille déjà présentée.
    func requestTrackingAuthorization() async {
        _ = await ATTrackingManager.requestTrackingAuthorization()
        defaults.set(true, forKey: Self.attPromptShownKey)
        hasShownATTPrompt = true
    }
}
