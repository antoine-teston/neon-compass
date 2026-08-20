import Testing
@testable import NeonCompass
import Foundation
import UIKit

/// Ce que ces tests protègent : un emplacement d'illustration se perd en
/// silence. `UIImage(named:)` rend `nil` sur un nom absent ou mal orthographié,
/// sans erreur ni avertissement de build, et l'écran se compose simplement sans
/// son image. Rien ne le signale — sauf ceci.
@MainActor
struct NCArtworkTests {
    @Test func everyArtworkResolvesInTheCatalogue() {
        for artwork in NCArtwork.allCases {
            #expect(
                UIImage(named: artwork.assetName) != nil,
                "illustration introuvable pour \(artwork) : \(artwork.assetName)"
            )
        }
    }

    /// Le catalogue est plat : deux emplacements qui porteraient le même nom
    /// d'asset pointeraient sur la même image sans que rien ne le dise.
    @Test func assetNamesAreDistinct() {
        let names = NCArtwork.allCases.map(\.assetName)
        #expect(Set(names).count == names.count, "noms d'asset en double : \(names)")
    }

    /// **Le test qui a une chance de tomber un jour.**
    ///
    /// L'interface est à `#0A081A`. Une illustration sortie du générateur est
    /// correctement exposée, donc lumineuse, et déposée telle quelle elle crève
    /// l'écran — c'est le motif de l'étape d'assombrissement du §6 de
    /// `docs/ops/2026-08-19-banque-images-prompts-et-themes-pro.md`. Rien
    /// n'empêche d'oublier cette étape ; ceci l'empêche.
    ///
    /// Le plafond est large exprès. Les gabarits en place mesurent ≈ 0,13, une
    /// vraie illustration étalonnée montera plus haut, et une image brute
    /// dépasse 0,5 — c'est cet écart-là qu'on attrape, pas dix centièmes.
    @Test func noArtworkIsBrightEnoughToBlowOutTheInterface() throws {
        for artwork in NCArtwork.allCases {
            let image = try #require(UIImage(named: artwork.assetName))
            let luminance = try #require(averageLuminance(of: image))
            #expect(
                luminance < 0.35,
                "\(artwork.assetName) est à \(luminance) de luminance moyenne : elle n'a pas reçu l'étalonnage du §6"
            )
        }
    }

    /// La moyenne de l'image entière, par réduction à un seul pixel.
    ///
    /// `CGContext` fait la moyenne des surfaces lui-même, ce qui évite de
    /// parcourir deux millions de pixels en Swift. `premultipliedLast` et non
    /// `noneSkipLast` : les gabarits sont opaques, mais une illustration future
    /// pourrait porter de l'alpha, et prémultiplier fait alors compter le
    /// transparent comme du noir — ce qui est bien ce qu'on veut mesurer,
    /// puisque le fond derrière est noir.
    private func averageLuminance(of image: UIImage) -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
