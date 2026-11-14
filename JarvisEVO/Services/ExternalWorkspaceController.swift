import SwiftUI
import Observation
import UIKit

@MainActor @Observable
final class ExternalWorkspaceController {
    static let shared = ExternalWorkspaceController()
    private(set) var state = DeskPresentationState()
    private(set) var model: AppModel?
    @ObservationIgnored private var windows: [String: UIWindow] = [:]
    func configure(model: AppModel) { self.model = model }
    func startSharing() { state.startSharing() }
    func stopSharing() { state.stopSharing() }
    func setForeground(_ value: Bool) { state.setForeground(value) }
    func select(_ panel: DeskPanel) { state.select(panel) }
    func scroll(_ action: DeskScrollAction) { state.requestScroll(action) }

    func attach(scene: UIWindowScene) {
        guard scene.session.role == .windowExternalDisplayNonInteractive else { return }
        let id = scene.session.persistentIdentifier
        state.connect(sessionID: id)
        guard windows[id] == nil else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DeskWorkspaceView(controller: self))
        windows[id] = window
        // Never make an external, noninteractive window the phone's key window.
        window.isHidden = false
    }
    func detach(sessionID: String) {
        state.disconnect(sessionID: sessionID)
        if let window = windows.removeValue(forKey: sessionID) {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
    }
}

@MainActor
final class ExternalWorkspaceSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let scene = scene as? UIWindowScene { ExternalWorkspaceController.shared.attach(scene: scene) }
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalWorkspaceController.shared.detach(sessionID: scene.session.persistentIdentifier)
    }
    func sceneWillResignActive(_ scene: UIScene) {
        ExternalWorkspaceController.shared.stopSharing()
    }
}
