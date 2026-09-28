import AppKit
import Foundation

// Run against --render-deck-preview with 7 visible tabs, 900 pt of height,
// and 8 notes. The middle of the second tab must not leave a second,
// translucent silhouette outside its actual paper-shaped hit target.
guard CommandLine.arguments.count == 2,
      let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))),
      bitmap.pixelsWide == 120,
      bitmap.pixelsHigh == 1800,
      let outside = bitmap.colorAt(x: 14, y: 300)?.usingColorSpace(.deviceRGB),
      let inside = bitmap.colorAt(x: 30, y: 300)?.usingColorSpace(.deviceRGB) else {
    fatalError("Expected a 120 × 1800 deck preview")
}

print(String(format: "outside alpha %.3f, inside alpha %.3f", outside.alphaComponent, inside.alphaComponent))
guard inside.alphaComponent > 0.90, outside.alphaComponent < 0.30 else {
    fputs("Deck tab has a duplicate glass silhouette outside its edge\n", stderr)
    exit(1)
}
print("Deck glass silhouette passed")
