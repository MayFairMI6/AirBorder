import ARKit
import Foundation
import RealityKit

final class ARSessionManager: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var trackingLabel = "Starting guidance…"
    @Published private(set) var isPaused = false
    @Published private(set) var isSupported = ARWorldTrackingConfiguration.isSupported

    private weak var arView: ARView?
    private var routeAnchor: AnchorEntity?

    func configure(_ view: ARView, indicator: RouteEntityKind, largeIndicators: Bool) {
        arView = view
        view.session.delegate = self
        view.renderOptions.insert(.disableMotionBlur)

        installRelativeIndicator(indicator, largeIndicators: largeIndicators, in: view)

        if ARWorldTrackingConfiguration.isSupported {
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.planeDetection = [.horizontal]
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            publishTrackingLabel("Move your phone slowly to establish camera tracking")
        } else {
            publishTrackingLabel("Simulator guidance preview — use a physical device for camera tracking")
        }
    }

    /// This is deliberately camera-relative, not an asserted airport position.
    /// A terminal partner map or surveyed indoor-localization source is required
    /// before a route can be placed at a real-world gate or corridor.
    func updateRelativeIndicator(_ indicator: RouteEntityKind, largeIndicators: Bool) {
        guard let arView, routeAnchor?.name != indicator.rawValue else { return }
        routeAnchor?.removeFromParent()
        installRelativeIndicator(indicator, largeIndicators: largeIndicators, in: arView)
    }

    func pause() {
        arView?.session.pause()
        isPaused = true
        trackingLabel = "Guidance paused"
    }

    func resume() {
        guard ARWorldTrackingConfiguration.isSupported, let arView else {
            isPaused = false
            return
        }
        arView.session.run(ARWorldTrackingConfiguration())
        isPaused = false
    }

    func recenter() {
        guard ARWorldTrackingConfiguration.isSupported, let arView else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        trackingLabel = "Recentered — scan the area slowly"
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let label: String = switch camera.trackingState {
        case .normal: "Camera tracking ready — confirm a landmark on the map"
        case .notAvailable: "Camera tracking unavailable — use the terminal map"
        case .limited(let reason):
            switch reason {
            case .initializing: "Initializing tracking…"
            case .excessiveMotion: "Move more slowly"
            case .insufficientFeatures: "Point toward a detailed sign or wall"
            case .relocalizing: "Restoring your position…"
            @unknown default: "Tracking is limited"
            }
        }
        DispatchQueue.main.async { self.trackingLabel = label }
    }

    /// `configure` is called by `UIViewRepresentable.makeUIView`. Deferring the
    /// publication avoids mutating SwiftUI-observed state during that render.
    private func publishTrackingLabel(_ label: String) {
        DispatchQueue.main.async { [weak self] in self?.trackingLabel = label }
    }

    private func installRelativeIndicator(_ indicator: RouteEntityKind, largeIndicators: Bool, in view: ARView) {
        let anchor = AnchorEntity(.camera)
        anchor.name = indicator.rawValue
        let entity = RouteEntityFactory.entity(for: indicator, large: largeIndicators)
        entity.position = SIMD3<Float>(0, -0.25, -1.35)
        anchor.addChild(entity)
        view.scene.addAnchor(anchor)
        routeAnchor = anchor
    }
}
