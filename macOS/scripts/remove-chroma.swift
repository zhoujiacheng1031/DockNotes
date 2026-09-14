#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 4,
      let targetSize = Int(CommandLine.arguments[3]),
      targetSize > 0 else {
    fputs("usage: remove-chroma.swift <input.png> <output.png> <size>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = NSImage(contentsOf: inputURL),
      let sourceImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("could not create bitmap\n", stderr)
    exit(1)
}

let bytesPerRow = targetSize * 4
let allocation = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow * targetSize, alignment: 16)
defer { allocation.deallocate() }

guard let context = CGContext(
    data: allocation,
    width: targetSize,
    height: targetSize,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
) else {
    fputs("could not create drawing context\n", stderr)
    exit(1)
}

context.interpolationQuality = .high
context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
let pixels = allocation.bindMemory(to: UInt8.self, capacity: bytesPerRow * targetSize)

// The generated source uses #00FF00 as a chroma matte. Recover the foreground
// colour as well as alpha so antialiased edges do not retain a green halo.
for y in 0..<targetSize {
    for x in 0..<targetSize {
        let offset = y * bytesPerRow + x * 4
        let red = Double(pixels[offset]) / 255
        let green = Double(pixels[offset + 1]) / 255
        let blue = Double(pixels[offset + 2]) / 255
        let distance = max(red, 1 - green, blue)
        // Image generation introduces a small variation across the nominally
        // flat matte. Treat that variation as background before feathering.
        let matteNoiseFloor = 0.075
        let alpha = min(1, max(0, (distance - matteNoiseFloor) / (1 - matteNoiseFloor)))

        guard alpha > 0.001 else {
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
            continue
        }

        let recoveredRed = red / alpha
        let recoveredGreen = (green - (1 - alpha)) / alpha
        let recoveredBlue = blue / alpha
        // The CGContext uses premultiplied-last RGBA bytes.
        pixels[offset] = UInt8((min(1, max(0, recoveredRed)) * alpha * 255).rounded())
        pixels[offset + 1] = UInt8((min(1, max(0, recoveredGreen)) * alpha * 255).rounded())
        pixels[offset + 2] = UInt8((min(1, max(0, recoveredBlue)) * alpha * 255).rounded())
        pixels[offset + 3] = UInt8((alpha * 255).rounded())
    }
}

guard let outputImage = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: outputImage).representation(using: .png, properties: [:]) else {
    fputs("could not encode png\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
