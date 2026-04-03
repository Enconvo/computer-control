import ApplicationServices
import CoreGraphics
import Foundation
import AppKit

// MARK: - JSON Helpers

func jsonString(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
          let str = String(data: data, encoding: .utf8) else { return "{}" }
    return str
}

func parseJSON(_ str: String) -> [String: Any]? {
    guard let data = str.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return obj
}

// MARK: - Element Cache

var elementCache: [Int: AXUIElement] = [:]
var elementMetadata: [Int: [String: Any]] = [:]
var cachedAppName: String = ""
var cachedPid: pid_t = 0

func clearCache() {
    elementCache.removeAll()
    elementMetadata.removeAll()
}

// MARK: - AX Attribute Helpers

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return err == .success ? value : nil
}

func axStringValue(_ element: AXUIElement, _ attribute: String) -> String? {
    guard let val = axValue(element, attribute) else { return nil }
    return val as? String
}

func axBoolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
    guard let val = axValue(element, attribute) else { return nil }
    if let n = val as? NSNumber { return n.boolValue }
    return nil
}

func axPointValue(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let val = axValue(element, attribute) else { return nil }
    var point = CGPoint.zero
    if AXValueGetValue(val as! AXValue, .cgPoint, &point) { return point }
    return nil
}

func axSizeValue(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    guard let val = axValue(element, attribute) else { return nil }
    var size = CGSize.zero
    if AXValueGetValue(val as! AXValue, .cgSize, &size) { return size }
    return nil
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    guard let val = axValue(element, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
    return val
}

func axActions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    let err = AXUIElementCopyActionNames(element, &names)
    guard err == .success, let arr = names as? [String] else { return [] }
    return arr
}

func axPerformAction(_ element: AXUIElement, _ action: String) -> Bool {
    return AXUIElementPerformAction(element, action as CFString) == .success
}

func axSetValue(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
    return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
}

// MARK: - Interactive Role Detection

let interactiveRoles: Set<String> = [
    "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
    "AXPopUpButton", "AXComboBox", "AXSlider", "AXMenuItem", "AXMenuButton",
    "AXLink", "AXIncrementor", "AXColorWell", "AXTabGroup", "AXTab",
    "AXDisclosureTriangle", "AXToolbar", "AXOutline", "AXTable", "AXRow",
    "AXCell", "AXSwitch", "AXSegmentedControl", "AXSearchField", "AXMenuBarItem",
]

let contextRoles: Set<String> = ["AXStaticText", "AXImage", "AXHeading"]

/// Layout roles that cost zero semantic depth (from ghost-os)
let layoutRoles: Set<String> = [
    "AXGroup", "AXGenericElement", "AXSection", "AXDiv",
    "AXList", "AXLandmarkMain", "AXLandmarkNavigation",
    "AXLandmarkBanner", "AXLandmarkContentInfo",
]

/// Clear stuck modifier flags after hotkey operations (from ghost-os)
func clearModifierFlags() {
    if let event = CGEvent(source: nil) {
        event.type = .flagsChanged
        event.flags = CGEventFlags(rawValue: 0)
        event.post(tap: .cghidEventTap)
    }
}

// MARK: - Snapshot

func buildSnapshot(appElement: AXUIElement, pid: pid_t, interactiveOnly: Bool, maxDepth: Int) -> [String: Any] {
    clearCache()
    cachedPid = pid

    // Per-element timeout: prevent hung Chrome/Electron elements from blocking (ghost-os pattern)
    AXUIElementSetMessagingTimeout(appElement, 3.0)
    defer { AXUIElementSetMessagingTimeout(appElement, 0) }

    var eIndex = 0
    var lines: [String] = []
    var elMap: [String: Any] = [:]

    func traverse(_ element: AXUIElement, semanticDepth: Int, indent: Int) {
        if semanticDepth > maxDepth { return }

        guard let role = axStringValue(element, kAXRoleAttribute), !role.isEmpty else { return }

        let name = axStringValue(element, kAXTitleAttribute) ?? axStringValue(element, kAXDescriptionAttribute) ?? ""
        let value = axStringValue(element, kAXValueAttribute)
        let desc = axStringValue(element, kAXDescriptionAttribute) ?? ""
        let subrole = axStringValue(element, kAXSubroleAttribute) ?? ""
        let enabled = axBoolValue(element, kAXEnabledAttribute) ?? true
        let pos = axPointValue(element, kAXPositionAttribute) ?? .zero
        let size = axSizeValue(element, kAXSizeAttribute) ?? .zero

        let isInteractive = interactiveRoles.contains(role)
        let isContext = contextRoles.contains(role)

        let displayRole = role.hasPrefix("AX") ? String(role.dropFirst(2)).lowercased() : role.lowercased()
        var label = ""
        if !name.isEmpty { label += " \"\(name)\"" }
        if let v = value, !v.isEmpty, v.count < 100 { label += " value=\"\(v)\"" }
        if !desc.isEmpty && desc != name { label += " desc=\"\(desc)\"" }
        if !enabled { label += " [disabled]" }

        let prefix = String(repeating: "  ", count: indent)

        if isInteractive {
            let idx = eIndex
            eIndex += 1
            lines.append("\(prefix)@e\(idx) [\(displayRole)]\(label)")

            // Cache the actual AXUIElement reference
            elementCache[idx] = element
            elementMetadata[idx] = [
                "index": idx,
                "role": role,
                "name": name,
                "value": value as Any,
                "description": desc,
                "bounds": [pos.x, pos.y, size.width, size.height],
                "enabled": enabled,
                "subrole": subrole,
                "pid": pid,
            ]
            elMap[String(idx)] = elementMetadata[idx]
        } else if !interactiveOnly && (isContext || semanticDepth <= 3) {
            lines.append("\(prefix)[\(displayRole)]\(label)")
        }

        // Semantic depth tunneling (ghost-os pattern):
        // Empty layout containers (AXGroup, AXDiv, etc.) cost 0 depth
        let hasSemanticContent: Bool
        if layoutRoles.contains(role) {
            hasSemanticContent = !name.isEmpty || !desc.isEmpty
        } else {
            hasSemanticContent = true
        }
        let childDepth = hasSemanticContent ? semanticDepth + 1 : semanticDepth

        // Recurse children
        let children = axChildren(element)
        let limit = min(children.count, 150)
        for i in 0..<limit {
            let childIndent = (isInteractive || isContext || semanticDepth <= 3) ? indent + 1 : indent
            traverse(children[i], semanticDepth: childDepth, indent: childIndent)
        }
    }

    // Get windows
    guard let windows = axValue(appElement, kAXWindowsAttribute) as? [AXUIElement] else {
        return ["error": "Could not access windows"]
    }

    var windowTitle = ""
    var windowBounds: [CGFloat]? = nil

    if let firstWindow = windows.first {
        windowTitle = axStringValue(firstWindow, kAXTitleAttribute) ?? ""
        if let wp = axPointValue(firstWindow, kAXPositionAttribute),
           let ws = axSizeValue(firstWindow, kAXSizeAttribute) {
            windowBounds = [wp.x, wp.y, ws.width, ws.height]
        }
    }

    for (i, window) in windows.enumerated() {
        let wt = axStringValue(window, kAXTitleAttribute) ?? ""
        let windowLabel = windows.count > 1 ? "[window \(i)]" : "[window]"
        lines.append("\(windowLabel)\(wt.isEmpty ? "" : " \"\(wt)\"")")
        traverse(window, semanticDepth: 0, indent: 1)
    }

    // Menu bar
    if let menuBarRef = axValue(appElement, kAXMenuBarAttribute) {
        // CFTypeRef -> AXUIElement (both are CFTypeRef-based)
        let menuBar = (menuBarRef as AnyObject) as! AXUIElement
        let menuItems = axChildren(menuBar)
        if !menuItems.isEmpty {
            lines.append("[menubar]")
            for item in menuItems.prefix(20) {
                traverse(item, semanticDepth: 0, indent: 1)
            }
        }
    }

    return [
        "success": true,
        "app": cachedAppName,
        "pid": pid,
        "tree": lines.joined(separator: "\n"),
        "interactiveCount": eIndex,
        "elementMap": elMap,
        "windowTitle": windowTitle,
        "windowBounds": windowBounds as Any,
    ]
}

