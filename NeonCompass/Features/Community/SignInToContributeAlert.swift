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
struct SignInToContributeAlert: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("community.signInToContribute.title", isPresented: $isPresented) {
            Button("community.signInToContribute.openProfile") {
                appModel.selectedTab = .profile
            }
            Button("profile.contribute.hint.cancel", role: .cancel) {}
        } message: {
            Text("community.signInToContribute.message")
        }
    }
}

extension View {
    func signInToContributeAlert(isPresented: Binding<Bool>) -> some View {
        modifier(SignInToContributeAlert(isPresented: isPresented))
    }
}
