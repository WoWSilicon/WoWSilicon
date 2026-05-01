import Foundation

struct ManagerAlert: Identifiable, Sendable {
    let id = UUID()
    let message: String
}
