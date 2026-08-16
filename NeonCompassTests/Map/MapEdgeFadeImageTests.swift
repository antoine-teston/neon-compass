import Testing
import Foundation
import CoreGraphics
@testable import NeonCompass

/// L'image du fondu est un carré de neuf tranches : les quatre coins portent
/// la retombée en deux dimensions, les quatre bandes la portent en une seule
/// et sont constantes le long de leur longueur — condition pour que
/// `contentsCenter` puisse les étirer sur 2 048 points sans les déformer.
struct MapEdgeFadeImageTests {
    private static let band = 8
    private static let side = 2 * band + 2

    /// Rend l'octet alpha du pixel, ou nil si l'image n'a pas la forme attendue.
    private static func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8? {
        guard image.bitsPerPixel == 32, image.alphaInfo == .premultipliedLast,
              let provider = image.dataProvider?.data else { return nil }
        let data = provider as Data
        return data[y * image.bytesPerRow + x * 4 + 3]
    }

    private static func rgb(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8)? {
        guard let provider = image.dataProvider?.data else { return nil }
        let data = provider as Data
        let i = y * image.bytesPerRow + x * 4
        return (data[i], data[i + 1], data[i + 2])
    }

    @Test func theImageIsTwiceTheBandPlusTheStretchableCentre() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        #expect(image.width == Self.side)
        #expect(image.height == Self.side)
    }

    /// Opaque au bord, transparent au centre : les deux extrémités de la
    /// rampe. Sans la première, le bord de la carte resterait visible ; sans la
    /// seconde, le fondu couvrirait la carte entière d'un voile.
    @Test func theRampRunsFromOpaqueEdgeToTransparentCentre() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        #expect(Self.alpha(image, x: 0, y: 0) == 255)
        #expect(Self.alpha(image, x: 0, y: Self.side / 2) == 255)
        #expect(Self.alpha(image, x: Self.side / 2, y: Self.side / 2) == 0)
    }

    /// Au bord, la couleur est celle du fond de l'app et pas une autre : c'est
    /// tout l'objet du fondu, faire se rejoindre la carte et le vide.
    @Test func theOpaqueEdgeIsExactlyTheAppBackground() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        let channels = try #require(Self.rgb(image, x: 0, y: Self.side / 2))
        #expect(channels.0 == 10)
        #expect(channels.1 == 8)
        #expect(channels.2 == 26)
    }

    /// À mi-bande, à mi-chemin — le lissage de Hermite vaut 0,5 en son milieu
    /// comme une rampe linéaire, ce qui rend l'attendu vérifiable de tête.
    @Test func theRampIsHalfwayAtHalfTheBand() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        let a = try #require(Self.alpha(image, x: Self.band / 2, y: Self.side / 2))
        #expect(abs(Int(a) - 128) <= 2)
    }

    /// La propriété qui autorise `contentsCenter` : dans une bande, l'alpha ne
    /// dépend que de la distance au bord de CETTE bande. Sans elle, l'étirement
    /// du centre déformerait le dégradé.
    @Test func aBandIsConstantAlongItsLength() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        let reference = try #require(Self.alpha(image, x: 3, y: Self.band))
        for y in Self.band...(Self.side - 1 - Self.band) {
            #expect(Self.alpha(image, x: 3, y: y) == reference)
        }
    }

    /// Le rectangle étirable désigne les 2 px du centre, pas un de plus : y
    /// inclure un pixel de la rampe étirerait une valeur intermédiaire sur
    /// toute la carte.
    @Test func theStretchableRectIsTheTwoCentrePixels() {
        let rect = MapEdgeFadeImage.contentsCenter(bandPixels: Self.band)
        #expect(abs(rect.minX - 8.0 / 18.0) < 0.0001)
        #expect(abs(rect.minY - 8.0 / 18.0) < 0.0001)
        #expect(abs(rect.width - 2.0 / 18.0) < 0.0001)
        #expect(abs(rect.height - 2.0 / 18.0) < 0.0001)
    }

    /// L'épaisseur en pixels suit l'appareil, pour que 80 points d'écran en
    /// fassent toujours 80.
    @Test func theBandInPixelsFollowsTheDevice() {
        #expect(MapEdgeFadeImage.band == 80)
        #expect(MapEdgeFadeImage.bandPixels(displayScale: 2) == 160)
        #expect(MapEdgeFadeImage.bandPixels(displayScale: 3) == 240)
        #expect(MapEdgeFadeImage.bandPixels(displayScale: 0) == 80)
    }

    @Test func aZeroBandYieldsNoImageRatherThanACrash() {
        #expect(MapEdgeFadeImage.make(bandPixels: 0, color: NCColor.nightSkyRGBA) == nil)
    }
}
