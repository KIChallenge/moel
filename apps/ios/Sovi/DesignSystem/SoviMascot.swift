import SwiftUI

enum MascotExpression { case calm, listening, working, speaking, confirmation }

struct SoviMascot: View {
    var size: CGFloat = 200
    var expression: MascotExpression = .calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tilt: Double {
        switch expression {
        case .listening: -6
        case .working: 4
        case .confirmation: -3
        case .speaking: 2
        case .calm: 0
        }
    }

    var body: some View {
        Image("SoviLeaf")
            .renderingMode(.original).resizable().scaledToFit()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(reduceMotion ? 0 : tilt))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: expression)
            .accessibilityHidden(true)
    }
}
