import UIKit
import XCTest
@testable import Murzik

/// Renders every `MurzikSprite` with the 3D renderer into `$RENDER_DIR/sprites/<rawValue>.png`
/// (192×192, transparent) and a review sheet into `$RENDER_DIR/3d/sprite-sheet.png`.
@MainActor
final class SpriteExportTests: XCTestCase {
    static var renderRoot: URL {
        let path = ProcessInfo.processInfo.environment["RENDER_DIR"]
        let url = path.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("murzik-renders")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func dir(_ name: String) -> URL {
        let url = renderRoot.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Alpha value (0...255) at a pixel.
    static func alpha(_ cg: CGImage, x: Int, y: Int) -> UInt8 {
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            }
        }
        return px[3]
    }

    func testExportAllSprites() throws {
        let renderer = try XCTUnwrap(MurzikSpriteRenderer(), "Metal unavailable")
        let start = Date()
        let images = renderer.renderAll()
        let sprites = SpriteExportTests.dir("sprites")
        for sprite in MurzikSprite.allCases {
            let image = try XCTUnwrap(images[sprite], "sprite not rendered: \(sprite.rawValue)")
            let cg = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cg.width, 192, sprite.rawValue)
            XCTAssertEqual(cg.height, 192, sprite.rawValue)
            // Transparent background, opaque cat.
            XCTAssertEqual(SpriteExportTests.alpha(cg, x: 1, y: 1), 0, "corner not transparent: \(sprite.rawValue)")
            XCTAssertEqual(SpriteExportTests.alpha(cg, x: 190, y: 1), 0, "corner not transparent: \(sprite.rawValue)")
            let bounds = try XCTUnwrap(MurzikSpriteRenderer.alphaBounds(cg), "empty sprite \(sprite.rawValue)")
            XCTAssertGreaterThan(bounds.width, 60, sprite.rawValue)
            XCTAssertGreaterThan(bounds.height, 50, sprite.rawValue)
            // Feet on the bottom edge (peek touches it).
            XCTAssertGreaterThan(bounds.maxY, 192 * 0.9, "not grounded: \(sprite.rawValue)")
            let data = try XCTUnwrap(image.pngData())
            try data.write(to: sprites.appendingPathComponent("\(sprite.rawValue).png"))
        }
        print("Rendered \(images.count) sprites in \(Date().timeIntervalSince(start)) s")
        try writeSheet(images)
    }

    func testSpritesAreDeterministic() throws {
        let renderer = try XCTUnwrap(MurzikSpriteRenderer())
        let a = try XCTUnwrap(renderer.render(.sitFront)?.pngData())
        _ = renderer.render(.surprised)
        let b = try XCTUnwrap(renderer.render(.sitFront)?.pngData())
        XCTAssertEqual(a.count, b.count, accuracy: a.count / 50)
    }

    // MARK: Sheet

    private func writeSheet(_ images: [MurzikSprite: UIImage]) throws {
        let all = MurzikSprite.allCases
        let cols = 7
        let cell: CGFloat = 200
        let labelH: CGFloat = 22
        let rows = Int(ceil(Double(all.count) / Double(cols)))
        let gridH = CGFloat(rows) * (cell + labelH)
        let islandH: CGFloat = 320
        let width = CGFloat(cols) * cell
        let height = 50 + gridH * 2 + islandH + 40
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let cream = UIColor(red: 0.98, green: 0.95, blue: 0.91, alpha: 1)
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            let c = ctx.cgContext
            UIColor(white: 0.16, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.white]
            ("3D Murzik sprites — 192 px, light / black / Dynamic Island sizes" as NSString)
                .draw(at: CGPoint(x: 16, y: 12), withAttributes: title)
            var y: CGFloat = 50
            for (bg, fg) in [(cream, UIColor.darkGray), (UIColor.black, UIColor.lightGray)] {
                bg.setFill()
                c.fill(CGRect(x: 0, y: y, width: width, height: gridH))
                let label: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: fg]
                for (i, s) in all.enumerated() {
                    let x = CGFloat(i % cols) * cell
                    let yy = y + CGFloat(i / cols) * (cell + labelH)
                    images[s]?.draw(in: CGRect(x: x + 4, y: yy + 4, width: 192, height: 192))
                    (s.rawValue.replacingOccurrences(of: "murzik_", with: "") as NSString)
                        .draw(at: CGPoint(x: x + 8, y: yy + cell), withAttributes: label)
                }
                y += gridH
            }
            // Dynamic Island rows: 36 pt at 1× and at 3× (108 px), on black capsules.
            y += 12
            let key: [MurzikSprite] = [.walk0, .walk3, .sitFront, .happy, .loving, .sleeping, .playful, .surprised, .excited, .peek]
            for size in [CGFloat(36), CGFloat(108)] {
                let row: [MurzikSprite] = size < 50 ? all : key
                let pad: CGFloat = size * 0.25
                let rowW = CGFloat(row.count) * (size + pad) + pad
                let scale = min(1, (width - 20) / rowW)
                let s = size * scale
                let p = pad * scale
                UIColor.black.setFill()
                UIBezierPath(roundedRect: CGRect(x: 10, y: y, width: width - 20, height: s + 2 * p),
                             cornerRadius: (s + 2 * p) / 2).fill()
                for (i, sp) in row.enumerated() {
                    images[sp]?.draw(in: CGRect(x: 10 + p + CGFloat(i) * (s + p), y: y + p, width: s, height: s))
                }
                y += s + 2 * p + 14
            }
        }
        let data = try XCTUnwrap(sheet.pngData())
        try data.write(to: SpriteExportTests.dir("3d").appendingPathComponent("sprite-sheet.png"))
    }
}
