import Foundation

public struct WatchdogConfig {
    public let cameraStallMillis: Int64
    public let pipelineStallMillis: Int64
    public let maxConsecutiveErrors: Int

    public init(
        cameraStallMillis: Int64 = 5_000,
        pipelineStallMillis: Int64 = 10_000,
        maxConsecutiveErrors: Int = 5
    ) {
        self.cameraStallMillis = cameraStallMillis
        self.pipelineStallMillis = pipelineStallMillis
        self.maxConsecutiveErrors = maxConsecutiveErrors
    }
}

public enum WatchdogStatus: String {
    case healthy = "HEALTHY"
    case cameraStalled = "CAMERA_STALLED"
    case pipelineStalled = "PIPELINE_STALLED"
    case modelFailing = "MODEL_FAILING"
}

public class KioskWatchdog {
    private let config: WatchdogConfig
    private var lastFrameReceived: Int64
    private var lastFrameFinished: Int64
    private var processingStarted: Int64?
    private var consecutiveErrors: Int = 0

    private let queue = DispatchQueue(label: "com.reskooler.KioskWatchdog")

    private func nowMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

    public init(config: WatchdogConfig = WatchdogConfig()) {
        self.config = config
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        self.lastFrameReceived = now
        self.lastFrameFinished = now
    }

    public func onFrameReceived() {
        queue.async {
            self.lastFrameReceived = self.nowMillis()
        }
    }

    public func onFrameStarted() {
        queue.async {
            self.processingStarted = self.nowMillis()
        }
    }

    public func onFrameFinished(success: Bool) {
        queue.async {
            self.processingStarted = nil
            self.lastFrameFinished = self.nowMillis()
            if success {
                self.consecutiveErrors = 0
            } else {
                self.consecutiveErrors += 1
            }
        }
    }

    public func check() -> WatchdogStatus {
        var status: WatchdogStatus = .healthy
        queue.sync {
            let now = self.nowMillis()

            if now - lastFrameReceived > config.cameraStallMillis {
                status = .cameraStalled
                return
            }

            if let start = processingStarted, now - start > config.pipelineStallMillis {
                status = .pipelineStalled
                return
            }

            if consecutiveErrors >= config.maxConsecutiveErrors {
                status = .modelFailing
                return
            }
        }
        return status
    }
}
