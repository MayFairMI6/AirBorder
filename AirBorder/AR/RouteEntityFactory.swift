import RealityKit
import UIKit

enum RouteEntityKind: String, CaseIterable, Sendable {
    case forward
    case slightLeft
    case left
    case sharpLeft
    case slightRight
    case right
    case sharpRight
    case uTurn
    case continueStraight
    case elevator
    case escalator
    case stairs
    case gate
    case warning
    case destinationReached
}

enum RouteEntityFactory {
    static func entity(for kind: RouteEntityKind, large: Bool) -> Entity {
        let root = Entity()
        let scale: Float = large ? 1.35 : 1
        let color: UIColor = switch kind {
        case .warning: .systemOrange
        case .destinationReached, .gate: .systemGreen
        case .elevator: .systemBlue
        case .stairs, .escalator: .systemIndigo
        default: .systemTeal
        }
        let material = SimpleMaterial(color: color, isMetallic: false)

        switch kind {
        case .forward, .continueStraight, .slightLeft, .left, .sharpLeft,
             .slightRight, .right, .sharpRight, .uTurn:
            let shaft = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.10 * scale, 0.035 * scale, 0.42 * scale)), materials: [material])
            shaft.position.z = -0.07
            let head = arrowHead(scale: scale, material: material)
            head.position.z = -0.36 * scale
            head.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            root.addChild(shaft)
            root.addChild(head)
            let yaw: Float = switch kind {
            case .slightLeft: -.pi / 4
            case .left: -.pi / 2
            case .sharpLeft: -.pi * 3 / 4
            case .slightRight: .pi / 4
            case .right: .pi / 2
            case .sharpRight: .pi * 3 / 4
            case .uTurn: .pi
            default: 0
            }
            root.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        case .elevator, .escalator, .stairs:
            let marker = ModelEntity(mesh: .generateBox(size: 0.28 * scale, cornerRadius: 0.05 * scale), materials: [material])
            root.addChild(marker)
        case .gate, .destinationReached:
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.18 * scale), materials: [material])
            root.addChild(marker)
        case .warning:
            let marker = warningMarker(scale: scale, material: material)
            root.addChild(marker)
        }
        root.name = kind.rawValue
        return root
    }

    private static func arrowHead(scale: Float, material: SimpleMaterial) -> ModelEntity {
        if #available(iOS 18.0, *) {
            return ModelEntity(mesh: .generateCone(height: 0.28 * scale, radius: 0.16 * scale), materials: [material])
        }
        return ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.24 * scale, 0.08 * scale, 0.24 * scale)),
            materials: [material]
        )
    }

    private static func warningMarker(scale: Float, material: SimpleMaterial) -> ModelEntity {
        if #available(iOS 18.0, *) {
            return ModelEntity(mesh: .generateCone(height: 0.36 * scale, radius: 0.22 * scale), materials: [material])
        }
        return ModelEntity(mesh: .generateBox(size: 0.28 * scale, cornerRadius: 0.04 * scale), materials: [material])
    }
}