// MARK: - Get App Element

func getAppElement(params: [String: Any]) -> (AXUIElement, pid_t, String)? {
    if let pid = params["pid"] as? Int {
        let p = pid_t(pid)
        let app = AXUIElementCreateApplication(p)
        let name = axStringValue(app, kAXTitleAttribute) ?? NSRunningApplication(processIdentifier: p)?.localizedName ?? "Unknown"
        cachedAppName = name
        return (app, p, name)
    }

    if let appName = params["appName"] as? String {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == appName || $0.bundleIdentifier?.contains(appName) == true
        }
        if let app = apps.first, let p = Optional(app.processIdentifier) {
            let ax = AXUIElementCreateApplication(p)
            cachedAppName = app.localizedName ?? appName
            return (ax, p, cachedAppName)
        }
        return nil
    }

    // Frontmost app
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
    let p = frontApp.processIdentifier
    let ax = AXUIElementCreateApplication(p)
    cachedAppName = frontApp.localizedName ?? "Unknown"
    return (ax, p, cachedAppName)
}

// MARK: - Command Handlers

func handleSnapshot(_ params: [String: Any]) -> [String: Any] {
    guard let (appEl, pid, _) = getAppElement(params: params) else {
        return ["success": false, "error": "Application not found"]
    }
    let interactiveOnly = params["interactiveOnly"] as? Bool ?? false
    let maxDepth = params["maxDepth"] as? Int ?? 25
    return buildSnapshot(appElement: appEl, pid: pid, interactiveOnly: interactiveOnly, maxDepth: maxDepth)
}

func handleClick(_ params: [String: Any]) -> [String: Any] {
    guard let index = params["index"] as? Int,
          let element = elementCache[index] else {
        return ["success": false, "error": "Element not found in cache. Run snapshot first."]
    }
    let button = params["button"] as? String ?? "left"

    if button == "right" {
        if axPerformAction(element, "AXShowMenu") {
            return ["success": true, "action": "rightClick"]
        }
        // Fallback to CGEvent right-click
        if let pos = axPointValue(element, kAXPositionAttribute),
           let size = axSizeValue(element, kAXSizeAttribute) {
            let cx = pos.x + size.width / 2
            let cy = pos.y + size.height / 2
            let point = CGPoint(x: cx, y: cy)
            if let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right),
               let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) {
                down.post(tap: .cghidEventTap)
                usleep(50000)
                up.post(tap: .cghidEventTap)
                return ["success": true, "action": "rightClick", "x": cx, "y": cy]
            }
        }
        return ["success": false, "error": "Right-click failed"]
    }

    // Left click: try AXPress first
    if axPerformAction(element, kAXPressAction) {
        return ["success": true, "action": "click"]
    }

    // Fallback to CGEvent click
    if let pos = axPointValue(element, kAXPositionAttribute),
       let size = axSizeValue(element, kAXSizeAttribute) {
        let cx = pos.x + size.width / 2
        let cy = pos.y + size.height / 2
        let point = CGPoint(x: cx, y: cy)
        if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
           let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
            usleep(50000)
            up.post(tap: .cghidEventTap)
            return ["success": true, "action": "click", "x": cx, "y": cy]
        }
    }
    return ["success": false, "error": "Click failed"]
}

func handleSetValue(_ params: [String: Any]) -> [String: Any] {
    guard let index = params["index"] as? Int,
          let element = elementCache[index] else {
        return ["success": false, "error": "Element not found in cache"]
    }
    let value = params["value"] as? String ?? ""
    if axSetValue(element, kAXValueAttribute, value as CFString) {
        return ["success": true, "action": "setValue", "value": value]
    }
    // Try focused + keystroke fallback
    _ = axSetValue(element, kAXFocusedAttribute, kCFBooleanTrue)
    // Select all then type
    return ["success": false, "error": "setValue failed. Try type instead."]
}

func handleFocus(_ params: [String: Any]) -> [String: Any] {
    guard let index = params["index"] as? Int,
          let element = elementCache[index] else {
        return ["success": false, "error": "Element not found in cache"]
    }
    if axSetValue(element, kAXFocusedAttribute, kCFBooleanTrue) {
        return ["success": true, "action": "focus"]
    }
    // Fallback: try clicking
    if axPerformAction(element, kAXPressAction) {
        return ["success": true, "action": "focus (via click)"]
    }
    return ["success": false, "error": "Focus failed"]
}

