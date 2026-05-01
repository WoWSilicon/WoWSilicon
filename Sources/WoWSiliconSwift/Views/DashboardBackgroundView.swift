import SwiftUI

struct DashboardBackgroundView: View {
    
    @State var isAnimating = false
    
    let gold = Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.75)
    
    var body: some View {
        if #available(macOS 15.0, *) {
            MeshGradient(width: 3, height: 3, points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [isAnimating ? 0.1 : 0.8, 0.5], [1.0, isAnimating ? 0.5 : 1],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ], colors: [
                isAnimating ? .blue : .blue, gold, .blue,
            ])
            .padding(-40)
            .blur(radius: 20)
            .opacity(0.5)
            .background(.background)
            .drawingGroup(opaque: true)
            .ecoAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), trigger: $isAnimating)
            .onAppear {
                isAnimating.toggle()
            }
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
