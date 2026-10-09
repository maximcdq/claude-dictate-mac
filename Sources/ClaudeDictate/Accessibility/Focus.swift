import AppKit

func frame(of element: AXUIElement) -> CGRect? {
    var pos: CFTypeRef?, size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
          let pos, let size else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

// Insertion point in global top-left coordinates, for any app, from the text around the caret:
// - the right edge of the character before it, unless that is a line break (its box sits on the previous line);
// - else the left edge of the character under it, unless that is a line break too;
// - else the empty range at the caret (apps answer that one least reliably, so it comes last).
// Some apps then still place it outside their own field (Telegram: an empty field's caret 11 pt above it); the
// field's frame is right, so the caret is pulled into it.
func caretRect() -> CGRect? {
    guard let element = focusedElement() else { return nil }
    var rangeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
          let rv = rangeRef else { return nil }
    var range = CFRange()
    guard AXValueGetValue(rv as! AXValue, .cfRange, &range) else { return nil }
    let caret = range.location + range.length

    var valueRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
    let text = valueRef as? NSString  // AX ranges count UTF-16 units, as NSString does

    func bounds(_ location: Int, _ length: Int) -> CGRect? {
        var query = CFRange(location: location, length: length)
        guard let q = AXValueCreate(.cfRange, &query) else { return nil }
        var b: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, q, &b) == .success,
              let b else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(b as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }
        return rect
    }
    func isBreak(_ i: Int) -> Bool {
        guard let text, i >= 0, i < text.length else { return false }
        return [10, 13, 0x2028, 0x2029].contains(text.character(at: i))
    }
    // a box taller than a line is the field, not a character: keep one line of it
    func caretLine(x: CGFloat, _ r: CGRect, alignBottom: Bool) -> CGRect {
        let line = min(r.height, 40)
        return CGRect(x: x, y: alignBottom ? r.maxY - line : r.minY, width: 0, height: line)
    }

    var result: CGRect
    if caret > 0, !isBreak(caret - 1), let r = bounds(caret - 1, 1) {
        result = caretLine(x: r.maxX, r, alignBottom: true)
    } else if let text, caret < text.length, !isBreak(caret), let r = bounds(caret, 1) {
        result = caretLine(x: r.minX, r, alignBottom: true)
    } else if let r = bounds(caret, 0) {
        result = caretLine(x: r.minX, r, alignBottom: false)
    } else {
        return nil
    }

    if let field = frame(of: element), field.height > 0,
       !field.insetBy(dx: -2, dy: -2).contains(CGPoint(x: result.minX, y: result.midY)) {
        result.origin.x = min(max(result.minX, field.minX), field.maxX)
        result.origin.y = field.height < result.height * 2.5 ? field.midY - result.height / 2 : field.minY + 2
    }
    return result
}

// Chrome and Electron build their accessibility tree (and so report the focused field) only when asked.
func enableAppAccessibility() {
    guard let app = NSWorkspace.shared.frontmostApplication else { return }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    // Chromium 15x ignores that one and switches its web content off again when unused; the flag VoiceOver sets turns
    // it on. Only for Chromium: to any other app it says a screen reader is running, and some change their behavior
    // for it (window animations, iTerm's hotkey window).
    var focused: CFTypeRef?
    if isChromium(app), AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) != .success {
        AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }
}

// Chrome, Edge, Brave, Arc, Electron apps…: every Chromium-based app ships a "<name> Helper (Renderer).app"
private var chromiumApps: [URL: Bool] = [:]
func isChromium(_ app: NSRunningApplication) -> Bool {
    guard let url = app.bundleURL else { return false }
    if let known = chromiumApps[url] { return known }
    var found = false
    if let walk = FileManager.default.enumerator(at: url.appendingPathComponent("Contents/Frameworks"), includingPropertiesForKeys: nil) {
        for case let item as URL in walk {
            if item.lastPathComponent.hasSuffix("Helper (Renderer).app") { found = true; break }
            if item.pathExtension == "app" || walk.level > 5 { walk.skipDescendants() }
        }
    }
    chromiumApps[url] = found
    return found
}

