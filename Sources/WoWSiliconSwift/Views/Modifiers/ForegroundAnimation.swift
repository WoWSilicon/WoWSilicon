import SwiftUI

struct ECOAnimationModifier: ViewModifier {
    
    let animation: Animation?
    
    @Binding
    var trigger: Bool
    
    @Environment(\.isGameRunning)
    private var isGameRunning
    
    @Environment(\.appearsActive)
    private var appearsActive
    
    private var isEnabled: Bool {
        appearsActive && !isGameRunning
    }
    
    func body(content: Content) -> some View {
        content
            .animation(isEnabled ? animation : .default, value: trigger)
            .onChange(of: isEnabled) {
                trigger.toggle()
            }
    }
}

extension View {
    
    func ecoAnimation(_ animation: Animation?, trigger: Binding<Bool>) -> some View {
        modifier(ECOAnimationModifier(animation: animation, trigger: trigger))
    }
}
