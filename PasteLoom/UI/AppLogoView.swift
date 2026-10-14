import AppKit
import SwiftUI

/// PasteLoom 品牌几何 P Glyph 形状 (Concept C: Clay · Ink · Paper)
public struct ConceptCGlyphShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let x0 = rect.minX
        let y0 = rect.minY
        let w = rect.width
        let h = rect.height

        let stemW = w * 0.240
        let topY = y0
        let stemBottomY = y0 + h
        let tabBottomY = y0 + h * 0.760
        let midBottomY = y0 + h * 0.680
        let notchLeftX = x0 + w * 0.475
        let rightX = x0 + w

        // Outer boundary
        path.move(to: CGPoint(x: x0, y: stemBottomY))
        path.addLine(to: CGPoint(x: x0, y: topY))
        path.addLine(to: CGPoint(x: x0 + w * 0.46, y: topY))
        path.addCurve(
            to: CGPoint(x: rightX, y: topY + h * 0.42),
            control1: CGPoint(x: x0 + w * 0.82, y: topY),
            control2: CGPoint(x: rightX, y: topY + h * 0.16)
        )
        path.addLine(to: CGPoint(x: rightX, y: tabBottomY))
        path.addLine(to: CGPoint(x: notchLeftX, y: tabBottomY))
        path.addLine(to: CGPoint(x: notchLeftX, y: midBottomY))
        path.addLine(to: CGPoint(x: x0 + stemW, y: midBottomY))
        path.addLine(to: CGPoint(x: x0 + stemW, y: stemBottomY))
        path.closeSubpath()

        // Inner counter (hole of P)
        let holeLeft = x0 + stemW
        let holeTop = topY + h * 0.220
        let holeBottom = topY + h * 0.540
        let holeRight = x0 + w * 0.760
        let holeRadius = (holeBottom - holeTop) * 0.45

        var holePath = Path()
        holePath.move(to: CGPoint(x: holeLeft, y: holeTop))
        holePath.addLine(to: CGPoint(x: holeRight - holeRadius, y: holeTop))
        holePath.addArc(
            tangent1End: CGPoint(x: holeRight, y: holeTop),
            tangent2End: CGPoint(x: holeRight, y: holeBottom),
            radius: holeRadius
        )
        holePath.addArc(
            tangent1End: CGPoint(x: holeRight, y: holeBottom),
            tangent2End: CGPoint(x: holeLeft, y: holeBottom),
            radius: holeRadius
        )
        holePath.addLine(to: CGPoint(x: holeLeft, y: holeBottom))
        holePath.closeSubpath()

        path.addPath(holePath)
        return path
    }
}

/// PasteLoom 品牌 Logo 视图组件
/// 提供品牌主程序与设置界面的高清晰度矢量与原生 PasteLoom 图标呈现
struct AppLogoView: View {
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 8
    var showShadow: Bool = false
    var isStandaloneClay: Bool = false

    var body: some View {
        Group {
            if isStandaloneClay {
                // 单独 Clay 符号模式
                ConceptCGlyphShape()
                    .fill(Color(red: 0.737, green: 0.396, blue: 0.318), style: FillStyle(eoFill: true))
                    .frame(width: size * 0.897, height: size)
            } else if let iconImg = NSImage(named: "PasteLoom") ?? (Bundle.main.url(forResource: "PasteLoom", withExtension: "png").flatMap { NSImage(contentsOf: $0) }) {
                Image(nsImage: iconImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .shadow(color: showShadow ? Color.black.opacity(0.18) : Color.clear, radius: showShadow ? 4 : 0, y: 1.5)
            } else {
                // macOS Ink 容器 + Paper 白色符号
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.145, green: 0.165, blue: 0.188),
                                    Color(red: 0.114, green: 0.133, blue: 0.153)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    ConceptCGlyphShape()
                        .fill(Color(red: 0.973, green: 0.961, blue: 0.937), style: FillStyle(eoFill: true))
                        .frame(width: size * 0.65 * 0.897, height: size * 0.65)
                        .shadow(color: Color.black.opacity(0.20), radius: size * 0.03, y: size * 0.015)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: showShadow ? Color.black.opacity(0.18) : Color.clear, radius: showShadow ? 4 : 0, y: 1.5)
            }
        }
    }
}