func handleGetInfo(_ params: [String: Any]) -> [String: Any] {
    guard let index = params["index"] as? Int,
          let element = elementCache[index] else {
        return ["success": false, "error": "Element not found in cache"]
    }
    let role = axStringValue(element, kAXRoleAttribute) ?? ""
    let subrole = axStringValue(element, kAXSubroleAttribute) ?? ""
    let name = axStringValue(element, kAXTitleAttribute) ?? ""
    let value = axStringValue(element, kAXValueAttribute)
    let desc = axStringValue(element, kAXDescriptionAttribute) ?? ""
    let enabled = axBoolValue(element, kAXEnabledAttribute) ?? true
    let focused = axBoolValue(element, kAXFocusedAttribute) ?? false
    let pos = axPointValue(element, kAXPositionAttribute) ?? .zero
    let size = axSizeValue(element, kAXSizeAttribute) ?? .zero
    let children = axChildren(element).count
    let actions = axActions(element)

    return [
        "success": true,
        "role": role, "subrole": subrole,
        "name": name, "title": name, "value": value as Any, "description": desc,
        "enabled": enabled, "focused": focused,
        "position": [pos.x, pos.y], "size": [size.width, size.height],
        "childCount": children, "actions": actions,
    ]
}

func handleGetText(_ params: [String: Any]) -> [String: Any] {
    guard let index = params["index"] as? Int,
          let element = elementCache[index] else {
        return ["success": false, "error": "Element not found in cache"]
    }
    let text = axStringValue(element, kAXValueAttribute)
        ?? axStringValue(element, kAXTitleAttribute)
        ?? axStringValue(element, kAXDescriptionAttribute)
        ?? ""
    return ["success": true, "text": text]
}

func handlePerformAction(_ params: [String: Any]) -> [String: Any] {
    guard let index = params["index"] as? Int,
          let element = elementCache[index],
          let actionName = params["actionName"] as? String else {
        return ["success": false, "error": "Missing index or actionName"]
    }
    if axPerformAction(element, actionName) {
        return ["success": true, "action": actionName]
    }
    return ["success": false, "error": "Action \(actionName) failed"]
}

func handleMouse(_ params: [String: Any]) -> [String: Any] {
    guard let action = params["action"] as? String,
          let x = params["x"] as? Double,
          let y = params["y"] as? Double else {
        return ["success": false, "error": "Missing action, x, or y"]
    }
    let point = CGPoint(x: x, y: y)

    switch action {
    case "click":
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return ["success": false, "error": "Failed to create CGEvent"]
        }
        down.post(tap: .cghidEventTap)
        usleep(50000)
        up.post(tap: .cghidEventTap)

    case "doubleClick":
        guard let d1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let u1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left),
              let d2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let u2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return ["success": false, "error": "Failed to create CGEvent"]
        }
        d1.setIntegerValueField(.mouseEventClickState, value: 1)
        u1.setIntegerValueField(.mouseEventClickState, value: 1)
        d2.setIntegerValueField(.mouseEventClickState, value: 2)
        u2.setIntegerValueField(.mouseEventClickState, value: 2)
        d1.post(tap: .cghidEventTap); u1.post(tap: .cghidEventTap)
        usleep(50000)
        d2.post(tap: .cghidEventTap); u2.post(tap: .cghidEventTap)

    case "rightClick":
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right),
              let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) else {
            return ["success": false, "error": "Failed to create CGEvent"]
        }
        down.post(tap: .cghidEventTap)
        usleep(50000)
        up.post(tap: .cghidEventTap)

    case "move":
        guard let evt = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            return ["success": false, "error": "Failed to create CGEvent"]
        }
        evt.post(tap: .cghidEventTap)

    case "mouseDown":
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) else {
            return ["success": false, "error": "Failed to create CGEvent"]
        }
        down.post(tap: .cghidEventTap)

    case "mouseUp":
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return ["success": false, "error": "Failed to create CGEvent"]
        }
        up.post(tap: .cghidEventTap)

    default:
        return ["success": false, "error": "Unknown mouse action: \(action)"]
    }

    return ["success": true, "action": action, "x": x, "y": y]
}

func handleScroll(_ params: [String: Any]) -> [String: Any] {
    let direction = params["direction"] as? String ?? "down"
    let amount = params["amount"] as? Int32 ?? 3

    var deltaY: Int32 = 0, deltaX: Int32 = 0
    switch direction {
    case "up": deltaY = amount
    case "down": deltaY = -amount
    case "left": deltaX = amount
    case "right": deltaX = -amount
    default: break
    }

    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0) else {
        return ["success": false, "error": "Failed to create scroll event"]
    }
    event.post(tap: .cghidEventTap)
    return ["success": true, "direction": direction, "amount": amount]
}

func handlePress(_ params: [String: Any]) -> [String: Any] {
    guard let key = params["key"] as? String else {
        return ["success": false, "error": "Missing key"]
    }
    let modifiers = params["modifiers"] as? [String] ?? []

    let keyCodeMap: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "forwarddelete": 117,
    ]

    // Build modifier flags
    var flags: CGEventFlags = []
    for mod in modifiers {
        switch mod.lowercased() {
        case "command", "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "option", "alt": flags.insert(.maskAlternate)
        case "control", "ctrl": flags.insert(.maskControl)
        default: break
        }
    }

    let lowerKey = key.lowercased()
    if let code = keyCodeMap[lowerKey] {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            return ["success": false, "error": "Failed to create key event"]
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    } else if key.count == 1, let scalar = key.unicodeScalars.first {
        // Use CGEvent with unicode character
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            return ["success": false, "error": "Failed to create key event"]
        }
        var char = UniChar(scalar.value)
        down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
        up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    } else {
        return ["success": false, "error": "Unknown key: \(key)"]
    }

    // Clear modifier flags to prevent stickiness (ghost-os pattern)
    if !modifiers.isEmpty { clearModifierFlags() }

    return ["success": true, "key": key, "modifiers": modifiers]
}

func handleType(_ params: [String: Any]) -> [String: Any] {
    guard let text = params["text"] as? String else {
        return ["success": false, "error": "Missing text"]
    }
    let delayUs = (params["delay"] as? Int ?? 0) * 1000 // ms to us

    for char in text {
        if char == "\n" || char == "\r" {
            // Press Return
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        } else {
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                var unichar = UniChar(char.unicodeScalars.first!.value)
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
        if delayUs > 0 { usleep(UInt32(delayUs)) }
    }
    return ["success": true, "text": text, "length": text.count]
}

func handleDrag(_ params: [String: Any]) -> [String: Any] {
    guard let fromIndex = params["fromIndex"] as? Int,
          let toIndex = params["toIndex"] as? Int,
          let fromEl = elementCache[fromIndex],
          let toEl = elementCache[toIndex] else {
        return ["success": false, "error": "Source or target element not found in cache"]
    }
    guard let fromPos = axPointValue(fromEl, kAXPositionAttribute),
          let fromSize = axSizeValue(fromEl, kAXSizeAttribute),
          let toPos = axPointValue(toEl, kAXPositionAttribute),
          let toSize = axSizeValue(toEl, kAXSizeAttribute) else {
        return ["success": false, "error": "Could not get element positions"]
    }

    let fromPt = CGPoint(x: fromPos.x + fromSize.width / 2, y: fromPos.y + fromSize.height / 2)
    let toPt = CGPoint(x: toPos.x + toSize.width / 2, y: toPos.y + toSize.height / 2)
    let duration = params["duration"] as? Int ?? 500
    let steps = 20
    let stepDelay = UInt32(duration * 1000 / steps)

    // Mouse down
    if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: fromPt, mouseButton: .left) {
        down.post(tap: .cghidEventTap)
    }
    usleep(50000)

    // Drag in steps
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let pt = CGPoint(x: fromPt.x + (toPt.x - fromPt.x) * t, y: fromPt.y + (toPt.y - fromPt.y) * t)
        if let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: pt, mouseButton: .left) {
            drag.post(tap: .cghidEventTap)
        }
        usleep(stepDelay)
    }

    // Mouse up
    if let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: toPt, mouseButton: .left) {
        up.post(tap: .cghidEventTap)
    }

    return ["success": true, "from": ["x": fromPt.x, "y": fromPt.y], "to": ["x": toPt.x, "y": toPt.y]]
}

