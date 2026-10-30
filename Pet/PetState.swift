/// Renderer-independent description of the pet.
struct PetState {
    enum Activity: String, CaseIterable {
        case waiting
        case sleeping = "rest"
        case walkingRight = "running-right"
        case walkingLeft = "running-left"
        case waving = "greeting"

        var title: String {
            switch self {
            case .waiting: "Ожидание"
            case .sleeping: "Отдых"
            case .walkingRight: "Бег вправо"
            case .walkingLeft: "Бег влево"
            case .waving: "Приветствие"
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
}
