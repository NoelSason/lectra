import SpriteKit
import UIKit

// MARK: - Delegate Protocol

protocol CourseBrainSpriteSceneDelegate: AnyObject {
    func didSelectNode(_ nodeID: String?)
    func didDoubleSelectNode(_ nodeID: String)
}

// MARK: - Scene

/// A premium neural-map visualization of course content.
///
/// **Architecture**: The scene receives raw graph data from the ViewModel and internally
/// re-organizes it into a **course-hub** layout:
///
///   • Each unique **course** becomes a large glowing hub node
///   • The most important child items (topics with high connectivity) orbit their course hub
///   • Low-value / noise nodes (generic modules, single-item topics) are filtered out
///   • Everything fits compactly within the viewport with always-readable labels
///
/// **Interaction**: Pan, pinch-to-zoom, tap-to-focus, drag nodes, double-tap to open.
final class CourseBrainSpriteScene: SKScene {

    // MARK: - Delegate

    weak var graphDelegate: CourseBrainSpriteSceneDelegate?

    // MARK: - Tunable Constants
    // ╔══════════════════════════════════════════════════════════════════════╗
    // ║  TWEAK these values to adjust feel. Scene rebuilds on data change. ║
    // ╚══════════════════════════════════════════════════════════════════════╝

    /// TWEAK: Repulsion charge (negative = repel). Increase magnitude for more spacing.
    private let repulsionCharge: CGFloat = -100

    /// TWEAK: Spring rest length between hub ↔ satellite (pts).
    private let springRestLength: CGFloat = 120

    /// TWEAK: Spring damping (0…1). Higher = less bounce.
    private let springDamping: CGFloat = 0.6

    /// TWEAK: Spring frequency. Higher = stiffer.
    private let springFrequency: CGFloat = 1.4

    /// TWEAK: Linear damping on all bodies. Lower = more floaty / alive.
    private let linearDamping: CGFloat = 1.8

    /// TWEAK: Course hub node radius.
    private let hubRadius: CGFloat = 36.0

    /// TWEAK: Satellite node radius.
    private let satelliteRadius: CGFloat = 18.0

    /// TWEAK: Hub label font size.
    private let hubLabelFontSize: CGFloat = 15.0

    /// TWEAK: Satellite label font size.
    private let satLabelFontSize: CGFloat = 11.0

    /// TWEAK: Glow intensity on hub nodes.
    private let hubGlowWidth: CGFloat = 14.0

    /// TWEAK: Glow intensity on satellite nodes.
    private let satGlowWidth: CGFloat = 8.0

    /// TWEAK: How close satellite nodes orbit their hub (pts).
    private let orbitRadius: CGFloat = 140.0

    /// TWEAK: Max satellites shown per hub to prevent clutter.
    private let maxSatellitesPerHub: Int = 8

    /// TWEAK: Dimmed alpha for unfocused nodes.
    private let dimmedAlpha: CGFloat = 0.07

    /// TWEAK: Edge line opacity.
    private let edgeAlpha: CGFloat = 0.16

    /// TWEAK: Camera zoom range.
    private let cameraMinScale: CGFloat = 0.3
    private let cameraMaxScale: CGFloat = 3.5

    // MARK: - Internal Types

    /// A processed hub (course) with its curated satellites.
    private struct CourseHub {
        let courseId: Int
        let courseName: String
        let satellites: [CourseBrainNode]  // curated, max `maxSatellitesPerHub`
    }

    // MARK: - State

    private var spritesByID: [String: SKShapeNode] = [:]
    private var labelsByID: [String: SKLabelNode] = [:]
    private var labelBgsByID: [String: SKShapeNode] = [:]
    private var edgeShapes: [String: SKShapeNode] = [:]
    /// Stores (sourceID, targetID) for each edge shape key, so we avoid parsing keys.
    private var edgeEndpoints: [String: (String, String)] = [:]
    private var hubNodeIDs: Set<String> = []

    private var graphNodes: [CourseBrainNode] = []
    private var graphEdges: [CourseBrainEdge] = []
    private var selectedNodeID: String?

    private var draggedNode: SKShapeNode?
    private var dragJoint: SKPhysicsJointPin?
    private var dragAnchor: SKNode?

    /// Track last two drag positions for computing release velocity.
    private var lastDragPoint: CGPoint = .zero
    private var prevDragPoint: CGPoint = .zero
    private var lastDragTime: TimeInterval = 0
    private var prevDragTime: TimeInterval = 0