func handleScreenshot(_ params: [String: Any]) -> [String: Any] {
    let filePath = params["filePath"] as? String ?? "/tmp/enconvo_screenshot_\(Int(Date().timeIntervalSince1970 * 1000)).png"

    // Use screencapture CLI (works on macOS 15+, unlike deprecated CGWindowListCreateImage)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-t", "png", filePath]
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            return ["success": true, "filePath": filePath]
        }
        return ["success": false, "error": "screencapture exited with code \(process.terminationStatus)"]
    } catch {
        return ["success": false, "error": error.localizedDescription]
    }
}

func handleApps(_ params: [String: Any]) -> [String: Any] {
    let apps = NSWorkspace.shared.runningApplications
        .filter { !$0.isHidden && $0.activationPolicy == .regular }
        .map { app -> [String: Any] in
            [
                "name": app.localizedName ?? "Unknown",
                "pid": app.processIdentifier,
                "frontmost": app.isActive,
                "bundleId": app.bundleIdentifier ?? "",
            ]
        }
    return ["success": true, "apps": apps]
}

func handleWindows(_ params: [String: Any]) -> [String: Any] {
    guard let (appEl, _, _) = getAppElement(params: params) else {
        return ["success": false, "error": "Application not found"]
    }
    guard let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement] else {
        return ["success": true, "windows": []]
    }

    var result: [[String: Any]] = []
    for (i, w) in windows.enumerated() {
        let name = axStringValue(w, kAXTitleAttribute) ?? ""
        let pos = axPointValue(w, kAXPositionAttribute) ?? .zero
        let size = axSizeValue(w, kAXSizeAttribute) ?? .zero
        let minimized = axBoolValue(w, "AXMinimized") ?? false
        result.append([
            "index": i, "name": name,
            "position": [pos.x, pos.y], "size": [size.width, size.height],
            "minimized": minimized,
        ])
    }
    return ["success": true, "windows": result]
}

func handleOpenApp(_ params: [String: Any]) -> [String: Any] {
    guard let appName = params["appName"] as? String else {
        return ["success": false, "error": "Missing appName"]
    }
    // Find app URL and open it
    let ws = NSWorkspace.shared
    if let appURL = ws.urlForApplication(withBundleIdentifier: appName) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let sem = DispatchSemaphore(value: 0)
        var openError: Error?
        ws.openApplication(at: appURL, configuration: config) { _, error in
            openError = error
            sem.signal()
        }
        sem.wait()
        if let err = openError {
            return ["success": false, "error": err.localizedDescription]
        }
        return ["success": true, "app": appName]
    }
    // Try by name via AppleScript
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", "tell application \"\(appName)\" to activate"]
    do {
        try process.run()
        process.waitUntilExit()
        return ["success": true, "app": appName]
    } catch {
        return ["success": false, "error": "Failed to open \(appName)"]
    }
}

func handleFind(_ params: [String: Any]) -> [String: Any] {
    guard let (appEl, _, _) = getAppElement(params: params) else {
        return ["success": false, "error": "Application not found"]
    }
    let roleFilter = params["role"] as? String
    let nameFilter = (params["name"] as? String)?.lowercased()
    let valueFilter = (params["value"] as? String)?.lowercased()
    let maxResults = params["maxResults"] as? Int ?? 20

    var results: [[String: Any]] = []

    func search(_ element: AXUIElement, depth: Int) {
        if depth > 15 || results.count >= maxResults { return }
        guard let role = axStringValue(element, kAXRoleAttribute) else { return }
        let name = axStringValue(element, kAXTitleAttribute) ?? ""
        let value = axStringValue(element, kAXValueAttribute) ?? ""

        var match = true
        if let rf = roleFilter, role != rf && role != "AX\(rf)" { match = false }
        if let nf = nameFilter, !name.lowercased().contains(nf) { match = false }
        if let vf = valueFilter, !value.lowercased().contains(vf) { match = false }

        if match && (roleFilter != nil || nameFilter != nil || valueFilter != nil) {
            let pos = axPointValue(element, kAXPositionAttribute) ?? .zero
            let size = axSizeValue(element, kAXSizeAttribute) ?? .zero
            results.append([
                "role": role, "name": name, "value": value,
                "position": [pos.x, pos.y], "size": [size.width, size.height],
            ])
        }

        for child in axChildren(element).prefix(150) {
            if results.count >= maxResults { break }
            search(child, depth: depth + 1)
        }
    }

    if let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement] {
        for w in windows {
            search(w, depth: 0)
            if results.count >= maxResults { break }
        }
    }

    return ["success": true, "results": results, "count": results.count]
}

func handleStatus(_ params: [String: Any]) -> [String: Any] {
    let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    return [
        "success": true,
        "cachedApp": cachedAppName,
        "cachedPid": cachedPid,
        "cachedElementCount": elementCache.count,
        "frontmostApp": frontApp,
    ]
}

// MARK: - Annotate (Set-of-Marks, from ghost-os)

