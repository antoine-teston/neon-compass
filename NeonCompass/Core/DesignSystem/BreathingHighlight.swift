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

    /// La teinte de la lueur. Le violet par défaut, et il reste RÉSERVÉ au jeu à
    /// venir : c'est ce qui fait de cette respiration un signal et non une
    /// décoration. Le second usage, l'orange des favoris, est admis pour deux
    /// raisons — il ne nomme aucun jeu, donc il n'entre pas en concurrence de
    /// sens ; et il défile avec la liste, donc il ne consomme pas en permanence
    /// l'un des trois accents lumineux que `CLAUDE.md` autorise par écran.
    var tint: Color = NCColor.sunsetViolet

    /// Une animation qui ne s'arrête jamais est exactement ce que ce réglage
    /// vise. Coupée, la vue garde son état haut plutôt que de retomber au creux
    /// de la respiration — sinon l'élément paraîtrait éteint.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isLit = false

    private var breathes: Bool { isActive && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(breathes ? (isLit ? 1 : 0.58) : 1)
            // Une pastille qui enfle très légèrement au sommet de la
            // respiration. Six pour cent sur trente points, c'est deux points :
            // assez pour que l'œil le prenne pour de la lumière, trop peu pour
            // qu'il le lise comme un mouvement. `scaleEffect` ne touche pas la
            // mise en page, donc rien ne bouge autour.
            .scaleEffect(breathes && isLit ? 1.06 : 1)
            // TROIS halos et non un seul : un rayon court donne le cœur dense
            // qui fait lire la couleur, les deux plus larges donnent la
            // diffusion qui la fait rayonner. Empilés, ils accentuent sans
            // forcer l'opacité d'un halo unique — poussée seule, celle-ci grise
            // le fond au lieu de l'éclairer, et devient sale bien avant d'être
            // lumineuse.
            .shadow(color: tint.opacity(coreGlow), radius: breathes && isLit ? 4 : 2)
            .shadow(color: tint.opacity(coreGlow), radius: breathes && isLit ? 10 : 4)
            .shadow(color: tint.opacity(haloGlow), radius: breathes && isLit ? 22 : 6)
            .onAppear {
                guard breathes else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    isLit = true
                }
            }
    }

    private var coreGlow: Double {
        guard isActive else { return 0 }
        guard breathes else { return 0.75 }
        return isLit ? 1 : 0.3
    }

    private var haloGlow: Double {
        guard isActive else { return 0 }
        guard breathes else { return 0.45 }
        return isLit ? 0.85 : 0.12
    }
}

extension View {
    /// Fait respirer cet élément s'il nomme le jeu à venir.
    ///
    /// À poser APRÈS le fond de l'élément — capsule, cercle — pour que la lueur
    /// entoure la pastille entière et non le seul tracé des lettres.
    func breathingHighlight(
        _ isActive: Bool = true,
        tint: Color = NCColor.sunsetViolet
    ) -> some View {
        modifier(BreathingHighlight(isActive: isActive, tint: tint))
    }
}
