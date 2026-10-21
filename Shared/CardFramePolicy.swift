import Foundation

struct CardFramePolicy {
    static func fit(_ frame: CGRect, to area: CGRect, minimumSize: CGSize) -> CGRect? {
        guard area.width >= minimumSize.width, area.height >= minimumSize.height,
              area.width > 0, area.height > 0 else { return nil }
        let width = min(max(frame.width, minimumSize.width), area.width)
        let height = min(max(frame.height, minimumSize.height), area.height)
        let x = max(area.minX, min(frame.minX, area.maxX - width))
        let y = max(area.minY, min(frame.minY, area.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func resize(_ frame: CGRect, by delta: CGSize, in area: CGRect,
                       minimumSize: CGSize) -> CGRect? {
        guard let start = fit(frame, to: area, minimumSize: minimumSize) else { return nil }
        let width = min(max(start.width + delta.width, minimumSize.width), area.maxX - start.minX)
        let height = min(max(start.height + delta.height, minimumSize.height), start.maxY - area.minY)
        return CGRect(x: start.minX, y: start.maxY - height, width: width, height: height)
    }
}