func handleAnnotate(_ params: [String: Any]) -> [String: Any] {
    guard let (appEl, pid, _) = getAppElement(params: params) else {
        return ["success": false, "error": "Application not found"]
    }
    AXUIElementSetMessagingTimeout(appEl, 3.0)
    defer { AXUIElementSetMessagingTimeout(appEl, 0) }

    let maxLabels = min(params["maxLabels"] as? Int ?? 50, 100)

    // Collect interactive elements with positions
    struct AElement {
        let role: String; let name: String
        let x: Double; let y: Double; let w: Double; let h: Double
        var cx: Double { x + w / 2 }; var cy: Double { y + h / 2 }
    }
    var collected: [AElement] = []

    func collect(_ element: AXUIElement, semDepth: Int) {
        guard semDepth <= 15, collected.count < 200 else { return }
        guard let role = axStringValue(element, kAXRoleAttribute) else { return }

        let hasContent = layoutRoles.contains(role) ?
            (axStringValue(element, kAXTitleAttribute) != nil || axStringValue(element, kAXDescriptionAttribute) != nil) : true
        let childDepth = hasContent ? semDepth + 1 : semDepth

        if interactiveRoles.contains(role) {
            if let pos = axPointValue(element, kAXPositionAttribute),
               let sz = axSizeValue(element, kAXSizeAttribute), sz.width >= 8, sz.height >= 8 {
                let name = axStringValue(element, kAXTitleAttribute) ?? axStringValue(element, kAXDescriptionAttribute) ?? ""
                collected.append(AElement(role: role, name: name, x: Double(pos.x), y: Double(pos.y), w: Double(sz.width), h: Double(sz.height)))
            }
        }
        for child in axChildren(element).prefix(150) { collect(child, semDepth: childDepth) }
    }

    if let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement] {
        for w in windows { collect(w, semDepth: 0) }
    }

    // Dedup by position (5px tolerance)
    var deduped: [AElement] = []
    for el in collected {
        if !deduped.contains(where: { abs($0.x - el.x) < 5 && abs($0.y - el.y) < 5 && $0.role == el.role }) {
            deduped.append(el)
        }
    }
    deduped.sort { abs($0.y - $1.y) > 10 ? $0.y < $1.y : $0.x < $1.x }
    let elements = Array(deduped.prefix(maxLabels))

    // Take screenshot
    let screenshotPath = "/tmp/enconvo_annotate_\(Int(Date().timeIntervalSince1970 * 1000)).png"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-t", "png", screenshotPath]
    do { try process.run(); process.waitUntilExit() } catch {
        return ["success": false, "error": "Screenshot failed"]
    }

    // Load image, draw labels
    guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: screenshotPath)),
          let dataProvider = CGDataProvider(data: imageData as CFData),
          let sourceImage = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
        return ["success": false, "error": "Failed to load screenshot"]
    }

    let imgW = sourceImage.width, imgH = sourceImage.height

    // Get window bounds for coordinate mapping
    var winX = 0.0, winY = 0.0, winW = Double(imgW), winH = Double(imgH)
    if let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement], let w = windows.first {
        if let pos = axPointValue(w, kAXPositionAttribute), let sz = axSizeValue(w, kAXSizeAttribute) {
            winX = Double(pos.x); winY = Double(pos.y); winW = Double(sz.width); winH = Double(sz.height)
        }
    }

    // For full screen capture, use screen dimensions
    let screen = NSScreen.main
    let screenW = Double(screen?.frame.width ?? 1728)
    let screenH = Double(screen?.frame.height ?? 1117)
    let scaleX = Double(imgW) / screenW
    let scaleY = Double(imgH) / screenH

    guard let ctx = CGContext(data: nil, width: imgW, height: imgH, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
        return ["success": false, "error": "Failed to create graphics context"]
    }
    ctx.draw(sourceImage, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))

    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, max(11.0 * CGFloat(scaleX), 9.0), nil)
    let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let boxColor = CGColor(red: 1, green: 0, blue: 0, alpha: 0.7)

    var indexLines: [String] = ["Elements found: \(elements.count)", ""]

    for (i, el) in elements.enumerated() {
        let label = "\(i + 1)"
        let relX = el.x * scaleX
        let relY = el.y * scaleY
        let pixW = el.w * scaleX
        let pixH = el.h * scaleY
        let flippedY = Double(imgH) - relY - pixH

        // Draw box
        ctx.setStrokeColor(boxColor); ctx.setLineWidth(1.5)
        ctx.stroke(CGRect(x: relX, y: flippedY, width: pixW, height: pixH))

        // Draw pill label
        let attrStr = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringReplaceString(attrStr, CFRangeMake(0, 0), label as CFString)
        CFAttributedStringSetAttribute(attrStr, CFRangeMake(0, label.count), kCTFontAttributeName, font)
        CFAttributedStringSetAttribute(attrStr, CFRangeMake(0, label.count), kCTForegroundColorAttributeName, white)
        let line = CTLineCreateWithAttributedString(attrStr)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let tw = Double(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let th = Double(ascent + descent)
        let pillW = tw + 6, pillH = th + 4
        let pillX = relX + 2, pillY = flippedY + pixH - pillH - 2

        ctx.setFillColor(red)
        ctx.fill(CGRect(x: pillX, y: pillY, width: pillW, height: pillH))
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: pillX + 3, y: pillY + 2 + descent)
        CTLineDraw(line, ctx)
        ctx.restoreGState()

        let shortRole = el.role.hasPrefix("AX") ? String(el.role.dropFirst(2)) : el.role
        let nameStr = el.name.isEmpty ? "" : " \"\(el.name)\""
        indexLines.append("[\(i+1)] \(shortRole)\(nameStr) — click: (\(Int(el.cx)), \(Int(el.cy)))")
    }

    // Save annotated image
    let annotatedPath = "/tmp/enconvo_annotated_\(Int(Date().timeIntervalSince1970 * 1000)).png"
    if let outImage = ctx.makeImage() {
        let bitmap = NSBitmapImageRep(cgImage: outImage)
        if let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: URL(fileURLWithPath: annotatedPath))
        }
    }

    // Cleanup original screenshot
    try? FileManager.default.removeItem(atPath: screenshotPath)

    return [
        "success": true,
        "filePath": annotatedPath,
        "index": indexLines.joined(separator: "\n"),
        "element_count": elements.count,
    ]
}

// MARK: - Wait Conditions (from ghost-os)