// The field that has keyboard focus, to notice the user clicking elsewhere mid-dictation.
func focusedElement() -> AXUIElement? {
    var focused: CFTypeRef?
    if AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
       let el = focused { return (el as! AXUIElement) }
    // Chrome at times answers only through its own app element
    guard let app = NSWorkspace.shared.frontmostApplication,
          AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                        kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let el = focused else { return nil }
    return (el as! AXUIElement)
}

func role(of element: AXUIElement?) -> String {
    guard let element else { return "nothing focused" }
    var role: CFTypeRef?, subrole: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
    return [role, subrole].compactMap { $0 as? String }.joined(separator: "/")
}

// Whether the focused element takes typed text: it has a text caret (a selected text range). The desktop, a file
// list, a button have none, so the text goes to the clipboard.
// Whether the element is in sight: its center inside a window of its app that the window server shows, and on a
// screen. A hidden window keeps its app and field focused (iTerm's hotkey window once it slides away, minimized windows),
// and Show Desktop slides the windows off the edges: text typed there would land out of sight. An element that reports
// no frame counts as visible when its app shows any window.
func visibleWindows(of pid: pid_t) -> [CGRect] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
        .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
        .compactMap { ($0[kCGWindowBounds as String] as! CFDictionary?).flatMap { CGRect(dictionaryRepresentation: $0) } }
}

func onScreen(_ element: AXUIElement) -> Bool {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    let windows = visibleWindows(of: pid)
    var pos: CFTypeRef?, size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
          let pos, let size else { return !windows.isEmpty }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    // A terminal reports its whole scrollback as the text area (iTerm: thousands of points tall, reaching far above
    // the window), so its center leaves the window as the history grows. What counts is the part inside a window.
    let frame = CGRect(origin: p, size: s)
    // accessibility and the window server measure from the top-left of the primary screen, AppKit from its bottom-left
    let primary = NSScreen.screens.first?.frame.height ?? 0
    return windows.contains { window in
        let shown = window.intersection(frame)
        guard !shown.isNull, !shown.isEmpty else { return false }
        return NSScreen.screens.contains { $0.frame.contains(CGPoint(x: shown.midX, y: primary - shown.midY)) }
    }
}

// Where the text goes. Like any dictation app it is typed into whatever has focus; only when macOS says for sure that
// nothing there takes text (the desktop, a page with no field active, a hidden window, an app with no window in
// sight) does it go to the clipboard instead. An app that tells nothing about its focus gets the text typed.
enum Focus { case field, noField, unknown }

func focusState(_ element: AXUIElement?) -> Focus {
    if let element { return focusedTakesText(element) ? .field : .noField }
    guard let app = NSWorkspace.shared.frontmostApplication else { return .noField }
    return visibleWindows(of: app.processIdentifier).isEmpty ? .noField : .unknown
}

func focusedTakesText(_ element: AXUIElement?) -> Bool {
    guard let element, onScreen(element) else { return false }
    if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(where: { role(of: element).hasPrefix($0) }) {
        return true
    }
    var value: CFTypeRef?
    // a web page reports a caret on every element (text can be selected anywhere): there only an element inside an
    // editable one takes text (inputs, contenteditable editors); typed elsewhere, letters fire the page's shortcuts
    if AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &value) == .success, value != nil {
        return true
    }
    if inWebArea(element) { return false }
    // a caret alone counts only on an element of no standard role (a custom text view): Chrome's toolbar buttons and
    // groups report one too
    let nonText = ["AXButton", "AXGroup", "AXLink", "AXStaticText", "AXImage", "AXList", "AXTable", "AXOutline", "AXRow",
                   "AXCell", "AXScrollArea", "AXToolbar", "AXWindow", "AXMenu", "AXCheckBox", "AXRadioButton",
                   "AXPopUpButton", "AXTabGroup", "AXSplitGroup", "AXSlider", "AXApplication"]
    if nonText.contains(where: { role(of: element).hasPrefix($0) }) { return false }
    return AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success && value != nil
}

func inWebArea(_ element: AXUIElement) -> Bool {
    var current: AXUIElement? = element
    for _ in 0..<60 {
        guard let e = current else { return false }
        if role(of: e).hasPrefix("AXWebArea") { return true }
        var parent: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXParentAttribute as CFString, &parent) == .success, let parent else { return false }
        current = (parent as! AXUIElement)
    }
    return false
}
