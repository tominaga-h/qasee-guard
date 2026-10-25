// メニューバー用のQaseeGuardシンボル（menubar-symbol.svg のパスをそのまま描画）
import AppKit

private let symbolViewBox = NSSize(width: 994.698, height: 1024)

private let symbolPaths = [
    "M 905.953 780.895 C 906.215 787.778 905.966 794.67 905.209 801.516 L 873.843 770.15 C 1014.394 576.176 984.564 307.163 804.932 148.692 C 625.3 -9.778 354.667 -5.832 179.732 157.808 C 4.797 321.447 -17.178 591.216 128.967 781.01 C 275.113 970.804 541.539 1018.498 744.45 891.189 L 773.738 925.404 C 766.368 925.778 758.981 925.566 751.645 924.771 C 533.232 1054.716 251.987 999.089 99.488 795.782 C -53.011 592.476 -27.699 306.902 158.182 133.588 C 344.064 -39.726 630.708 -45.017 822.859 121.318 C 1015.011 287.654 1050.845 572.099 905.953 780.895 Z",
    "M 850.386 746.692 L 714.344 610.651 C 769.686 504.661 740.362 374.2 644.987 302.087 C 549.613 229.974 416.098 237.312 329.201 319.442 C 242.304 401.573 227.453 534.462 294.077 633.749 C 360.701 733.035 489.302 769.665 598.242 720.385 L 722.916 866.032 C 533.791 981.741 287.785 935.581 153.472 759.181 C 19.159 582.781 40.105 333.359 201.957 181.831 C 363.81 30.303 614.069 25.819 781.246 171.451 C 948.423 317.083 978.292 565.594 850.386 746.692 Z",
    "M 631.805 569.318 L 899.138 836.651 C 948.551 886.063 974.49 954.238 970.421 1024 C 913.834 1014.478 862.391 985.379 825.075 941.787 L 564.153 636.97 L 631.805 569.318 Z",
]

/// SVGのパス文字列（M / L / C / Z、絶対座標のみ）を NSBezierPath にする
private func bezierPath(fromSVG d: String) -> NSBezierPath {
    let path = NSBezierPath()
    let tokens = d.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
    var i = 0
    var cmd = ""
    func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
    while i < tokens.count {
        let t = tokens[i]
        if ["M", "L", "C", "Z"].contains(t) {
            cmd = t
            i += 1
            if t == "Z" { path.close(); continue }
        }
        switch cmd {
        case "M":
            path.move(to: NSPoint(x: num(), y: num()))
            cmd = "L" // M のあとに続く座標は L 扱い
        case "L":
            path.line(to: NSPoint(x: num(), y: num()))
        case "C":
            let c1 = NSPoint(x: num(), y: num())
            let c2 = NSPoint(x: num(), y: num())
            let p = NSPoint(x: num(), y: num())
            path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
        default:
            i += 1
        }
    }
    path.windingRule = .evenOdd
    return path
}

/// メニューバー用のテンプレート画像（明るい/暗いメニューバーに合わせて自動で色が変わる）
func makeMenuBarSymbol(height: CGFloat = 16) -> NSImage {
    let size = NSSize(width: height * symbolViewBox.width / symbolViewBox.height, height: height)
    let image = NSImage(size: size, flipped: true) { rect in
        let scale = rect.height / symbolViewBox.height
        var t = AffineTransform()
        t.scale(scale)
        NSColor.black.setFill()
        for d in symbolPaths {
            let p = bezierPath(fromSVG: d)
            p.transform(using: t)
            p.fill()
        }
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "QaseeGuard"
    return image
}
