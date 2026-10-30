import CielCore
import Testing

@Suite struct ModelStateTests {
    @Test func aDownloadRunsFromStartToReady() {
        let state = ModelState.notDownloaded.applying(.start).applying(.progress(0.37)).applying(.verified)
        #expect(state == .ready)
    }

    @Test func progressStaysWithinBounds() {
        let downloading = ModelState.notDownloaded.applying(.start)
        #expect(downloading.applying(.progress(1.4)) == .downloading(fraction: 1))
        #expect(downloading.applying(.progress(-1)) == .downloading(fraction: 0))
    }

    @Test func aFailedDownloadCanStartAgain() {
        let failed = ModelState.downloading(fraction: 0.5).applying(.failed("Offline"))
        #expect(failed == .failed("Offline"))
        #expect(failed.applying(.start) == .downloading(fraction: 0))
    }

    @Test func cancellingOrRemovingLeavesNothingDownloaded() {
        #expect(ModelState.downloading(fraction: 0.5).applying(.cancelled) == .notDownloaded)
        for state in [ModelState.ready, .failed("Offline"), .downloading(fraction: 0.2), .notDownloaded] {
            #expect(state.applying(.removed) == .notDownloaded)
        }
    }

    @Test(arguments: [
        (ModelState.ready, ModelState.Event.start), (.ready, .verified), (.ready, .progress(0.5)),
        (.notDownloaded, .verified), (.notDownloaded, .progress(0.5)), (.notDownloaded, .failed("x")),
        (.notDownloaded, .cancelled), (.failed("x"), .verified), (.failed("x"), .cancelled),
        (.downloading(fraction: 0.5), .start),
    ])
    func illegalEventsChangeNothing(state: ModelState, event: ModelState.Event) {
        #expect(state.applying(event) == state)
    }

    @Test func parakeetUltraIsPinned() {
        let model = SpeechModel.parakeetUltra
        #expect(model.url.absoluteString.contains("/resolve/a1539be1b849ea7463b88343e5277b373d0c4ea9/"))
        #expect(model.url.lastPathComponent == model.fileName)
        #expect(model.byteCount == 549_800_864)
        #expect(model.sha256.count == 64)
    }
}
