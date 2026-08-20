import SwiftUI

/// L'alerte que voient les deux gestes exigeant un compte : proposer un lieu sur
/// la carte, et voter dans le volet Social.
///
/// Un seul endroit pour les deux, parce qu'ils butent sur la même condition et
/// doivent dire la même chose. Deux textes séparés divergeraient.
///
/// Ce qu'elle remplace : rien. Le bouton de proposition faisait un
/// `if authModel.userID != nil { … }` **sans `else`** — déconnecté, le menu se
/// refermait et il ne se passait rien. Ni alerte, ni explication, ni chemin.
///
/// Elle ouvre la feuille de connexion, et non plus l'onglet Profil : y basculer
/// laissait le geste refusé derrière soi et la connexion encore à trouver, au
/// bas d'une section des réglages.
///
/// Elle la présente ELLE-MÊME plutôt que de lever `AppModel.showsSignIn`. Ses
/// quatre points d'accroche ne sont pas au même étage : trois sont posés sur un
/// écran d'onglet (carte, Social), le quatrième sur `ContributionsPanel` quand
/// c'est `ProposalsSheet` qui le porte — donc déjà dans une feuille. Or
/// `RootView` n'en présente qu'une à la fois, et la seconde demande est perdue
/// en silence (mesuré au simulateur le 2026-08-19). Un modificateur ne peut pas
/// savoir où on l'a posé : il présente donc depuis là où il est, ce qui marche
/// dans les deux cas.
struct SignInToContributeAlert: ViewModifier {
    @Binding var isPresented: Bool
    @State private var showsSignIn = false

    func body(content: Content) -> some View {
        content
            .alert("community.signInToContribute.title", isPresented: $isPresented) {
                Button("community.signInToContribute.signIn") { showsSignIn = true }
                Button("profile.contribute.hint.cancel", role: .cancel) {}
            } message: {
                Text("community.signInToContribute.message")
            }
            .sheet(isPresented: $showsSignIn) { SignInSheet() }
    }
}

extension View {
    func signInToContributeAlert(isPresented: Binding<Bool>) -> some View {
        modifier(SignInToContributeAlert(isPresented: isPresented))
    }
}