func handleWait(_ params: [String: Any]) -> [String: Any] {
    guard let condition = params["condition"] as? String else {
        return ["success": false, "error": "Missing condition"]
    }
    let value = params["value"] as? String
    let timeout = params["timeout"] as? Double ?? 30.0
    let interval = params["interval"] as? Double ?? 0.5

    let deadline = Date().addingTimeInterval(timeout)

    // Capture baseline for "changed" conditions
    var baseline: String? = nil
    if condition == "titleChanged" {
        if let (appEl, _, _) = getAppElement(params: params) {
            if let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement], let w = windows.first {
                baseline = axStringValue(w, kAXTitleAttribute)
            }
        }
    }

    while Date() < deadline {
        var met = false

        switch condition {
        case "elementExists":
            if let v = value { met = elementExistsByName(query: v, params: params) }
        case "elementGone":
            if let v = value { met = !elementExistsByName(query: v, params: params) }
        case "titleContains":
            if let v = value, let (appEl, _, _) = getAppElement(params: params),
               let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement], let w = windows.first,
               let title = axStringValue(w, kAXTitleAttribute) {
                met = title.localizedCaseInsensitiveContains(v)
            }
        case "titleChanged":
            if let (appEl, _, _) = getAppElement(params: params),
               let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement], let w = windows.first {
                let current = axStringValue(w, kAXTitleAttribute)
                met = current != baseline
            }
        case "delay":
            Thread.sleep(forTimeInterval: timeout)
            return ["success": true, "condition": "delay", "waited": timeout]
        default:
            return ["success": false, "error": "Unknown condition: \(condition)"]
        }

        if met { return ["success": true, "condition": condition, "met": true] }
        Thread.sleep(forTimeInterval: interval)
    }

    return ["success": false, "error": "Timed out after \(Int(timeout))s waiting for \(condition)"]
}

func elementExistsByName(query: String, params: [String: Any]) -> Bool {
    guard let (appEl, _, _) = getAppElement(params: params) else { return false }
    AXUIElementSetMessagingTimeout(appEl, 3.0)
    defer { AXUIElementSetMessagingTimeout(appEl, 0) }
    let q = query.lowercased()

    func search(_ el: AXUIElement, depth: Int) -> Bool {
        guard depth < 15 else { return false }
        let title = axStringValue(el, kAXTitleAttribute)?.lowercased() ?? ""
        let desc = axStringValue(el, kAXDescriptionAttribute)?.lowercased() ?? ""
        let value = axStringValue(el, kAXValueAttribute)?.lowercased() ?? ""
        if title.contains(q) || desc.contains(q) || value.contains(q) { return true }
        for child in axChildren(el) { if search(child, depth: depth + 1) { return true } }
        return false
    }

    if let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement] {
        for w in windows { if search(w, depth: 0) { return true } }
    }
    return false
}

// MARK: - Context (smart orientation, from ghost-os)

func handleContext(_ params: [String: Any]) -> [String: Any] {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
        return ["success": false, "error": "No frontmost application"]
    }
    let pid = frontApp.processIdentifier
    let appName = frontApp.localizedName ?? "Unknown"
    let bundleId = frontApp.bundleIdentifier ?? ""
    let appEl = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appEl, 3.0)

    var windowTitle = ""
    var focusedRole = "", focusedName = ""
    var url: String? = nil

    if let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement], let w = windows.first {
        windowTitle = axStringValue(w, kAXTitleAttribute) ?? ""
    }

    // Focused element
    if let focused = axValue(appEl, "AXFocusedUIElement") {
        let fel = focused as! AXUIElement
        focusedRole = axStringValue(fel, kAXRoleAttribute) ?? ""
        focusedName = axStringValue(fel, kAXTitleAttribute) ?? axStringValue(fel, kAXDescriptionAttribute) ?? ""
    }

    // Try to find URL (browser web area)
    func findURL(_ el: AXUIElement, depth: Int) -> String? {
        guard depth < 10 else { return nil }
        let role = axStringValue(el, kAXRoleAttribute) ?? ""
        if role == "AXWebArea" { return axStringValue(el, "AXURL") ?? axStringValue(el, kAXValueAttribute) }
        for child in axChildren(el) { if let u = findURL(child, depth: depth + 1) { return u } }
        return nil
    }
    if let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement], let w = windows.first {
        url = findURL(w, depth: 0)
    }

    AXUIElementSetMessagingTimeout(appEl, 0)

    return [
        "success": true,
        "app": appName, "bundleId": bundleId, "pid": pid,
        "windowTitle": windowTitle,
        "url": url as Any,
        "focusedElement": ["role": focusedRole, "name": focusedName],
    ]
}

// MARK: - Element At Point

func handleElementAt(_ params: [String: Any]) -> [String: Any] {
    guard let x = params["x"] as? Double, let y = params["y"] as? Double else {
        return ["success": false, "error": "Missing x or y"]
    }
    let systemWide = AXUIElementCreateSystemWide()
    var elementRef: AXUIElement?
    let err = AXUIElementCopyElementAtPosition(systemWide, Float(x), Float(y), &elementRef)
    guard err == .success, let element = elementRef else {
        return ["success": false, "error": "No element found at (\(Int(x)), \(Int(y)))"]
    }
    let role = axStringValue(element, kAXRoleAttribute) ?? ""
    let name = axStringValue(element, kAXTitleAttribute) ?? ""
    let value = axStringValue(element, kAXValueAttribute)
    let desc = axStringValue(element, kAXDescriptionAttribute) ?? ""
    let subrole = axStringValue(element, kAXSubroleAttribute) ?? ""
    let enabled = axBoolValue(element, kAXEnabledAttribute) ?? true
    let focused = axBoolValue(element, kAXFocusedAttribute) ?? false
    let pos = axPointValue(element, kAXPositionAttribute) ?? .zero
    let size = axSizeValue(element, kAXSizeAttribute) ?? .zero
    let actions = axActions(element)
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""

    return [
        "success": true, "role": role, "subrole": subrole,
        "name": name, "value": value as Any, "description": desc,
        "enabled": enabled, "focused": focused,
        "position": [pos.x, pos.y], "size": [size.width, size.height],
        "actions": actions, "pid": pid, "app": appName,
    ]
}

// MARK: - Long Press

func handleLongPress(_ params: [String: Any]) -> [String: Any] {
    guard let x = params["x"] as? Double, let y = params["y"] as? Double else {
        // Try index-based
        if let index = params["index"] as? Int, let element = elementCache[index],
           let pos = axPointValue(element, kAXPositionAttribute),
           let size = axSizeValue(element, kAXSizeAttribute) {
            let cx = Double(pos.x + size.width / 2)
            let cy = Double(pos.y + size.height / 2)
            return doLongPress(x: cx, y: cy, params: params)
        }
        return ["success": false, "error": "Missing x/y or index"]
    }
    return doLongPress(x: x, y: y, params: params)
}

func doLongPress(x: Double, y: Double, params: [String: Any]) -> [String: Any] {
    let duration = params["duration"] as? Double ?? 1.0
    let button = params["button"] as? String ?? "left"
    let point = CGPoint(x: x, y: y)

    let mouseType: CGEventType = button == "right" ? .rightMouseDown : .leftMouseDown
    let mouseUpType: CGEventType = button == "right" ? .rightMouseUp : .leftMouseUp
    let mouseBtn: CGMouseButton = button == "right" ? .right : .left

    guard let down = CGEvent(mouseEventSource: nil, mouseType: mouseType, mouseCursorPosition: point, mouseButton: mouseBtn),
          let up = CGEvent(mouseEventSource: nil, mouseType: mouseUpType, mouseCursorPosition: point, mouseButton: mouseBtn) else {
        return ["success": false, "error": "Failed to create CGEvent"]
    }
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: duration)
    up.post(tap: .cghidEventTap)
    return ["success": true, "action": "longPress", "x": x, "y": y, "duration": duration]
}

