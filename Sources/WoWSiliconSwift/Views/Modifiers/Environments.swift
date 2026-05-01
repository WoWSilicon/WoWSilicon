import SwiftUI

extension EnvironmentValues {
    
    @Entry
    var isGameRunning = false
}

extension View {
    
    func registerEnvironmentValues(_ viewModel: MainDashboardViewModel) -> some View {
        environment(\.isGameRunning, viewModel.isGameOperationInProgress)
    }
}
