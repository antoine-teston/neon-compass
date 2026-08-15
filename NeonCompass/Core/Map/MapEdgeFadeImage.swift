import CoreGraphics
import Foundation

/// L'image du fondu des bords : un carré dont les `band` pixels de pourtour
/// passent de la couleur du fond au transparent, et dont le centre — 2 px —
/// est entièrement transparent.
///
/// Pourquoi une image et non quatre dégradés posés à la main : `contentsCenter`
/// étire ces 2 px sur toute la surface du calque, donc une image de quelques
/// centaines de kilo-octets habille une carte de 2 048 points de côté, et les
/// quatre coins sont peints une fois pour toutes plutôt que raccordés.
///
/// Pourquoi pas dans les PNG des socles : l'épaisseur est en points d'ÉCRAN.
/// Cuite dans l'image, elle vaudrait 16 points de contenu au zoom maximal et
/// 187 au repos — le fondu grossirait avec la carte, ce qui est exactement ce
/// qu'on ne veut pas.
enum MapEdgeFadeImage {
    /// L'épaisseur du fondu, en points d'écran.
    static let band: CGFloat = 80

    /// La même, en pixels de l'appareil — l'épaisseur à graver.
    static func bandPixels(displayScale: CGFloat) -> Int {
        Int((band * max(displayScale, 1)).rounded())
    }

    /// Le rectangle étirable, en coordonnées unitaires — à poser sur
    /// `CALayer.contentsCenter`. Il désigne les 2 px du centre, pas un de
    /// plus : y inclure un pixel de la rampe étirerait une valeur
    /// intermédiaire sur toute la carte.
    static func contentsCenter(bandPixels: Int) -> CGRect {
        let side = CGFloat(2 * bandPixels + 2)
        return CGRect(
            x: CGFloat(bandPixels) / side, y: CGFloat(bandPixels) / side,
            width: 2 / side, height: 2 / side
        )
    }

    /// - Parameter bandPixels: l'épaisseur de la bande, en pixels de l'image.
    static func make(bandPixels: Int, color: NCColor.RGBA) -> CGImage? {
        guard bandPixels > 0 else { return nil }
        let side = 2 * bandPixels + 2
        let band = Double(bandPixels)
        let red = min(max(color.red, 0), 1) * 255
        let green = min(max(color.green, 0), 1) * 255
        let blue = min(max(color.blue, 0), 1) * 255
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            let dy = Double(min(y, side - 1 - y))
            for x in 0..<side {
                // Distance au bord le plus proche : le minimum sur les deux
                // axes. Ce choix laisse chaque bande constante le long de sa
                // longueur — condition de `contentsCenter` — et chanfreine les
                // coins, ce qui ne se distingue pas d'un coin radial à cette
                // échelle.
                let dx = Double(min(x, side - 1 - x))
                let t = min(min(dx, dy) / band, 1)
                // Lissage de Hermite : une rampe linéaire laisse une arête
                // visible là où le fondu s'arrête, les dérivées nulles aux deux
                // bouts l'effacent. Vaut 0,5 en son milieu comme la linéaire.
                let alpha = 1 - t * t * (3 - 2 * t)
                let i = (y * side + x) * 4
                // Prémultiplié : les canaux portent déjà le facteur alpha.
                pixels[i] = UInt8((red * alpha).rounded())
                pixels[i + 1] = UInt8((green * alpha).rounded())
                pixels[i + 2] = UInt8((blue * alpha).rounded())
                pixels[i + 3] = UInt8((255 * alpha).rounded())
            }
        }
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            // `makeImage` prend une copie du tampon, donc l'image survit à la
            // portée du pointeur.
            return context.makeImage()
        }
    }
}