    /// Timer for ambient drift impulses.
    private var lastAmbientTime: TimeInterval = 0

    private let cameraNode = SKCameraNode()
    private var lastPanPoint: CGPoint = .zero
    private var initialCameraScale: CGFloat = 1.0

    private let nodeCategory: UInt32 = 0x1 << 0
    private let anchorCategory: UInt32 = 0x1 << 3

    // MARK: - Hub color palette (one per course, cycled)
    private let hubPalette: [UIColor] = [
        UIColor(red: 0.835, green: 0.392, blue: 0.541, alpha: 1), // rose
        UIColor(red: 0.298, green: 0.553, blue: 1.000, alpha: 1), // blue
        UIColor(red: 1.000, green: 0.624, blue: 0.271, alpha: 1), // amber
        UIColor(red: 0.275, green: 0.788, blue: 0.478, alpha: 1), // green
        UIColor(red: 0.627, green: 0.427, blue: 1.000, alpha: 1), // purple
        UIColor(red: 0.200, green: 0.780, blue: 0.820, alpha: 1), // teal
        UIColor(red: 0.950, green: 0.500, blue: 0.200, alpha: 1), // tangerine
        UIColor(red: 0.700, green: 0.350, blue: 0.900, alpha: 1), // violet
    ]

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        backgroundColor = UIColor(red: 0.027, green: 0.027, blue: 0.031, alpha: 1)
        physicsWorld.gravity = .zero

