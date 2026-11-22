import SwiftUI
import LocalAuthentication

enum AppLock {
    static let enabledKey = "lock.enabled"

    /// Face ID / Touch ID with the device passcode as fallback.
    static func canUse() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static func authenticate(reason: String = "Desbloquear o livo") async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Locks the app after it goes to the background (when enabled) and hides content in the app switcher.
struct LockGate<Content: View>: View {
    @AppStorage(AppLock.enabledKey) private var enabled = false
    @Environment(\.scenePhase) private var phase
    @State private var locked = UserDefaults.standard.bool(forKey: AppLock.enabledKey)
    @State private var authenticating = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .overlay {
                if locked {
                    LockScreen(authenticating: authenticating, unlock: unlock)
                } else if phase != .active {
                    PrivacyCover()
                }
            }
            .onChange(of: phase) { _, new in
                if new == .background && enabled { locked = true }
                if new == .active && locked { unlock() }
            }
            .onChange(of: enabled) { _, on in if !on { locked = false } }
            .task { if locked { unlock() } }
    }

    private func unlock() {
        guard !authenticating else { return }
        guard AppLock.canUse() else {
            // No passcode/biometrics on the device anymore: locking would trap the user.
            locked = false
            return
        }
        authenticating = true
        Task {
            let ok = await AppLock.authenticate()
            authenticating = false
            if ok { locked = false }
        }
    }
}

private struct LockScreen: View {
    let authenticating: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: Spacing.m) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Color.lifeAccent)
                Text("livo").font(.largeTitle.bold())
                Text("sua vida mais inteligente").foregroundStyle(.secondary)
                Button("Desbloquear", action: unlock)
                    .buttonStyle(.borderedProminent)
                    .disabled(authenticating)
                    .padding(.top, Spacing.m)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            Text("livo").font(.largeTitle.bold()).foregroundStyle(Color.lifeAccent)
        }
        .accessibilityHidden(true)
    }
}
