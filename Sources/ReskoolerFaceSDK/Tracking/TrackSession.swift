import Foundation

public class TrackSession {
    private var currentId: Int? = nil

    public init() {}

    public func onFace(trackingId: Int?) -> Bool {
        guard let trackingId = trackingId else {
            return false
        }

        let changed = currentId != nil && currentId != trackingId
        currentId = trackingId

        return changed
    }

    public func clear() {
        currentId = nil
    }
}