// MARK: - Hotkey

func handleHotkey(_ params: [String: Any]) -> [String: Any] {
    guard let keys = params["keys"] as? [String], !keys.isEmpty else {
        return ["success": false, "error": "Missing keys array (e.g. [\"cmd\", \"shift\", \"p\"])"]
    }
    // Last element is the key, rest are modifiers
    let key = keys.last!
    let modifiers = Array(keys.dropLast())
    let result = handlePress(["key": key, "modifiers": modifiers])
    return result
}

// MARK: - Window Management

func handleWindow(_ params: [String: Any]) -> [String: Any] {
    guard let action = params["action"] as? String else {
        return ["success": false, "error": "Missing action"]
    }
    let appName = params["appName"] as? String

    // Resolve target app
    let appEl: AXUIElement
    if let name = appName {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.localizedName == name }
        guard let app = apps.first else { return ["success": false, "error": "App '\(name)' not found"] }
        appEl = AXUIElementCreateApplication(app.processIdentifier)
    } else {
        guard let front = NSWorkspace.shared.frontmostApplication else {
            return ["success": false, "error": "No frontmost app"]
        }
        appEl = AXUIElementCreateApplication(front.processIdentifier)
    }

    // Find target window (by title or first window)
    guard let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else {
        return ["success": false, "error": "No windows found"]
    }
    let windowTitle = params["window"] as? String
    let window: AXUIElement
    if let title = windowTitle {
        let match = windows.first { (axStringValue($0, kAXTitleAttribute) ?? "").localizedCaseInsensitiveContains(title) }
        guard let w = match else { return ["success": false, "error": "Window '\(title)' not found"] }
        window = w
    } else {
        window = windows[0]
    }

    switch action {
    case "minimize":
        _ = axSetValue(window, "AXMinimized", kCFBooleanTrue)
        return ["success": true, "action": "minimize"]

    case "restore":
        _ = axSetValue(window, "AXMinimized", kCFBooleanFalse)
        return ["success": true, "action": "restore"]

    case "maximize", "fullscreen":
        if let btn = findWindowButton(window, subrole: "AXFullScreenButton") {
            _ = axPerformAction(btn, kAXPressAction)
            return ["success": true, "action": "fullscreen"]
        }
        // Fallback: resize to screen
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let pos = NSValue(point: NSPoint(x: f.origin.x, y: f.origin.y))
            let sz = NSValue(size: NSSize(width: f.width, height: f.height))
            var posVal: AXValue?
            var szVal: AXValue?
            var p = CGPoint(x: f.origin.x, y: 0)
            var s = CGSize(width: f.width, height: f.height)
            posVal = AXValueCreate(.cgPoint, &p)
            szVal = AXValueCreate(.cgSize, &s)
            if let pv = posVal { _ = axSetValue(window, kAXPositionAttribute, pv) }
            if let sv = szVal { _ = axSetValue(window, kAXSizeAttribute, sv) }
        }
        return ["success": true, "action": "maximize"]

    case "close":
        if let btn = findWindowButton(window, subrole: "AXCloseButton") {
            _ = axPerformAction(btn, kAXPressAction)
            return ["success": true, "action": "close"]
        }
        return ["success": false, "error": "Close button not found"]

    case "move":
        guard let x = params["x"] as? Double, let y = params["y"] as? Double else {
            return ["success": false, "error": "Missing x, y for move"]
        }
        var point = CGPoint(x: x, y: y)
        if let val = AXValueCreate(.cgPoint, &point) {
            _ = axSetValue(window, kAXPositionAttribute, val)
            return ["success": true, "action": "move", "x": x, "y": y]
        }
        return ["success": false, "error": "Failed to set position"]

    case "resize":
        guard let w = params["width"] as? Double, let h = params["height"] as? Double else {
            return ["success": false, "error": "Missing width, height for resize"]
        }
        var size = CGSize(width: w, height: h)
        if let val = AXValueCreate(.cgSize, &size) {
            _ = axSetValue(window, kAXSizeAttribute, val)
            return ["success": true, "action": "resize", "width": w, "height": h]
        }
        return ["success": false, "error": "Failed to set size"]

    case "list":
        var result: [[String: Any]] = []
        for (i, w) in windows.enumerated() {
            let name = axStringValue(w, kAXTitleAttribute) ?? ""
            let pos = axPointValue(w, kAXPositionAttribute) ?? .zero
            let sz = axSizeValue(w, kAXSizeAttribute) ?? .zero
            let minimized = axBoolValue(w, "AXMinimized") ?? false
            let fullscreen = axBoolValue(w, "AXFullScreen") ?? false
            result.append(["index": i, "name": name, "position": [pos.x, pos.y], "size": [sz.width, sz.height], "minimized": minimized, "fullscreen": fullscreen])
        }
        return ["success": true, "windows": result]

    default:
        return ["success": false, "error": "Unknown window action: \(action). Use: list, minimize, maximize, restore, close, move, resize"]
    }
}

func findWindowButton(_ window: AXUIElement, subrole: String) -> AXUIElement? {
    for child in axChildren(window) {
        let sr = axStringValue(child, kAXSubroleAttribute) ?? ""
        if sr == subrole { return child }
        let role = axStringValue(child, kAXRoleAttribute) ?? ""
        if role == "AXButton" && sr == subrole { return child }
    }
    return nil
}

// MARK: - State (unified desktop state)

func handleState(_ params: [String: Any]) -> [String: Any] {
    let runningApps = NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }

    var apps: [[String: Any]] = []
    for app in runningApps {
        let name = app.localizedName ?? "Unknown"
        let pid = app.processIdentifier
        let bundleId = app.bundleIdentifier ?? ""
        let frontmost = app.isActive

        var windowList: [[String: Any]] = []
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 2.0)
        if let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement] {
            for (i, w) in windows.enumerated() {
                let wName = axStringValue(w, kAXTitleAttribute) ?? ""
                let pos = axPointValue(w, kAXPositionAttribute) ?? .zero
                let size = axSizeValue(w, kAXSizeAttribute) ?? .zero
                let minimized = axBoolValue(w, "AXMinimized") ?? false
                windowList.append(["index": i, "title": wName, "position": [pos.x, pos.y], "size": [size.width, size.height], "minimized": minimized])
            }
        }

        apps.append(["name": name, "pid": pid, "bundleId": bundleId, "frontmost": frontmost, "windows": windowList])
    }

    return ["success": true, "apps": apps, "appCount": apps.count]
}

