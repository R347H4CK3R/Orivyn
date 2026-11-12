import Foundation

/// Bounded tree for small, already byte-limited XML parts. No DTD, entity declarations or network.
final class OfficeXMLNode {
    let name: String
    let namespace: String
    let attributes: [String: String]
    var children: [OfficeXMLNode] = []
    var text = ""
    init(name: String, namespace: String, attributes: [String: String]) {
        self.name = name; self.namespace = namespace; self.attributes = attributes
    }
    func children(_ name: String, in namespace: String) -> [OfficeXMLNode] {
        children.filter { $0.name == name && $0.namespace == namespace }
    }
    func first(_ name: String, in namespace: String) -> OfficeXMLNode? {
        children.first { $0.name == name && $0.namespace == namespace }
    }
    func attribute(_ name: String, namespace: String? = nil) -> String? {
        attributes[namespace.map { "{\($0)}\(name)" } ?? name]
    }
}

final class BoundedOfficeXML: NSObject, XMLParserDelegate {
    private let limits: OfflineDocumentLimits
    private let control: OfficeReadControl
    private var stack: [OfficeXMLNode] = []
    private var namespaces: [[String: String]] = [["xml":"http://www.w3.org/XML/1998/namespace"]]
    private var root: OfficeXMLNode?
    private var nodes = 0, textBytes = 0
    private var failure: Error?
    private init(limits: OfflineDocumentLimits, control: OfficeReadControl) { self.limits = limits; self.control = control }

    static func parse(_ data: Data, limits: OfflineDocumentLimits, control: OfficeReadControl = OfficeReadControl()) throws -> OfficeXMLNode {
        try Task.checkCancellation()
        guard data.count <= limits.maximumEntryBytes, let text = String(data: data, encoding: .utf8),
              !text.contains("\0"), !text.uppercased().contains("<!DOCTYPE"),
              !text.uppercased().contains("<!ENTITY") else { throw OfflineDocumentError.invalidXML }
        // Examine only an actual declaration. XMLParser validates the rest of its grammar.
        // A bounded anchored attribute match allows every legal XML whitespace spelling.
        let withoutBOM = text.hasPrefix("\u{FEFF}") ? text.dropFirst() : text[...]
        if withoutBOM.hasPrefix("<?xml"), withoutBOM.dropFirst(5).first.map({ " \t\r\n".contains($0) }) == true {
            guard let end = withoutBOM.range(of: "?>"), withoutBOM[..<end.upperBound].utf8.count <= 1_024 else { throw OfflineDocumentError.invalidXML }
            let declaration = String(withoutBOM[..<end.upperBound])
            let pattern = #"[ \t\r\n]encoding[ \t\r\n]*=[ \t\r\n]*(["'])([A-Za-z][A-Za-z0-9._-]*)\1"#
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: declaration,range: NSRange(declaration.startIndex...,in: declaration))
            guard matches.count <= 1 else { throw OfflineDocumentError.invalidXML }
            if let match = matches.first, let range = Range(match.range(at: 2),in: declaration) {
                guard declaration[range].lowercased() == "utf-8" else { throw OfflineDocumentError.invalidXML }
            }
        }
        let delegate = BoundedOfficeXML(limits: limits, control: control)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false // Resolve qualified attributes explicitly as well as elements.
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let ok = parser.parse()
        if let error = delegate.failure { throw error }
        guard ok, delegate.stack.isEmpty, let root = delegate.root else { throw OfflineDocumentError.invalidXML }
        return root
    }

    private func stop(_ parser: XMLParser, _ error: Error = OfflineDocumentError.invalidXML) {
        if failure == nil { failure = error }; parser.abortParsing()
    }
    private func expanded(_ qualified: String, scope: [String: String], attribute: Bool) -> (String,String)? {
        let parts = qualified.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 1 { return (qualified, attribute ? "" : (scope[""] ?? "")) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              let uri = scope[String(parts[0])], !uri.isEmpty else { return nil }
        return (String(parts[1]),uri)
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        do { try control.checkpoint(.xmlNode) } catch { stop(parser,error); return }
        nodes += 1
        guard nodes <= limits.maximumXMLNodes, stack.count < limits.maximumXMLDepth,
              attributeDict.count <= limits.maximumXMLAttributes else {
            stop(parser, OfflineDocumentError.limit("The Office XML exceeds its node, depth or attribute limits.")); return
        }
        var scope = namespaces.last ?? [:]
        for (key,value) in attributeDict {
            guard key.utf8.count <= 256, value.utf8.count <= limits.maximumStringBytes else {
                stop(parser,OfflineDocumentError.limit("An Office XML attribute is too long.")); return
            }
            if key == "xmlns" { scope[""] = value }
            else if key.hasPrefix("xmlns:") {
                let prefix = String(key.dropFirst(6))
                guard prefix != "xmlns", prefix != "xml" || value == "http://www.w3.org/XML/1998/namespace" else { stop(parser); return }
                scope[prefix] = value
            }
        }
        guard scope.count <= 32, let (name,uri) = expanded(elementName,scope: scope,attribute: false) else { stop(parser); return }
        var attributes = [String:String]()
        for (key,value) in attributeDict where key != "xmlns" && !key.hasPrefix("xmlns:") {
            guard let (local,uri) = expanded(key,scope: scope,attribute: true) else { stop(parser); return }
            let expandedKey = uri.isEmpty ? local : "{\(uri)}\(local)"
            guard attributes.updateValue(value,forKey: expandedKey) == nil else { stop(parser); return }
        }
        let node = OfficeXMLNode(name: name,namespace: uri,attributes: attributes)
        if let parent = stack.last { parent.children.append(node) }
        else if root == nil { root = node }
        else { stop(parser); return }
        stack.append(node); namespaces.append(scope)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard !stack.isEmpty else { stop(parser); return }
        stack.removeLast(); namespaces.removeLast()
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let bytes = string.utf8.count
        guard bytes <= limits.maximumXMLTextBytes - textBytes,
              (stack.last?.text.utf8.count ?? 0) <= limits.maximumStringBytes - bytes else {
            stop(parser,OfflineDocumentError.limit("The Office XML exceeds its text or string limits.")); return
        }
        textBytes += bytes; stack.last?.text += string
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock,encoding: .utf8) else { stop(parser); return }
        self.parser(parser,foundCharacters: text)
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { stop(parser); return nil }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { stop(parser) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { stop(parser) }
    func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?, systemID: String?, notationName: String?) { stop(parser) }
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil { failure = OfflineDocumentError.invalidXML }
    }
}
