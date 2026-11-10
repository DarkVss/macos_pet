/// Renderer-independent description of the pet.
struct PetState {
    enum Activity: String, CaseIterable {
        case waiting
        case sleeping = "rest"
        case walkingRight = "running-right"
        case walkingLeft = "running-left"
        case waving = "greeting"
        case listeningToMusic = "listening-to-music"

        var title: String {
            switch self {
            case .waiting: "Ожидание"
            case .sleeping: "Отдых"
            case .walkingRight: "Бег вправо"
            case .walkingLeft: "Бег влево"
            case .waving: "Приветствие"
            case .listeningToMusic: "Слушаю музыку"
            }
        }
    }

    var activity: Activity = .waiting
    /// Clockwise gaze direction in 22.5-degree steps; nil uses activity animation.
    var lookDirection: Int?
}

@MainActor
protocol PetRendering: AnyObject {
    func display(_ state: PetState)
}

@MainActor
final class PetController {
    private let renderer: any PetRendering
    private(set) var state = PetState()
    private var stateBeforeDragging: PetState?

    init(renderer: any PetRendering) {
        self.renderer = renderer
        renderer.display(state)
    }

    func setActivity(_ activity: PetState.Activity) {
        state.activity = activity
        state.lookDirection = nil
        renderer.display(state)
    }

    func look(toward direction: Int) {
        state.lookDirection = ((direction % 16) + 16) % 16
        renderer.display(state)
    }

    func resetLook() {
        state.lookDirection = nil
        renderer.display(state)
    }

    func drag(horizontalDistance: Double) {
        guard abs(horizontalDistance) >= 2 else { return }
        if stateBeforeDragging == nil { stateBeforeDragging = state }
        let activity: PetState.Activity = horizontalDistance > 0 ? .walkingRight : .walkingLeft
        guard state.activity != activity || state.lookDirection != nil else { return }
        state.activity = activity
        state.lookDirection = nil
        renderer.display(state)
    }

    func endDragging() {
        guard let previous = stateBeforeDragging else { return }
        stateBeforeDragging = nil
        state = previous
        renderer.display(state)
    }
}