// MARK: - Read (extract text from element subtree)

func handleRead(_ params: [String: Any]) -> [String: Any] {
    let maxDepth = params["maxDepth"] as? Int ?? 10

    // If index provided, read from cached element
    if let index = params["index"] as? Int, let element = elementCache[index] {
        var texts: [String] = []
        collectText(element, texts: &texts, depth: 0, maxDepth: maxDepth)
        return ["success": true, "text": texts.joined(separator: "\n"), "lineCount": texts.count]
    }

    // Otherwise read from frontmost window
    guard let (appEl, _, _) = getAppElement(params: params) else {
        return ["success": false, "error": "Application not found"]
    }
    AXUIElementSetMessagingTimeout(appEl, 3.0)
    defer { AXUIElementSetMessagingTimeout(appEl, 0) }

    guard let windows = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement], let w = windows.first else {
        return ["success": false, "error": "No window found"]
    }

    var texts: [String] = []
    collectText(w, texts: &texts, depth: 0, maxDepth: maxDepth)
    return ["success": true, "text": texts.joined(separator: "\n"), "lineCount": texts.count]
}

func collectText(_ element: AXUIElement, texts: inout [String], depth: Int, maxDepth: Int) {
    guard depth <= maxDepth else { return }
    let role = axStringValue(element, kAXRoleAttribute) ?? ""

    // Collect text from value, title, or name
    if role == "AXStaticText" || role == "AXTextField" || role == "AXTextArea" || role == "AXHeading" || role == "AXLink" {
        if let v = axStringValue(element, kAXValueAttribute), !v.isEmpty {
            texts.append(v)
        } else if let t = axStringValue(element, kAXTitleAttribute), !t.isEmpty {
            texts.append(t)
        }
    }

    // Semantic depth for recursion
    let hasContent = !layoutRoles.contains(role) || (axStringValue(element, kAXTitleAttribute) != nil)
    let childDepth = hasContent ? depth + 1 : depth

    for child in axChildren(element).prefix(200) {
        collectText(child, texts: &texts, depth: childDepth, maxDepth: maxDepth)
    }
}

// MARK: - Inspect (alias for getInfo with more detail)

func handleInspect(_ params: [String: Any]) -> [String: Any] {
    // Support both index and x/y
    if let index = params["index"] as? Int, let element = elementCache[index] {
        return inspectElement(element)
    }
    if let x = params["x"] as? Double, let y = params["y"] as? Double {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(x), Float(y), &elementRef)
        guard err == .success, let element = elementRef else {
            return ["success": false, "error": "No element at (\(Int(x)), \(Int(y)))"]
        }
        return inspectElement(element)
    }
    return ["success": false, "error": "Provide index or x/y"]
}

func inspectElement(_ element: AXUIElement) -> [String: Any] {
    let role = axStringValue(element, kAXRoleAttribute) ?? ""
    let subrole = axStringValue(element, kAXSubroleAttribute) ?? ""
    let name = axStringValue(element, kAXTitleAttribute) ?? ""
    let value = axStringValue(element, kAXValueAttribute)
    let desc = axStringValue(element, kAXDescriptionAttribute) ?? ""
    let enabled = axBoolValue(element, kAXEnabledAttribute) ?? true
    let focused = axBoolValue(element, kAXFocusedAttribute) ?? false
    let pos = axPointValue(element, kAXPositionAttribute) ?? .zero
    let size = axSizeValue(element, kAXSizeAttribute) ?? .zero
    let actions = axActions(element)
    let children = axChildren(element).count
    let domId = axStringValue(element, "AXDOMIdentifier") ?? ""
    let identifier = axStringValue(element, "AXIdentifier") ?? ""
    let help = axStringValue(element, kAXHelpAttribute) ?? ""
    let roleDesc = axStringValue(element, kAXRoleDescriptionAttribute) ?? ""

    // Check if editable
    let editable = role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox" || role == "AXSearchField"

    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""

    return [
        "success": true,
        "role": role, "subrole": subrole, "roleDescription": roleDesc,
        "name": name, "value": value as Any, "description": desc, "help": help,
        "enabled": enabled, "focused": focused, "editable": editable,
        "position": [pos.x, pos.y], "size": [size.width, size.height],
        "actions": actions, "childCount": children,
        "domId": domId, "identifier": identifier,
        "pid": pid, "app": appName,
    ]
}

// MARK: - Main Dispatch

func dispatch(method: String, params: [String: Any]) -> [String: Any] {
    switch method {
    case "snapshot": return handleSnapshot(params)
    case "click": return handleClick(params)
    case "setValue": return handleSetValue(params)
    case "focus": return handleFocus(params)
    case "getInfo": return handleGetInfo(params)
    case "getText": return handleGetText(params)
    case "performAction": return handlePerformAction(params)
    case "mouse": return handleMouse(params)
    case "scroll": return handleScroll(params)
    case "press": return handlePress(params)
    case "type": return handleType(params)
    case "drag": return handleDrag(params)
    case "screenshot": return handleScreenshot(params)
    case "apps": return handleApps(params)
    case "windows": return handleWindows(params)
    case "openApp": return handleOpenApp(params)
    case "find": return handleFind(params)
    case "status": return handleStatus(params)
    case "annotate": return handleAnnotate(params)
    case "wait": return handleWait(params)
    case "context": return handleContext(params)
    case "elementAt": return handleElementAt(params)
    case "longPress": return handleLongPress(params)
    case "hotkey": return handleHotkey(params)
    case "window": return handleWindow(params)
    case "state": return handleState(params)
    case "read": return handleRead(params)
    case "inspect": return handleInspect(params)
    case "ping": return ["success": true, "pong": true]
    default: return ["success": false, "error": "Unknown method: \(method)"]
    }
}

// MARK: - Main Loop (stdin/stdout JSON-RPC)

func main() {
    // Disable stdout buffering for real-time communication
    setbuf(stdout, nil)

    // Send ready signal
    print(jsonString(["ready": true, "pid": ProcessInfo.processInfo.processIdentifier]))

    while let line = readLine(strippingNewline: true) {
        guard !line.isEmpty, let request = parseJSON(line) else { continue }

        let id = request["id"] ?? 0
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]

        let result = dispatch(method: method, params: params)
        var response = result
        response["id"] = id
        print(jsonString(response))
    }
}

main()
