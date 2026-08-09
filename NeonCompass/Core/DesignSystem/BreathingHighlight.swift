import SwiftUI

/// La respiration des références au jeu à venir.
///
/// Une lueur violette qui monte et redescend sans fin, sur les seuls éléments
/// qui nomment le jeu attendu — jamais sur celui déjà sorti, dont la mention est
/// une aide au repérage et non une promesse.
///
/// **Le violet, et pas le cyan.** Au comptage du 8 août 2026 rapporté dans
/// `NCColor.neonCyan`, le cyan pesait 60 des 94 accents de l'app et le violet
/// **1** — le dégradé `sunset`, cœur synthwave de la palette, ne servait presque
/// nulle part. C'est donc la teinte la plus disponible, et la seule qui
/// n'entre en concurrence ni avec le cyan (rubriques, onglet actif, progression)
/// ni avec le magenta (repère de nouveauté, bouton de la carte).
///
/// **Le coût est mesuré, pas supposé.** Sonde `CADisplayLink` sur iPhone 17,
/// l'effet posé sur tous les emplacements à la fois : zéro image perdue au repos
/// comme sans effet, et quatorze au défilement contre quinze sans. Le
/// `LazyVStack` ne rend que les cartes visibles — cinq ou six, jamais
/// quarante-six — donc « partout » ne fait jamais plus d'une poignée
/// d'animations simultanées.
struct BreathingHighlight: ViewModifier {
    /// Coupe l'effet là où le contenu ne parle pas du jeu à venir.
    var isActive: Bool = true

    /// Une animation qui ne s'arrête jamais est exactement ce que ce réglage
    /// vise. Coupée, la vue garde son état haut plutôt que de retomber au creux
    /// de la respiration — sinon l'élément paraîtrait éteint.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isLit = false

    private var breathes: Bool { isActive && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(breathes ? (isLit ? 1 : 0.82) : 1)
            .shadow(
                color: NCColor.sunsetViolet.opacity(glowOpacity),
                radius: breathes && isLit ? 8 : 3
            )
            .onAppear {
                guard breathes else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    isLit = true
                }
            }
    }

    private var glowOpacity: Double {
        guard isActive else { return 0 }
        guard breathes else { return 0.55 }
        return isLit ? 0.9 : 0.2
    }
}

extension View {
    /// Fait respirer cet élément s'il nomme le jeu à venir.
    ///
    /// À poser APRÈS le fond de l'élément — capsule, cercle — pour que la lueur
    /// entoure la pastille entière et non le seul tracé des lettres.
    func breathingHighlight(_ isActive: Bool = true) -> some View {
        modifier(BreathingHighlight(isActive: isActive))
    }
}
