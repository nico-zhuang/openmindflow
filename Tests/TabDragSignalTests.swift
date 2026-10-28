import AppKit

@main enum TabDragSignalTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let suite = "local.openmindflow.tab-drag.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = AppDelegate(defaults: defaults)
        let source = app.makeUnshownWindowSession(), destination = app.makeUnshownWindowSession()
        let document = source.active!, retained = destination.active!
        let transfer = app.tabTransfer
        let oldMenu = NSApp.mainMenu
        let keyboard = TrackingShortcutProbe()
        let menu = NSMenu()
        let top = NSMenuItem(title: "Tracking Fixture", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let shortcut = NSMenuItem(title: "Shortcut Fixture", action: #selector(TrackingShortcutProbe.fire(_:)),
                                  keyEquivalent: "g")
        shortcut.keyEquivalentModifierMask = [.command]
        shortcut.target = keyboard
        submenu.addItem(shortcut)
        menu.addItem(top)
        menu.setSubmenu(submenu, for: top)
        NSApp.mainMenu = menu
        defer { NSApp.mainMenu = oldMenu }
        let title = source.tabStrip.subviews.first { $0.subviews.count == 2 &&
            $0.subviews[0] is NSButton }!.subviews[0] as! NSButton
        let point = title.convert(CGPoint(x: 8, y: 8), to: nil)
        let shortcutKey = NSEvent.keyEvent(with: .keyDown, location: point, modifierFlags: [.command],
            timestamp: 200, windowNumber: source.window.windowNumber, context: nil,
            characters: "g", charactersIgnoringModifiers: "g", isARepeat: false, keyCode: 5)!
        NSApp.sendEvent(shortcutKey)
        assert(keyboard.invocations == 1, "AppKit normally dispatches this Cmd shortcut")
        keyboard.invocations = 0
        let pointerDown = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: 199, windowNumber: source.window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        let pointerUp = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: 201, windowNumber: source.window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 1)!
        NSApp.postEvent(pointerUp, atStart: false)
        NSApp.postEvent(shortcutKey, atStart: true)
        title.mouseDown(with: pointerDown)
        assert(keyboard.invocations == 1,
               "pointer tracking must route an intercepted Cmd shortcut through normal AppKit dispatch")
        let farAway = CGPoint(x: 50_000, y: 50_000)
        func unchanged(_ reason: String, windows count: Int = 2) {
            assert(app.windowSessions.count == count, reason)
            assert(source.documents.count == 1 && source.documents[0] === document &&
                   document.window === source.window && destination.documents[0] === retained, reason)
        }
        func event(_ type: NSEvent.EventType, timestamp: TimeInterval, keyCode: UInt16 = 0,
                   windowNumber: Int? = nil) -> NSEvent {
            if type == .keyDown {
                return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: timestamp, windowNumber: windowNumber ?? source.window.windowNumber, context: nil,
                    characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                    keyCode: keyCode)!
            }
            return NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: timestamp, windowNumber: windowNumber ?? source.window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let equalTimestamp = DragReleaseSignal()
        let equalToken = UUID()
        equalTimestamp.arm(token: equalToken, after: 100,
                           sourceWindowNumber: source.window.windowNumber)
        equalTimestamp.observeDequeued(event(.keyDown, timestamp: 100, keyCode: 53))
        equalTimestamp.observeDequeued(event(.leftMouseUp, timestamp: 101))
        assert(!equalTimestamp.positivelyReleased(token: equalToken),
               "a dequeued Escape at drag-start timestamp vetoes later source-window mouse-up")
        let signal = DragReleaseSignal()
        let unknown = transfer.begin(document: document, source: source)
        signal.arm(token: unknown, after: 10, sourceWindowNumber: source.window.windowNumber)
        assert(!transfer.finish(token: unknown, locationOnScreen: farAway, operation: [], signal: signal))
        unchanged(".none without a positively dequeued release is not a tear-off")
        signal.observeDequeued(event(.leftMouseUp, timestamp: 9))
        assert(!transfer.finish(token: unknown, locationOnScreen: farAway, operation: [], signal: signal))
        unchanged("mouse-up from before drag start cannot authorize tear-off")
        signal.observeDequeued(event(.keyDown, timestamp: 11, keyCode: 53))
        signal.observeDequeued(event(.leftMouseUp, timestamp: 12))
        assert(!transfer.finish(token: unknown, locationOnScreen: farAway, operation: [], signal: signal))
        unchanged("Escape while active cannot be overridden by a later mouse-up")
        signal.disarm(token: unknown)
        transfer.cancel(token: unknown)
        signal.arm(token: unknown, after: 13, sourceWindowNumber: source.window.windowNumber)
        signal.observeDequeued(event(.leftMouseUp, timestamp: 14))
        assert(!signal.positivelyReleased(token: unknown),
               "Escape permanently vetoes this token even after a mistaken rearm")
        signal.disarm(token: unknown)

        let missing = UUID()
        let release = transfer.begin(document: document, source: source)
        signal.arm(token: release, after: 20, sourceWindowNumber: source.window.windowNumber)
        signal.observeDequeued(event(.leftMouseUp, timestamp: 21))
        assert(!transfer.finish(token: missing, locationOnScreen: farAway, operation: [], signal: signal))
        unchanged("foreign token cannot borrow a verified release")
        assert(!transfer.finish(token: release, locationOnScreen: farAway, operation: .move, signal: signal))
        unchanged("successful operation marker must not tear off")
        signal.disarm(token: release)
        let insideToken = transfer.begin(document: document, source: source)
        signal.arm(token: insideToken, after: 22, sourceWindowNumber: source.window.windowNumber)
        signal.observeDequeued(event(.leftMouseUp, timestamp: 23))
        let stripScreen = source.window.convertToScreen(source.tabStrip.convert(source.tabStrip.bounds, to: nil))
        assert(!stripScreen.isEmpty &&
               !transfer.finish(token: insideToken, locationOnScreen: CGPoint(x: stripScreen.midX,
                   y: stripScreen.midY), operation: [], signal: signal))
        unchanged("confirmed mouse-up over an eligible strip must not tear off")
        signal.disarm(token: insideToken)
        let canvasToken = transfer.begin(document: document, source: source)
        signal.arm(token: canvasToken, after: 24, sourceWindowNumber: source.window.windowNumber)
        signal.observeDequeued(event(.leftMouseUp, timestamp: 24.5))
        let canvasScreen = CGPoint(x: source.window.frame.midX, y: source.window.frame.midY)
        assert(!transfer.finish(token: canvasToken, locationOnScreen: canvasScreen,
                                operation: [], signal: signal),
               "release on a document canvas is not a tearoff even though it is outside the tab strip")
        unchanged("canvas drop cannot create a registered tearoff window")
        signal.disarm(token: canvasToken)
        let unrelated = transfer.begin(document: document, source: source)
        let unrelatedSignal = DragReleaseSignal()
        unrelatedSignal.arm(token: unrelated, after: 25, sourceWindowNumber: source.window.windowNumber)
        unrelatedSignal.observeDequeued(event(.leftMouseUp, timestamp: 26,
                                               windowNumber: destination.window.windowNumber))
        assert(!transfer.finish(token: unrelated, locationOnScreen: farAway,
                                operation: [], signal: unrelatedSignal))
        unchanged("another window's mouse-up cannot authorize this source tab tearoff")
        unrelatedSignal.disarm(token: unrelated)
        let auxiliary = SyntheticVisibleAuxiliaryWindow(contentRect:
            CGRect(x: 45_000, y: 45_000, width: 320, height: 220), styleMask: [.titled],
            backing: .buffered, defer: false)
        auxiliary.isReleasedWhenClosed = false
        assert(NSApp.windows.contains(where: { $0 === auxiliary }) && auxiliary.isVisible,
               "fixture represents a visible auxiliary app window without ordering it")
        let auxiliaryToken = transfer.begin(document: document, source: source)
        let auxiliarySignal = DragReleaseSignal()
        auxiliarySignal.arm(token: auxiliaryToken, after: 27,
                            sourceWindowNumber: source.window.windowNumber)
        auxiliarySignal.observeDequeued(event(.leftMouseUp, timestamp: 28))
        let auxiliaryPoint = CGPoint(x: auxiliary.frame.midX, y: auxiliary.frame.midY)
        assert(!transfer.finish(token: auxiliaryToken, locationOnScreen: auxiliaryPoint,
                                operation: [], signal: auxiliarySignal),
               "release over visible Settings/Find/Color-like app window is not a desktop tearoff")
        unchanged("auxiliary app window cannot create a new document window")
        auxiliarySignal.disarm(token: auxiliaryToken)
        auxiliary.close()

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("local.openmindflow.test.\(UUID())"))
        let malformed = UUID()
        pasteboard.clearContents()
        pasteboard.setData(Data("not-a-uuid".utf8), forType: DocumentTabTransfer.pasteboardType)
        assert(destination.tabStrip.token(from: pasteboard) == nil)
        pasteboard.clearContents()
        pasteboard.setData(Data(malformed.uuidString.utf8), forType: DocumentTabTransfer.pasteboardType)
        assert(destination.tabStrip.token(from: pasteboard) == nil,
               "a syntactically correct foreign pasteboard token has no process-local membership")
        let pending = transfer.begin(document: document, source: source)
        pasteboard.clearContents()
        pasteboard.setData(Data(pending.uuidString.utf8), forType: DocumentTabTransfer.pasteboardType)
        assert(destination.tabStrip.token(from: pasteboard) == pending)
        let snapshot = destination.documents
        assert(destination.tabStrip.previewInsertion(token: pending, at: CGPoint(x: 0, y: 10)) == 0)
        assert(destination.documents.count == snapshot.count && destination.documents[0] === snapshot[0])
        destination.tabStrip.cancelInsertionPreview()
        assert(destination.tabStrip.previewIndex == nil,
               "cancel removes visual insertion preview without mutating membership")
        assert(!destination.tabStrip.accept(token: pending, at: CGPoint(x: 4000, y: 4000)),
               "drop outside the strip/canvas cannot adopt a token")
        unchanged("canvas-like off-strip drop must fail closed")
        transfer.cancel(token: pending)
        assert(destination.tabStrip.token(from: pasteboard) == nil,
               "canceled token retained on a pasteboard must not be replayed")
        assert(!document.canvas.registeredDraggedTypes.contains(DocumentTabTransfer.pasteboardType),
               "canvas accepts media, never document-tab pasteboard tokens")

        let disappearing = app.makeUnshownWindowSession()
        let abandoned = transfer.begin(document: document, source: source)
        assert(disappearing.tabStrip.previewInsertion(token: abandoned, at: CGPoint(x: 4, y: 4)) == 0)
        disappearing.window.close()
        assert(!disappearing.tabStrip.accept(token: abandoned, at: CGPoint(x: 4, y: 4)))
        transfer.cancel(token: abandoned)
        unchanged("destination closed after preview must leave source document untouched")
        let staleSource = transfer.begin(document: document, source: source)
        source.remove(document)
        source.insert(document)
        pasteboard.clearContents()
        pasteboard.setData(Data(staleSource.uuidString.utf8), forType: DocumentTabTransfer.pasteboardType)
        assert(transfer.liveSource(for: staleSource) == nil &&
               destination.tabStrip.token(from: pasteboard) == nil,
               "reinserted document must not revive token from old source generation")
        unchanged("source ownership generation changes invalidate an old drag token")
        transfer.cancel(token: staleSource)

        let accepted = transfer.begin(document: document, source: source)
        pasteboard.clearContents()
        pasteboard.setData(Data(accepted.uuidString.utf8), forType: DocumentTabTransfer.pasteboardType)
        let dropPoint = destination.tabStrip.convert(CGPoint(x: 4, y: 4), to: nil)
        let foreignDrag = SyntheticTabDraggingInfo(window: destination.window, pasteboard: pasteboard,
                                                  source: NSView(frame: .zero), location: dropPoint)
        assert(destination.tabStrip.draggingEntered(foreignDrag).isEmpty &&
               !destination.tabStrip.performDragOperation(foreignDrag),
               "copied valid token with foreign draggingSource must not be accepted")
        unchanged("foreign drag source may not forge private token drop")
        let nativeDrag = SyntheticTabDraggingInfo(window: destination.window, pasteboard: pasteboard,
                                                 source: source.tabStrip, location: dropPoint)
        assert(destination.tabStrip.draggingEntered(nativeDrag) == .move)
        let successful = destination.tabStrip.performDragOperation(nativeDrag)
        assert(successful && destination.documents.contains(where: { $0 === document }))
        let count = app.windowSessions.count
        let afterDrop = DragReleaseSignal()
        afterDrop.arm(token: accepted, after: 30, sourceWindowNumber: source.window.windowNumber)
        afterDrop.observeDequeued(event(.leftMouseUp, timestamp: 31))
        assert(!transfer.finish(token: accepted, locationOnScreen: farAway, operation: [], signal: afterDrop))
        assert(app.windowSessions.count == count && destination.documents.contains(where: { $0 === document }),
               "successful destination transfer consumes token before source endedAt")

        let tearSource = app.makeUnshownWindowSession()
        let tearDocument = tearSource.active!
        let rejectedToken = transfer.begin(document: tearDocument, source: tearSource)
        let rejectedSignal = DragReleaseSignal()
        rejectedSignal.arm(token: rejectedToken, after: 35, sourceWindowNumber: tearSource.window.windowNumber)
        rejectedSignal.observeDequeued(event(.leftMouseUp, timestamp: 36,
                                             windowNumber: tearSource.window.windowNumber))
        let factoryBefore = transfer.createEmptyWindow
        let eligibleBefore = transfer.eligibleWindows
        let windowsBeforeRejected = app.windowSessions.count
        var factoryCreated: WindowSession?
        var eligibilityChecks = 0
        transfer.createEmptyWindow = { let created = factoryBefore?(); factoryCreated = created; return created }
        transfer.eligibleWindows = {
            eligibilityChecks += 1
            return eligibilityChecks == 1 ? app.windowSessions : app.windowSessions.filter { $0 !== factoryCreated }
        }
        assert(!transfer.finish(token: rejectedToken, locationOnScreen: farAway,
                                operation: [], signal: rejectedSignal))
        assert(factoryCreated != nil && app.windowSessions.count == windowsBeforeRejected &&
               tearSource.documents[0] === tearDocument,
               "new empty factory window must be closed when its eligibility disappears")
        transfer.eligibleWindows = eligibleBefore
        transfer.createEmptyWindow = factoryBefore
        rejectedSignal.disarm(token: rejectedToken)
        let newToken = transfer.begin(document: tearDocument, source: tearSource)
        let confirmed = DragReleaseSignal()
        confirmed.arm(token: newToken, after: 40, sourceWindowNumber: tearSource.window.windowNumber)
        confirmed.observeDequeued(event(.leftMouseUp, timestamp: 41,
                                        windowNumber: tearSource.window.windowNumber))
        let windowsBefore = app.windowSessions.count
        assert(transfer.finish(token: newToken, locationOnScreen: farAway, operation: [], signal: confirmed))
        let owner = app.windowSessions.single { $0.documents.contains(where: { $0 === tearDocument }) }
        assert(owner != nil && owner !== tearSource && owner?.documents.count == 1 &&
               owner?.active === tearDocument && tearDocument.window === owner?.window &&
               app.resolveSession(for: owner?.window) === tearDocument &&
               app.windowSessions.count == windowsBefore,
               "tearoff must use registered empty factory window and transfer exact session")
        assert(!transfer.finish(token: newToken, locationOnScreen: farAway, operation: [], signal: confirmed))
        let vanishedSource = app.makeUnshownWindowSession()
        let vanishedToken = transfer.begin(document: vanishedSource.active!, source: vanishedSource)
        let vanishedWindowNumber = vanishedSource.window.windowNumber
        vanishedSource.window.close()
        let afterSourceClose = DragReleaseSignal()
        afterSourceClose.arm(token: vanishedToken, after: 50, sourceWindowNumber: vanishedWindowNumber)
        afterSourceClose.observeDequeued(event(.leftMouseUp, timestamp: 51,
                                               windowNumber: vanishedWindowNumber))
        let countAfterClose = app.windowSessions.count
        assert(!transfer.finish(token: vanishedToken, locationOnScreen: farAway,
                                operation: [], signal: afterSourceClose) &&
               app.windowSessions.count == countAfterClose,
               "closed source cannot create a tearoff even with matching release event")
        let closingSource = app.makeUnshownWindowSession()
        let closingToken = closingSource.tabStrip.armNativeDrag(
            document: closingSource.active!, source: closingSource, after: 60)!
        assert(DocumentDragApplication.activeReleaseSignal != nil)
        assert(destination.tabStrip.previewInsertion(token: closingToken, at: CGPoint(x: 4, y: 4)) != nil)
        assert(destination.tabStrip.previewIndex != nil)
        closingSource.window.close() // Simulate interrupted source without NSDraggingSource.endedAt.
        assert(DocumentDragApplication.activeReleaseSignal == nil &&
               transfer.liveSource(for: closingToken) == nil &&
               destination.tabStrip.previewIndex == nil,
               "source close must disarm token, signal and all insertion previews without endedAt")
        let nextSource = app.makeUnshownWindowSession()
        let nextToken = nextSource.tabStrip.armNativeDrag(
            document: nextSource.active!, source: nextSource, after: 70)
        assert(nextToken != nil && DocumentDragApplication.activeReleaseSignal != nil,
               "after interrupted source closes, another independent tab drag may arm")
        nextSource.window.close()
        assert(DocumentDragApplication.activeReleaseSignal == nil)
        print("offscreen token-only drag, dequeued-release gate, cancel, destination and tearoff passed; physical production drag not tested")
    }
}

/// Offscreen window whose visibility getter models a Settings/Find/Color panel; never ordered.
private final class SyntheticVisibleAuxiliaryWindow: NSWindow {
    override var isVisible: Bool { true }
}

private final class TrackingShortcutProbe: NSObject {
    var invocations = 0
    @objc func fire(_ sender: Any?) { invocations += 1 }
}

private extension Array {
    func single(_ matches: (Element) -> Bool) -> Element? {
        let items = filter(matches)
        return items.count == 1 ? items[0] : nil
    }
}

/// A deliberately synthetic destination argument; it does not model a physical AppKit drag session.
private final class SyntheticTabDraggingInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingSourceOperationMask: NSDragOperation = .move
    let draggingLocation: NSPoint
    let draggedImageLocation: NSPoint = .zero
    let draggedImage: NSImage? = nil
    let draggingPasteboard: NSPasteboard
    let draggingSource: Any?
    let draggingSequenceNumber: Int = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight = .none

    init(window: NSWindow, pasteboard: NSPasteboard, source: Any?, location: CGPoint) {
        draggingDestinationWindow = window
        draggingPasteboard = pasteboard
        draggingSource = source
        draggingLocation = location
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}
