import ApplicationServices

extension AXUIElement {
    func attribute<T>(_ attribute: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    func children() -> [AXUIElement] {
        attribute(kAXChildrenAttribute as String) ?? []
    }

    func role() -> String? {
        attribute(kAXRoleAttribute as String)
    }

    func title() -> String? {
        attribute(kAXTitleAttribute as String)
    }

    func position() -> CGPoint? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, kAXPositionAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // Safe: CFGetTypeID check above guarantees value is AXValue
        let axValue = value as! AXValue // swiftlint:disable:this force_cast
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    func size() -> CGSize? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, kAXSizeAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // Safe: CFGetTypeID check above guarantees value is AXValue
        let axValue = value as! AXValue // swiftlint:disable:this force_cast
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }

    func frame() -> CGRect? {
        guard let position = position(), let size = size() else { return nil }
        return CGRect(origin: position, size: size)
    }

    func performAction(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }

    func press() -> Bool {
        performAction(kAXPressAction as String)
    }

    func description_() -> String? {
        attribute(kAXDescriptionAttribute as String)
    }

    func identifier() -> String? {
        attribute("AXIdentifier" as String)
    }

    func subrole() -> String? {
        attribute(kAXSubroleAttribute as String)
    }

    func attributeNames() -> [String] {
        var names: CFArray?
        let result = AXUIElementCopyAttributeNames(self, &names)
        guard result == .success, let cfNames = names else { return [] }
        return cfNames as? [String] ?? []
    }
}
