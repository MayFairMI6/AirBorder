import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    let sessionManager: ARSessionManager
    let indicator: RouteEntityKind
    let largeIndicators: Bool

    func makeUIView(context: Context) -> ARView {
        #if targetEnvironment(simulator)
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        #else
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        #endif
        sessionManager.configure(view, indicator: indicator, largeIndicators: largeIndicators)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        sessionManager.updateRelativeIndicator(indicator, largeIndicators: largeIndicators)
    }
}
