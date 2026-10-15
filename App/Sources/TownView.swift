import SmallvilleCore
import SpriteKit
import SwiftUI

/// The town. For now a schematic: one box per location with the agents currently in it. The
/// Tiled map and sprites arrive once assets are fetched and `TownScene` learns to draw them.
struct TownView: View {
    @Environment(SimulationController.self) private var controller
    @State private var scene = TownScene(size: CGSize(width: 390, height: 600))

    var body: some View {
        @Bindable var controller = controller
        NavigationStack {
            VStack(spacing: 12) {
                SpriteView(scene: scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                if let snapshot = controller.snapshot {
                    Text("\(snapshot.now)  ·  \(snapshot.budget.totalCalls) calls  ·  \(snapshot.eventCount) events")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let error = controller.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }

                HStack {
                    Picker("Brain", selection: $controller.brainChoice) {
                        ForEach(SimulationController.BrainChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .disabled(controller.isRunning)
                    Spacer()
                    Button(controller.isRunning ? "Stop" : "Start") {
                        if controller.isRunning {
                            controller.stop()
                        } else {
                            controller.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Smallville")
            .onChange(of: controller.snapshot?.now) {
                if let snapshot = controller.snapshot {
                    scene.render(snapshot, world: .smallvilleSubset())
                }
            }
        }
    }
}

/// Draws locations as labeled boxes and agents as emoji inside them.
final class TownScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.93, green: 0.90, blue: 0.82, alpha: 1)
        scaleMode = .resizeFill
    }

    func render(_ snapshot: Simulation.Snapshot, world: WorldMap) {
        removeAllChildren()
        let locations = world.allLocations
        let columns = 2
        let cellWidth = size.width / CGFloat(columns)
        let rows = max(1, (locations.count + columns - 1) / columns)
        let cellHeight = size.height / CGFloat(rows)

        for (index, location) in locations.enumerated() {
            let column = index % columns
            let row = index / columns
            let origin = CGPoint(x: CGFloat(column) * cellWidth, y: size.height - CGFloat(row + 1) * cellHeight)
            let box = SKShapeNode(rect: CGRect(origin: origin, size: CGSize(width: cellWidth, height: cellHeight)).insetBy(dx: 6, dy: 6), cornerRadius: 8)
            box.fillColor = location.isPublic ? SKColor(white: 1, alpha: 0.7) : SKColor(white: 1, alpha: 0.35)
            box.strokeColor = SKColor(white: 0.4, alpha: 0.6)
            addChild(box)

            let title = SKLabelNode(text: location.name)
            title.fontName = "AvenirNext-DemiBold"
            title.fontSize = 11
            title.fontColor = SKColor.darkGray
            title.position = CGPoint(x: origin.x + cellWidth / 2, y: origin.y + cellHeight - 22)
            addChild(title)

            let here = snapshot.agents.filter { $0.location == location.id }
            for (slot, agent) in here.enumerated() {
                let label = SKLabelNode(text: "\(agent.emoji) \(agent.name.split(separator: " ").first ?? "")")
                label.fontName = "AvenirNext-Regular"
                label.fontSize = 13
                label.fontColor = SKColor.black
                label.position = CGPoint(
                    x: origin.x + cellWidth / 2, y: origin.y + cellHeight - 44 - CGFloat(slot) * 18)
                addChild(label)
            }
        }
    }
}