        addChild(cameraNode)
        camera = cameraNode

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)
    }

    // MARK: - Public API

    func loadGraph(
        nodes: [CourseBrainNode],
        edges: [CourseBrainEdge],
        highlightedNodeIDs: Set<String>,
        openCounts: [String: Int],
        selectedNodeID: String?
    ) {
        self.graphNodes = nodes
        self.graphEdges = edges
        self.selectedNodeID = selectedNodeID
        rebuildScene()
    }

    func updateSelection(_ nodeID: String?) {
        let old = selectedNodeID
        selectedNodeID = nodeID
        if old != nodeID {
            applyFocusVisuals()
            if let nodeID, let sprite = spritesByID[nodeID] {
                animateCamera(to: sprite.position)
            }
        }
    }

    // MARK: - Data Processing

    /// Analyze the raw graph nodes and produce course-hub clusters with curated satellites.
    private func buildHubs() -> [CourseHub] {
        // 1. Group ALL nodes by courseId (using metadata.courseName for the hub label)
        var courseNodes: [Int: (name: String, nodes: [CourseBrainNode])] = [:]

        for node in graphNodes {
            guard let courseId = node.courseId else { continue }
            let name = node.metadata.courseName ?? "Course \(courseId)"
            courseNodes[courseId, default: (name: name, nodes: [])].nodes.append(node)
        }

        // 2. For each course, pick the most important satellite nodes
        var hubs: [CourseHub] = []
        for (courseId, group) in courseNodes {
            let satellites = curateSatellites(group.nodes)
            hubs.append(CourseHub(
                courseId: courseId,
                courseName: abbreviateCourseName(group.name),
                satellites: satellites
            ))
        }

        // Sort hubs so the biggest course is first (most central placement)
        hubs.sort { $0.satellites.count > $1.satellites.count }
        return hubs
    }

    /// Pick the most important nodes from a course group, filtering out noise.
    private func curateSatellites(_ nodes: [CourseBrainNode]) -> [CourseBrainNode] {
        // Score each node for importance. Topics with many connections score high.
        let edgeCounts = computeEdgeCounts()

        let scored: [(node: CourseBrainNode, score: Int)] = nodes.map { node in
            var score = edgeCounts[node.id] ?? 0

            // Boost topics with connections
            if node.type == .topic { score += 3 }

            // Boost assignments (students care about these)
            if node.type == .assignment { score += 2 }

            // Penalize noise labels
            let titleLower = node.title.lowercased()
            let noisePatterns = [
                "unfiled", "general", "course files", "module", "pages",
                "assignments", "quizzes", "course image", "files", "photos"
            ]
            if noisePatterns.contains(where: { titleLower.contains($0) }) {
                score -= 10
            }

            // Penalize generic short names
            if node.title.count < 4 { score -= 5 }

            return (node, score)
        }

        return scored
            .filter { $0.score >= 0 } // drop noise
            .sorted { $0.score > $1.score }
            .prefix(maxSatellitesPerHub)
            .map(\.node)
    }

    private func computeEdgeCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for edge in graphEdges {
            counts[edge.source, default: 0] += 1
            counts[edge.target, default: 0] += 1
        }
        return counts
    }

    /// Shorten long course names like "Chem 3BL: Organic Chemistry Laboratory (Spring 2026)"
    /// to something that fits a label: "Chem 3BL"
    private func abbreviateCourseName(_ name: String) -> String {
        // If it has a colon, take the part before it
        if let colonIdx = name.firstIndex(of: ":") {
            let prefix = String(name[name.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            if prefix.count >= 4 { return prefix }
        }
        // If it's too long, truncate
        if name.count > 30 {
            return String(name.prefix(27)) + "…"
        }
        return name
    }

    // MARK: - Scene Rebuild

    private func rebuildScene() {
        // Clear everything
        for (_, n) in spritesByID { n.removeFromParent() }
        for (_, e) in edgeShapes { e.removeFromParent() }
        spritesByID.removeAll()
        labelsByID.removeAll()
        labelBgsByID.removeAll()
        edgeShapes.removeAll()
        edgeEndpoints.removeAll()
        hubNodeIDs.removeAll()
        physicsWorld.removeAllJoints()
        draggedNode = nil
        dragJoint = nil
        dragAnchor?.removeFromParent()
        dragAnchor = nil

        let hubs = buildHubs()
        guard !hubs.isEmpty else {
            cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
            cameraNode.setScale(1.0)
            return
        }

        // ─── Arrange hubs compactly ───
        // Use a tight grid/honeycomb layout centered on the view
        let positions = layoutHubPositions(count: hubs.count)

        for (i, hub) in hubs.enumerated() {
            let hubID = "hub:\(hub.courseId)"
            let hubPos = positions[i]
            let color = hubPalette[i % hubPalette.count]

            // ── Hub sprite ──
            createHubSprite(id: hubID, title: hub.courseName, position: hubPos, color: color)

            // ── Satellites ──
            let satCount = hub.satellites.count
            for (j, sat) in hub.satellites.enumerated() {
                let angle = (CGFloat(j) / max(CGFloat(satCount), 1)) * 2 * .pi - .pi / 2
                let r = orbitRadius + (j >= 6 ? 50 : 0) // second ring if > 6
                let satPos = CGPoint(
                    x: hubPos.x + cos(angle) * r,
                    y: hubPos.y + sin(angle) * r
                )
                createSatelliteSprite(node: sat, position: satPos, hubColor: color)
            }
        }

        // ─── Edges ───
        // Draw edges between existing sprites only
        let renderedIDs = Set(spritesByID.keys)
        for edge in graphEdges {
            guard renderedIDs.contains(edge.source), renderedIDs.contains(edge.target) else { continue }
            let shape = SKShapeNode()
            shape.strokeColor = UIColor.white.withAlphaComponent(edgeAlpha)
            shape.lineWidth = 1.2
            shape.lineCap = .round
            shape.zPosition = 1
            addChild(shape)
            edgeShapes[edge.id] = shape
            edgeEndpoints[edge.id] = (edge.source, edge.target)
        }

        // Also create edges from hub → its satellites (organic connection lines)
        for (i, hub) in hubs.enumerated() {
            let hubID = "hub:\(hub.courseId)"
            for sat in hub.satellites {
                let edgeKey = "hubedge_\(hub.courseId)_\(sat.id)"
                guard edgeShapes[edgeKey] == nil else { continue }
                let shape = SKShapeNode()
                shape.strokeColor = hubPalette[i % hubPalette.count].withAlphaComponent(0.12)
                shape.lineWidth = 1.5
                shape.lineCap = .round
                shape.zPosition = 1
                addChild(shape)
                edgeShapes[edgeKey] = shape
                edgeEndpoints[edgeKey] = (hubID, sat.id)
            }
        }

        // ─── Spring joints ───
        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.05),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.createJoints(hubs: hubs)
                self.applyFocusVisuals()
            }
        ]))

        // ─── Camera ───
        fitCamera(to: positions)
    }

    /// Lay out hub positions in a compact hexagonal / force-aware pattern.
    private func layoutHubPositions(count: Int) -> [CGPoint] {
        let cx = size.width / 2
        let cy = size.height / 2

        if count == 1 {
            return [CGPoint(x: cx, y: cy)]
        }

        // Use concentric rings with moderate spacing
        let spacing: CGFloat = 340 // distance between hub centers
        var positions: [CGPoint] = []

        if count <= 3 {
            // Horizontal row
            let totalW = CGFloat(count - 1) * spacing
            for i in 0..<count {
                positions.append(CGPoint(
                    x: cx - totalW / 2 + CGFloat(i) * spacing,
                    y: cy
                ))
            }
        } else if count <= 7 {
            // One center + ring
            positions.append(CGPoint(x: cx, y: cy))
            let ringCount = count - 1
            for i in 0..<ringCount {
                let angle = (CGFloat(i) / CGFloat(ringCount)) * 2 * .pi - .pi / 2
                positions.append(CGPoint(
                    x: cx + cos(angle) * spacing,
                    y: cy + sin(angle) * spacing
                ))
            }
        } else {
            // Two concentric rings
            positions.append(CGPoint(x: cx, y: cy))
            let innerCount = min(count - 1, 6)
            for i in 0..<innerCount {
                let angle = (CGFloat(i) / CGFloat(innerCount)) * 2 * .pi - .pi / 2
                positions.append(CGPoint(
                    x: cx + cos(angle) * spacing,
                    y: cy + sin(angle) * spacing
                ))
            }
            let outerCount = count - 1 - innerCount
            for i in 0..<outerCount {
                let angle = (CGFloat(i) / CGFloat(max(outerCount, 1))) * 2 * .pi
                positions.append(CGPoint(
                    x: cx + cos(angle) * spacing * 2.0,
                    y: cy + sin(angle) * spacing * 2.0
                ))
            }
        }

        return positions
    }

    private func createHubSprite(id: String, title: String, position: CGPoint, color: UIColor) {
        let circle = SKShapeNode(circleOfRadius: hubRadius)
        circle.fillColor = color
        circle.strokeColor = color.withAlphaComponent(0.5)
        circle.lineWidth = 2.5
        circle.glowWidth = hubGlowWidth
        circle.name = id
        circle.zPosition = 20
        circle.position = position

        let body = SKPhysicsBody(circleOfRadius: hubRadius + 8)
        body.isDynamic = true
        body.mass = 5.0
        body.charge = repulsionCharge * 4.0
        body.linearDamping = linearDamping * 1.5
        body.angularDamping = 8.0
        body.friction = 0.5
        body.restitution = 0.02
        body.categoryBitMask = nodeCategory
        body.collisionBitMask = nodeCategory
        body.allowsRotation = false
        circle.physicsBody = body

        // ── Label (always visible) ──
        let label = SKLabelNode(text: title)
        label.fontSize = hubLabelFontSize
        label.fontName = "SFProDisplay-Semibold"
        label.fontColor = .white
        label.alpha = 1.0
        label.verticalAlignmentMode = .top
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -(hubRadius + 10))
        label.preferredMaxLayoutWidth = 200
        label.numberOfLines = 2
        label.zPosition = 35
        circle.addChild(label)
        labelsByID[id] = label

        // ── Label background pill ──
        let bgW: CGFloat = max(CGFloat(title.count) * 9, 100)
        let bg = SKShapeNode(rectOf: CGSize(width: bgW, height: 26), cornerRadius: 8)
        bg.fillColor = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 0.82)
        bg.strokeColor = .clear
        bg.position = CGPoint(x: 0, y: -(hubRadius + 23))
        bg.zPosition = 30
        bg.alpha = 0.9
        circle.addChild(bg)
        labelBgsByID[id] = bg

        addChild(circle)
        spritesByID[id] = circle
        hubNodeIDs.insert(id)
    }

    private func createSatelliteSprite(node: CourseBrainNode, position: CGPoint, hubColor: UIColor) {
        let radius = satelliteRadius
        let color = satelliteColor(for: node.type, hubColor: hubColor)

        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = color
        circle.strokeColor = color.withAlphaComponent(0.5)
        circle.lineWidth = 1.5
        circle.glowWidth = satGlowWidth
        circle.name = node.id
        circle.zPosition = 10
        circle.position = position

        let body = SKPhysicsBody(circleOfRadius: radius + 4)
        body.isDynamic = true
        body.mass = 0.6
        body.charge = repulsionCharge
        body.linearDamping = linearDamping
        body.angularDamping = 5.0
        body.friction = 0.3
        body.restitution = 0.05
        body.categoryBitMask = nodeCategory
        body.collisionBitMask = nodeCategory
        body.allowsRotation = false
        circle.physicsBody = body

        // ── Label (shown on zoom/select) ──
        let title = abbreviateTitle(node.title, max: 24)
        let label = SKLabelNode(text: title)
        label.fontSize = satLabelFontSize
        label.fontName = "SFProText-Medium"
        label.fontColor = .white
        label.alpha = 0.0
        label.verticalAlignmentMode = .top
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -(radius + 6))
        label.preferredMaxLayoutWidth = 130
        label.numberOfLines = 2
        label.zPosition = 35
        circle.addChild(label)
        labelsByID[node.id] = label

        addChild(circle)
        spritesByID[node.id] = circle
    }

    /// Satellite color: tinted version of the hub color, shifted by node type.
    private func satelliteColor(for type: CourseBrainNodeType, hubColor: UIColor) -> UIColor {
        switch type {
        case .topic:    return hubColor.withAlphaComponent(0.9)
        case .concept:  return UIColor(red: 0.627, green: 0.427, blue: 1.000, alpha: 1)
        case .assignment: return UIColor(red: 1.000, green: 0.624, blue: 0.271, alpha: 1)
        case .lecture:  return UIColor(red: 0.298, green: 0.553, blue: 1.000, alpha: 1)
        case .note:     return UIColor(red: 0.275, green: 0.788, blue: 0.478, alpha: 1)
        case .file:     return UIColor(red: 0.604, green: 0.627, blue: 0.667, alpha: 1)
        }
    }

    private func createJoints(hubs: [CourseHub]) {
        for hub in hubs {
            let hubID = "hub:\(hub.courseId)"
            guard let hubSprite = spritesByID[hubID],
                  let hubBody = hubSprite.physicsBody else { continue }

            for sat in hub.satellites {
                guard let satSprite = spritesByID[sat.id],
                      let satBody = satSprite.physicsBody else { continue }

                let spring = SKPhysicsJointSpring.joint(
                    withBodyA: hubBody,
                    bodyB: satBody,
                    anchorA: hubSprite.position,
                    anchorB: satSprite.position
                )
                spring.damping = springDamping
                spring.frequency = springFrequency
                physicsWorld.add(spring)
            }
        }

        // Also add springs for original graph edges between satellites
        let renderedIDs = Set(spritesByID.keys)
        for edge in graphEdges {
            guard renderedIDs.contains(edge.source),
                  renderedIDs.contains(edge.target),
                  let srcSprite = spritesByID[edge.source],
                  let tgtSprite = spritesByID[edge.target],
                  let srcBody = srcSprite.physicsBody,
                  let tgtBody = tgtSprite.physicsBody else { continue }

            let spring = SKPhysicsJointSpring.joint(
                withBodyA: srcBody,
                bodyB: tgtBody,
                anchorA: srcSprite.position,
                anchorB: tgtSprite.position
            )
            spring.damping = springDamping
            spring.frequency = springFrequency * 0.5 // weaker cross-links
            physicsWorld.add(spring)
        }
    }

    private func fitCamera(to positions: [CGPoint]) {
        guard !positions.isEmpty else {
            cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
            cameraNode.setScale(1.0)
            return
        }

        let xs = positions.map(\.x)
        let ys = positions.map(\.y)
        let midX = (xs.min()! + xs.max()!) / 2
        let midY = (ys.min()! + ys.max()!) / 2

        // Account for orbit radius
        let contentW = (xs.max()! - xs.min()!) + orbitRadius * 2 + 200
        let contentH = (ys.max()! - ys.min()!) + orbitRadius * 2 + 200
        let scaleX = contentW / size.width
        let scaleY = contentH / size.height
        let fitScale = max(scaleX, scaleY, 0.6)

        cameraNode.position = CGPoint(x: midX, y: midY)
        cameraNode.setScale(min(fitScale, 2.0))
    }

    // MARK: - Physics Update

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        applyAmbientDrift(currentTime)
    }

    override func didSimulatePhysics() {
        super.didSimulatePhysics()
        updateEdgePaths()
        updateLabelVisibility()
    }

    /// Apply tiny random impulses to keep the graph feeling alive and breathing.
    private func applyAmbientDrift(_ currentTime: TimeInterval) {
        guard currentTime - lastAmbientTime > 2.0 else { return } // every 2 seconds
        lastAmbientTime = currentTime

        for (_, sprite) in spritesByID {
            guard let body = sprite.physicsBody, body.isDynamic else { continue }
            let dx = CGFloat.random(in: -3...3)
            let dy = CGFloat.random(in: -3...3)
            body.applyImpulse(CGVector(dx: dx, dy: dy))
        }
    }

    private func updateEdgePaths() {
        for (key, shape) in edgeShapes {
            guard let (srcID, tgtID) = edgeEndpoints[key],
                  let src = spritesByID[srcID],
                  let tgt = spritesByID[tgtID] else {
                shape.path = nil
                continue
            }

            let from = src.position
            let to = tgt.position
            let dx = to.x - from.x
            let dy = to.y - from.y
            let dist = sqrt(dx * dx + dy * dy)
            let perpScale: CGFloat = min(dist * 0.05, 12)
            let perpX = -dy / max(dist, 1) * perpScale
            let perpY = dx / max(dist, 1) * perpScale
            let ctrl = CGPoint(x: (from.x + to.x) / 2 + perpX, y: (from.y + to.y) / 2 + perpY)

            let path = CGMutablePath()
            path.move(to: from)
            path.addQuadCurve(to: to, control: ctrl)
            shape.path = path
        }
    }

    private func updateLabelVisibility() {
        let scale = cameraNode.xScale
        let showSatLabels = scale < 1.1

        for (id, label) in labelsByID {
            if hubNodeIDs.contains(id) {
                label.alpha = 0.95 // always visible
                labelBgsByID[id]?.alpha = 0.85
            } else if id == selectedNodeID {
                label.alpha = 0.95
            } else if showSatLabels && (spritesByID[id]?.alpha ?? 0) > 0.5 {
                label.alpha = 0.8
            } else {
                label.alpha = 0.0
            }
        }
    }

    // MARK: - Focus / Dim

    private func applyFocusVisuals() {
        guard let sel = selectedNodeID else {
            for (_, s) in spritesByID { s.alpha = 1.0 }
            for (_, e) in edgeShapes { e.alpha = edgeAlpha }
            for (id, l) in labelsByID {
                l.alpha = hubNodeIDs.contains(id) ? 0.95 : 0.0
            }
            for (id, bg) in labelBgsByID {
                bg.alpha = hubNodeIDs.contains(id) ? 0.85 : 0.0
            }
            return
        }

        var connected = Set([sel])
        for edge in graphEdges {
            if edge.source == sel { connected.insert(edge.target) }
            else if edge.target == sel { connected.insert(edge.source) }
        }
        // Also connect hub ↔ satellite
        for (id, _) in spritesByID {
            if id.hasPrefix("hub:") {
                // If selected is a satellite of this hub, highlight hub too
                // and vice versa
            }
        }

        for (id, sprite) in spritesByID {
            let show = connected.contains(id) || hubNodeIDs.contains(id)
            sprite.run(SKAction.fadeAlpha(to: show ? 1.0 : dimmedAlpha, duration: 0.22))
        }

        for (key, shape) in edgeShapes {
            let visible: Bool
            if let edge = graphEdges.first(where: { $0.id == key }) {
                visible = connected.contains(edge.source) && connected.contains(edge.target)
            } else {
                visible = false // hub edges: show if connected
            }
            shape.run(SKAction.fadeAlpha(to: visible ? edgeAlpha * 2.0 : dimmedAlpha * 0.3, duration: 0.22))
        }

        for (id, label) in labelsByID {
            let isHub = hubNodeIDs.contains(id)
            let isConnected = connected.contains(id)
            label.alpha = (id == sel) ? 1.0 : (isHub ? 0.95 : (isConnected ? 0.85 : 0.0))
        }
        for (id, bg) in labelBgsByID {
            bg.alpha = hubNodeIDs.contains(id) ? 0.85 : 0.0
        }
    }

    // MARK: - Gestures

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let view = self.view else { return }
        switch g.state {
        case .began:
            lastPanPoint = g.location(in: view)
            let sp = convertPoint(fromView: g.location(in: view))
            if let hit = nodeAt(sp) { beginDrag(hit, at: sp); return }
        case .changed:
            if draggedNode != nil {
                moveDrag(to: convertPoint(fromView: g.location(in: view)))
            } else {
                let cur = g.location(in: view)
                let s = cameraNode.xScale
                cameraNode.position.x -= (cur.x - lastPanPoint.x) * s
                cameraNode.position.y += (cur.y - lastPanPoint.y) * s
                lastPanPoint = cur
            }
        case .ended, .cancelled:
            endDrag()
        default: break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began: initialCameraScale = cameraNode.xScale
        case .changed:
            cameraNode.setScale(min(max(initialCameraScale / g.scale, cameraMinScale), cameraMaxScale))
        default: break
        }
    }

    @objc private func handleSingleTap(_ g: UITapGestureRecognizer) {
        guard let view = self.view else { return }
        let sp = convertPoint(fromView: g.location(in: view))
        if let hit = nodeAt(sp) {
            selectedNodeID = hit.name
            applyFocusVisuals()
            graphDelegate?.didSelectNode(hit.name)
            animateCamera(to: hit.position)
        } else {
            selectedNodeID = nil
            applyFocusVisuals()
            graphDelegate?.didSelectNode(nil)
        }
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        guard let view = self.view else { return }
        let sp = convertPoint(fromView: g.location(in: view))
        if let hit = nodeAt(sp), let id = hit.name {
            if let node = graphNodes.first(where: { $0.id == id }),
               let url = node.resourceURL {
                print("[CourseBrain] Open: \(url.absoluteString)")
            }
            graphDelegate?.didDoubleSelectNode(id)
        }
    }

    // MARK: - Hit Testing

    private func nodeAt(_ point: CGPoint) -> SKShapeNode? {
        for node in nodes(at: point) {
            if let shape = node as? SKShapeNode, spritesByID.values.contains(shape) { return shape }
            if let p = node.parent as? SKShapeNode, spritesByID.values.contains(p) { return p }
        }
        return nil
    }

    // MARK: - Dragging

    private func beginDrag(_ node: SKShapeNode, at pt: CGPoint) {
        draggedNode = node
        let anchor = SKNode()
        anchor.position = pt
        anchor.physicsBody = SKPhysicsBody(circleOfRadius: 1)
        anchor.physicsBody?.isDynamic = false
        anchor.physicsBody?.categoryBitMask = anchorCategory
        anchor.physicsBody?.collisionBitMask = 0
        addChild(anchor)
        dragAnchor = anchor
        if let nb = node.physicsBody, let ab = anchor.physicsBody {
            let j = SKPhysicsJointPin.joint(withBodyA: ab, bodyB: nb, anchor: pt)
            physicsWorld.add(j)
            dragJoint = j
        }
    }

    private func moveDrag(to pt: CGPoint) {
        guard let da = dragAnchor, let dj = dragJoint else { return }
        physicsWorld.remove(dj)
        da.position = pt
        if let nb = draggedNode?.physicsBody, let ab = da.physicsBody {
            let j = SKPhysicsJointPin.joint(withBodyA: ab, bodyB: nb, anchor: pt)
            physicsWorld.add(j)
            dragJoint = j
        }

        // Track velocity for release
        let now = CACurrentMediaTime()
        prevDragPoint = lastDragPoint
        prevDragTime = lastDragTime
        lastDragPoint = pt
        lastDragTime = now
    }

    private func endDrag() {
        // Compute release velocity from last two tracked positions
        if let node = draggedNode, let body = node.physicsBody {
            let dt = lastDragTime - prevDragTime
            if dt > 0.001 && dt < 0.5 {
                let vx = (lastDragPoint.x - prevDragPoint.x) / CGFloat(dt)
                let vy = (lastDragPoint.y - prevDragPoint.y) / CGFloat(dt)
                // Clamp to prevent insane velocities
                let maxV: CGFloat = 600
                let clampedVx = min(max(vx, -maxV), maxV)
                let clampedVy = min(max(vy, -maxV), maxV)
                body.velocity = CGVector(dx: clampedVx, dy: clampedVy)
            }
        }

        if let j = dragJoint { physicsWorld.remove(j) }
        dragAnchor?.removeFromParent()
        dragAnchor = nil; dragJoint = nil; draggedNode = nil
    }

    // MARK: - Camera

    private func animateCamera(to pos: CGPoint) {
        let move = SKAction.move(to: pos, duration: 0.3)
        move.timingMode = .easeInEaseOut
        cameraNode.run(move)
    }

    // MARK: - Helpers

    private func abbreviateTitle(_ title: String, max m: Int = 24) -> String {
        title.count <= m ? title : String(title.prefix(m - 1)) + "…"
    }
}
