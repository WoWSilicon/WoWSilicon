import SwiftUI

struct PlayButtonStyle: ButtonStyle {
    
    @State
    private var animateToggle = false
    
    @Environment(\.isEnabled)
    private var isEnabled
    
    private let colors: [Color] = [Color(red: 1.0, green: 0.8, blue: 0.2), .blue]
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .font(.system(size: 32, weight: .heavy, design: .rounded))
            .padding(.vertical, 20)
            .padding(.horizontal, 32)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(gradient: .init(colors: animateToggle ? colors : colors.reversed()), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .ecoAnimation(isEnabled ? .linear(duration: 3.0).repeatForever(autoreverses: true) : .none, trigger: $animateToggle)
            }
            .saturation(isEnabled ? 1 : 0.5)
            .opacity(!isEnabled ? 0.6 : (configuration.isPressed ? 0.8 : 1.0))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .onAppear {
                animateToggle.toggle()
            }
    }
}

extension ButtonStyle where Self == PlayButtonStyle {
    
    static var play: PlayButtonStyle {
        PlayButtonStyle()
    }
}
