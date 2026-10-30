import AppKit
import ApplicationServices
import Foundation

// 仅检查本项目原生应用；节点路径用于定向交互，密码字段不输出内容。
let identifier = "local.skillatlas.app"
guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first else {
    fputs("应用未运行\n", stderr); exit(1)
}
let root = AXUIElementCreateApplication(application.processIdentifier)
AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func mainWindow() -> AXUIElement? {
    (attribute(root, kAXWindowsAttribute) as? [AXUIElement])?.first { attribute($0, kAXIdentifierAttribute) as? String == "skill-atlas-main" }
}
func activate() {
    application.activate(options: [])
    AXUIElementSetAttributeValue(root, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    if let window = mainWindow() { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
}
func find(_ element: AXUIElement, title: String) -> AXUIElement? {
    if attribute(element, kAXTitleAttribute) as? String == title { return element }
    for child in children(element) { if let result = find(child, title: title) { return result } }
    return nil
}
func frame(_ element: AXUIElement) -> CGRect? {
    guard let rawPoint = attribute(element, kAXPositionAttribute), let rawSize = attribute(element, kAXSizeAttribute),
          CFGetTypeID(rawPoint) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(rawPoint as! AXValue, .cgPoint, &point)
    AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
}
func click(_ element: AXUIElement) {
    activate()
    guard let box = frame(element), box.width > 0, box.height > 0 else { fputs("节点没有可点击区域\n", stderr); exit(4) }
    let point = CGPoint(x: box.midX, y: box.midY)
    let source = CGEventSource(stateID: .combinedSessionState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
}
func walk(_ element: AXUIElement, _ path: String = "", _ depth: Int = 0) {
    if depth > 25 { return }
    let role = attribute(element, kAXRoleAttribute) as? String ?? ""
    if role == "AXApplication" || role == "AXMenuBar" { return }
    let subtype = attribute(element, kAXSubroleAttribute) as? String ?? ""
    let fields = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute].compactMap { key -> String? in
        if key == kAXValueAttribute && subtype == "AXSecureTextField" { return nil }
        guard let value = attribute(element, key) else { return nil }
        if CFGetTypeID(value) == AXUIElementGetTypeID() { return nil }
        let text = String(describing: value).replacingOccurrences(of: "\n", with: " ")
        return text.isEmpty ? nil : "\(key)=\(text.prefix(220))"
    }
    if !fields.isEmpty || role == "AXTextField" { print("\(path) \(role) \(fields.joined(separator: " | "))") }
    for (index, child) in children(element).enumerated() { walk(child, path.isEmpty ? "\(index)" : "\(path).\(index)", depth + 1) }
}
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "activate" {
    activate()
    print("应用前台状态=\(String(describing: attribute(root, kAXFrontmostAttribute)))")
} else if arguments.first == "quit" {
    print("退出请求=\(application.terminate())")
} else if arguments.first == "resize", arguments.count == 3, let width = Double(arguments[1]), let height = Double(arguments[2]),
          let window = mainWindow() {
    var size = CGSize(width: width, height: height)
    let status = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    print("调整尺寸状态=\(status.rawValue) 实际=\(String(describing: frame(window)))")
    if status != .success { exit(3) }
} else if arguments.first == "screenshot", arguments.count == 2 {
    activate()
    let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let window = entries.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == application.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }),
          let id = window[kCGWindowNumber as String] as? Int else { fputs("没有可见应用窗口\n", stderr); exit(5) }
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", String(id), arguments[1]]
    try process.run(); process.waitUntilExit(); exit(process.terminationStatus)
} else if arguments.first == "diagnose" {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value)
    print("pid=\(application.processIdentifier) trusted=\(AXIsProcessTrusted()) windows_status=\(status.rawValue) windows=\(String(describing: value))")
    for window in value as? [AXUIElement] ?? [] { walk(window, "window") }
} else if arguments.first == "windows" {
    let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for entry in entries where entry[kCGWindowOwnerPID as String] as? Int32 == application.processIdentifier {
        print("window_id=\(entry[kCGWindowNumber as String] ?? "") title=\(entry[kCGWindowName as String] ?? "")")
    }
} else if arguments.count >= 2 {
    var node = root
    for step in arguments[1].split(separator: ".") {
        guard let index = Int(step), children(node).indices.contains(index) else { fputs("节点路径已失效\n", stderr); exit(2) }
        node = children(node)[index]
    }
    let status: AXError
    if arguments[0] == "choose", arguments.count == 3 {
        AXUIElementPerformAction(node, kAXPressAction as CFString)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        guard let option = find(node, title: arguments[2]) else { fputs("未找到指定菜单项\n", stderr); exit(6) }
        status = AXUIElementPerformAction(option, kAXPressAction as CFString)
    } else if arguments[0] == "hover", let box = frame(node) {
        activate()
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: box.midX, y: box.midY), mouseButton: .left)?.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        print("已悬停应用节点"); exit(0)
    } else if arguments[0] == "inspect" {
        var names: CFArray?
        AXUIElementCopyActionNames(node, &names)
        print("actions=\(String(describing: names)) frame=\(String(describing: frame(node))) help=\(String(describing: attribute(node, kAXHelpAttribute))) enabled=\(String(describing: attribute(node, kAXEnabledAttribute)))")
        exit(0)
    } else if arguments[0] == "type", arguments.count == 3 {
        activate()
        AXUIElementSetAttributeValue(node, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        down.flags = .maskCommand; down.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
        up.flags = .maskCommand; up.post(tap: .cghidEventTap)
        let units = Array(arguments[2].utf16)
        if units.isEmpty {
            CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: false)?.post(tap: .cghidEventTap)
        } else {
            for isDown in [true, false] {
                let key = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown)!
                units.withUnsafeBufferPointer { key.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress!) }
                key.post(tap: .cghidEventTap)
            }
        }
        print("已向应用文本字段发送输入"); exit(0)
    } else if arguments[0] == "click" { click(node); exit(0) }
    else if arguments[0] == "frame" { print(String(describing: frame(node))); exit(0) }
    else if arguments[0] == "press" { status = AXUIElementPerformAction(node, kAXPressAction as CFString) }
    else if arguments[0] == "confirm" { status = AXUIElementPerformAction(node, "AXConfirm" as CFString) }
    else if arguments[0] == "select" { status = AXUIElementSetAttributeValue(node, kAXSelectedAttribute as CFString, kCFBooleanTrue) }
    else if arguments[0] == "focus" { activate(); status = AXUIElementSetAttributeValue(node, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
    else if arguments[0] == "set-number", arguments.count == 3, let value = Double(arguments[2]) { status = AXUIElementSetAttributeValue(node, kAXValueAttribute as CFString, NSNumber(value: value)) }
    else if arguments[0] == "set", arguments.count == 3 { status = AXUIElementSetAttributeValue(node, kAXValueAttribute as CFString, arguments[2] as CFString) }
    else { exit(2) }
    print("操作状态=\(status.rawValue)")
    if status != .success { exit(3) }
} else {
    for (index, window) in children(root).enumerated() where attribute(window, kAXRoleAttribute) as? String == "AXWindow" { walk(window, "\(index)") }
}
