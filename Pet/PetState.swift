/// Renderer-independent description of the pet.
struct PetState: Equatable {
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
    private var selectedState = PetState()
    private var draggingActivity: PetState.Activity?
    private var isMusicActive = false

    init(renderer: any PetRendering) {
        self.renderer = renderer
        renderer.display(state)
    }

    func setActivity(_ activity: PetState.Activity) {
        selectedState.activity = activity
        selectedState.lookDirection = nil
        updateDisplay()
    }

    func look(toward direction: Int) {
        selectedState.lookDirection = ((direction % 16) + 16) % 16
        updateDisplay()
    }

    func resetLook() {
        selectedState.lookDirection = nil
        updateDisplay()
    }

    func drag(horizontalDistance: Double) {
        guard abs(horizontalDistance) >= 2 else { return }
        draggingActivity = horizontalDistance > 0 ? .walkingRight : .walkingLeft
        updateDisplay()
    }

    func endDragging() {
        draggingActivity = nil
        updateDisplay()
    }

    func setMusicActive(_ active: Bool) {
        isMusicActive = active
        updateDisplay()
    }

    private func updateDisplay() {
        let next: PetState
        if let activity = draggingActivity {
            next = PetState(activity: activity)
        } else if isMusicActive {
            next = PetState(activity: .listeningToMusic)
        } else {
            next = selectedState
        }
        guard next != state else { return }
        state = next
        renderer.display(state)
    }
}
