import SwiftUI
import SpriteKit

/// SwiftUI wrapper that hosts the `CourseBrainSpriteScene` inside an `SKView`.
/// Bridges graph data from the ViewModel into SpriteKit and routes delegate
/// callbacks (node selection, double‑tap) back to SwiftUI.
struct CourseBrainSpriteView: UIViewRepresentable {

    let graph: CourseBrainGraph
    let highlightedNodeIDs: Set<String>
    @Binding var selectedNodeID: String?
    let onNodeTap: (String) -> Void
    let onNodeDoubleTap: (String) -> Void

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.ignoresSiblingOrder = true
        skView.allowsTransparency = true
        skView.backgroundColor = UIColor(hex: 0x0D0A09)

        // Create the scene sized to the view's bounds (will resize via update)
        let scene = CourseBrainSpriteScene(size: CGSize(width: 1200, height: 900))
        scene.scaleMode = .resizeFill
        scene.graphDelegate = context.coordinator

        skView.presentScene(scene)
        context.coordinator.scene = scene

        // Initial data load
        scene.loadGraph(
            nodes: graph.nodes,
            edges: graph.edges,
            highlightedNodeIDs: highlightedNodeIDs,
            openCounts: [:], // openCounts can be passed through graph in a future iteration
            selectedNodeID: selectedNodeID
        )

        return skView
    }

    func updateUIView(_ skView: SKView, context: Context) {
        guard let scene = context.coordinator.scene else { return }

        // Check if graph changed (fingerprint comparison)
        if context.coordinator.lastFingerprint != graph.fingerprint {
            context.coordinator.lastFingerprint = graph.fingerprint
            scene.loadGraph(
                nodes: graph.nodes,
                edges: graph.edges,
                highlightedNodeIDs: highlightedNodeIDs,
                openCounts: [:],
                selectedNodeID: selectedNodeID
            )
        } else {
            // Selection may have changed externally (e.g., from left panel)
            scene.updateSelection(selectedNodeID)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, CourseBrainSpriteSceneDelegate {
        var parent: CourseBrainSpriteView
        var scene: CourseBrainSpriteScene?
        var lastFingerprint: String = ""

        init(parent: CourseBrainSpriteView) {
            self.parent = parent
        }

        func didSelectNode(_ nodeID: String?) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.selectedNodeID = nodeID
                if let nodeID {
                    self.parent.onNodeTap(nodeID)
                }
            }
        }

        func didDoubleSelectNode(_ nodeID: String) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.onNodeDoubleTap(nodeID)
            }
        }
    }
}
