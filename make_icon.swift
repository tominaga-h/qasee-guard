// 元画像を 1024x1024 の透明キャンバス中央に置き直す（macOSアイコンの余白に合わせる）
// 使い方: swift make_icon.swift <入力PNG> <出力PNG>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]),
      let srcRep = src.representations.first else {
    fputs("usage: make_icon.swift <in.png> <out.png>\n", stderr); exit(1)
}
let canvas = 1024
let body: CGFloat = 880 // 影込みの絵の大きさ（残りは透明の余白）
let w = CGFloat(srcRep.pixelsWide), h = CGFloat(srcRep.pixelsHigh)
let scale = body / max(w, h)
let dw = w * scale, dh = h * scale

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: canvas, height: canvas)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
src.draw(in: NSRect(x: (CGFloat(canvas) - dw) / 2, y: (CGFloat(canvas) - dh) / 2, width: dw, height: dh))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("ok")
