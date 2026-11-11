import Foundation
import CoreGraphics

/// Keeps the draggable area inside the union of connected display rectangles.
struct ScreenDragConstraint {
    static func translation(of container: CGRect, toward delta: CGPoint, screens: [CGRect],
                            margin: CGFloat = 10) -> CGPoint {
        // Expand the container rather than inset each screen, keeping monitor seams open.
        let rect = container.insetBy(dx: -margin, dy: -margin)
        guard !screens.isEmpty else { return .zero }
        guard isCovered(rect, by: screens) else {
            // Recover positions saved before a monitor was disconnected.
            return screens.filter { $0.width >= rect.width && $0.height >= rect.height }
                .map { screen in
                    CGPoint(x: min(max(rect.minX + delta.x, screen.minX), screen.maxX - rect.width) - rect.minX,
                            y: min(max(rect.minY + delta.y, screen.minY), screen.maxY - rect.height) - rect.minY)
                }
                .min { hypot($0.x, $0.y) < hypot($1.x, $1.y) } ?? .zero
        }
        var result = advance(rect, by: delta, screens: screens)
        // After reaching an outer edge, allow movement along it.
        let horizontal = advance(rect.offsetBy(dx: result.x, dy: result.y),
                                 by: CGPoint(x: delta.x - result.x, y: 0), screens: screens)
        result.x += horizontal.x
        let vertical = advance(rect.offsetBy(dx: result.x, dy: result.y),
                               by: CGPoint(x: 0, y: delta.y - result.y), screens: screens)
        result.y += vertical.y
        return result
    }

    private static func advance(_ rect: CGRect, by delta: CGPoint, screens: [CGRect]) -> CGPoint {
        // Coverage can change only when a hit-box edge crosses a display edge.
        var crossings: [CGFloat] = [0, 1]
        for screen in screens {
            if delta.x != 0 {
                for edge in [screen.minX, screen.maxX] {
                    crossings += [(edge - rect.minX) / delta.x, (edge - rect.maxX) / delta.x]
                }
            }
            if delta.y != 0 {
                for edge in [screen.minY, screen.maxY] {
                    crossings += [(edge - rect.minY) / delta.y, (edge - rect.maxY) / delta.y]
                }
            }
        }
        crossings = Array(Set(crossings.filter { $0 >= 0 && $0 <= 1 })).sorted()
        for (start, end) in zip(crossings, crossings.dropFirst()) {
            let midpoint = (start + end) / 2
            if !isCovered(rect.offsetBy(dx: delta.x * midpoint, dy: delta.y * midpoint), by: screens) {
                return CGPoint(x: delta.x * start, y: delta.y * start)
            }
        }
        return delta
    }

    private static func isCovered(_ rect: CGRect, by screens: [CGRect]) -> Bool {
        var uncovered = [rect]
        for screen in screens {
            uncovered = uncovered.flatMap { piece -> [CGRect] in
                let overlap = piece.intersection(screen)
                guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return [piece] }
                return [
                    CGRect(x: piece.minX, y: piece.minY, width: overlap.minX - piece.minX, height: piece.height),
                    CGRect(x: overlap.maxX, y: piece.minY, width: piece.maxX - overlap.maxX, height: piece.height),
                    CGRect(x: overlap.minX, y: piece.minY, width: overlap.width, height: overlap.minY - piece.minY),
                    CGRect(x: overlap.minX, y: overlap.maxY, width: overlap.width, height: piece.maxY - overlap.maxY)
                ].filter { $0.width > 0.000001 && $0.height > 0.000001 }
            }
            if uncovered.isEmpty { return true }
        }
        return uncovered.isEmpty
    }
}
