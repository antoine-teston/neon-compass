import SwiftUI

struct PlaceholderScreen: View {
    let tab: AppTab

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(NCColor.sunset)
                Text(tab.titleKey)
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
            }
        }
    }
}
