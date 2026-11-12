import Foundation
import CoreFoundation
import WebKit

enum VMCheckpointRequest: Sendable {
    case begin(Int, String?)
    case append(UUID, Int, Data)
    case commit(UUID)
    case abort(UUID)
    case latest
    case read(UUID, Int, Int)

    static func parse(_ body: Any, owner: UUID, identity: VMCheckpointIdentity) throws -> Self {
        guard identity.isValid, let object=body as? [String:Any], object.count <= 7,
              let ownerText=object["owner"] as? String, ownerText.count==36, UUID(uuidString:ownerText)==owner,
              let action=object["action"] as? String else { throw VMCheckpointError.rejected }
        func keys(_ expected: Set<String>) throws {
            guard Set(object.keys)==expected.union(["owner","action"]) else { throw VMCheckpointError.rejected }
        }
        func integer(_ name:String, minimum:Int, maximum:Int) throws -> Int {
            guard let value=object[name] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
                  value.doubleValue.rounded(.down)==value.doubleValue, value.doubleValue>=Double(minimum), value.doubleValue<=Double(maximum) else { throw VMCheckpointError.rejected }
            return value.intValue
        }
        func uuid(_ name:String) throws -> UUID {
            guard let text=object[name] as? String,text.count==36,let value=UUID(uuidString:text) else { throw VMCheckpointError.rejected };return value
        }
        func pinnedIdentity() throws {
            guard let value=object["identity"] as? [String:Any],Set(value.keys)==["engineSHA256","guestSHA256","configurationSHA256"],
                  value["engineSHA256"] as? String == identity.engineSHA256,
                  value["guestSHA256"] as? String == identity.guestSHA256,
                  value["configurationSHA256"] as? String == identity.configurationSHA256 else { throw VMCheckpointError.incompatible }
        }
        switch action {
        case "begin":
            let supplied=object["expectedSHA256"]
            try keys(supplied == nil ? ["identity","expectedBytes"] : ["identity","expectedBytes","expectedSHA256"])
            try pinnedIdentity()
            let hash=supplied as? String
            guard supplied==nil || (hash != nil && VMCheckpointStore.validDigest(hash!)) else { throw VMCheckpointError.rejected }
            return .begin(try integer("expectedBytes",minimum:1,maximum:VMCheckpointStore.maximumBytes),hash)
        case "append":
            try keys(["transaction","offset","base64"])
            guard let encoded=object["base64"] as? String, !encoded.isEmpty,
                  encoded.utf8.count <= 4 * ((VMCheckpointStore.chunkBytes + 2) / 3),
                  let data=Data(base64Encoded:encoded), !data.isEmpty,data.count<=VMCheckpointStore.chunkBytes,
                  data.base64EncodedString()==encoded else { throw VMCheckpointError.rejected }
            return .append(try uuid("transaction"),try integer("offset",minimum:0,maximum:VMCheckpointStore.maximumBytes),data)
        case "commit": try keys(["transaction"]);return .commit(try uuid("transaction"))
        case "abort": try keys(["transaction"]);return .abort(try uuid("transaction"))
        case "latest": try keys(["identity"]);try pinnedIdentity();return .latest
        case "read":
            try keys(["identity","generation","offset","length"]);try pinnedIdentity()
            return .read(try uuid("generation"),try integer("offset",minimum:0,maximum:VMCheckpointStore.maximumBytes),try integer("length",minimum:1,maximum:VMCheckpointStore.chunkBytes))
        default: throw VMCheckpointError.rejected
        }
    }
}

/// One trusted local document, one lifecycle owner, one outstanding disk request.
/// No arbitrary paths, network, guest commands or automatic VM execution.
@MainActor
final class VMCheckpointBridge: NSObject, @preconcurrency WKScriptMessageHandlerWithReply {
    weak var ownedWebView: WKWebView?
    private let owner: UUID
    private let identity: VMCheckpointIdentity
    private let store: VMCheckpointStore
    private var active=true
    private var busy=false
    private var transaction: UUID?
    private var restoreGeneration: UUID?

    init(owner:UUID, identity:VMCheckpointIdentity, store:VMCheckpointStore) {
        self.owner=owner;self.identity=identity;self.store=store
        super.init()
    }
    static func authorized(candidate:WKWebView?,owned:WKWebView?,isMainFrame:Bool,scheme:String,host:String,port:Int) -> Bool {
        guard let candidate,let owned else { return false }
        return candidate === owned && isMainFrame && scheme=="orivyn-vm" && host=="bundle" && port==0
    }
    @discardableResult
    func invalidate() -> Task<Void,Never> {
        active=false;ownedWebView=nil;restoreGeneration=nil
        let id=transaction;transaction=nil
        return Task { if let id { try? await store.abort(transaction:id) } }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard active, message.name=="vmCheckpoint", Self.authorized(candidate:message.webView,owned:ownedWebView,
              isMainFrame:message.frameInfo.isMainFrame,scheme:message.frameInfo.securityOrigin.protocol,
              host:message.frameInfo.securityOrigin.host,port:message.frameInfo.securityOrigin.port) else {
            replyHandler(nil,"Checkpoint request rejected");return
        }
        // Decode immediately on the main actor; no unbounded Any payload crosses actors.
        let request:VMCheckpointRequest
        do { request=try VMCheckpointRequest.parse(message.body,owner:owner,identity:identity) }
        catch { replyHandler(nil,"Checkpoint request rejected");return }
        Task { @MainActor in
            do { let value=try await execute(request);replyHandler(value,nil) }
            catch { replyHandler(nil,"Checkpoint unavailable, interrupted or invalid") }
        }
    }
    /// Internal test seam for parser/state-machine tests; the WebKit entry point
    /// additionally requires exact webview/frame/origin authorization above.
    func process(_ body:Any) async throws -> Any {
        try await execute(VMCheckpointRequest.parse(body,owner:owner,identity:identity))
    }
    private func execute(_ request:VMCheckpointRequest) async throws -> Any {
        guard active,!busy else { throw VMCheckpointError.rejected }
        busy=true;defer { busy=false }
        switch request {
        case let .begin(bytes,hash):
            guard transaction==nil else { throw VMCheckpointError.busy }
            let id=try await store.begin(identity:identity,expectedBytes:bytes,expectedSHA256:hash)
            guard active else { try? await store.abort(transaction:id);throw VMCheckpointError.rejected }
            transaction=id
            return ["transaction":id.uuidString]
        case let .append(id,offset,data):
            guard transaction==id else { throw VMCheckpointError.staleTransaction }
            let next=try await store.append(transaction:id,offset:offset,data:data)
            guard active else { throw VMCheckpointError.rejected }
            return ["nextOffset":next]
        case let .commit(id):
            guard transaction==id else { throw VMCheckpointError.staleTransaction }
            let saved=try await store.commit(transaction:id)
            transaction=nil
            guard active else { throw VMCheckpointError.rejected }
            return Self.body(saved)
        case let .abort(id):
            guard transaction==id else { throw VMCheckpointError.staleTransaction }
            try await store.abort(transaction:id);transaction=nil
            guard active else { throw VMCheckpointError.rejected }
            return [String:String]()
        case .latest:
            let latest=try await store.latest(identity:identity)
            guard active else { throw VMCheckpointError.rejected }
            restoreGeneration=latest?.generation
            if let latest { return Self.body(latest) }
            return NSNull()
        case let .read(generation,offset,length):
            guard restoreGeneration==generation else { throw VMCheckpointError.rejected }
            let data=try await store.read(identity:identity,generation:generation,offset:offset,length:length)
            guard active else { throw VMCheckpointError.rejected }
            return ["base64":data.base64EncodedString()]
        }
    }
    private static func body(_ value:VMCheckpointMetadata) -> [String:Any] {
        ["schemaVersion":value.schemaVersion,"generation":value.generation.uuidString,"bytes":value.bytes,"sha256":value.sha256,
         "identity":["engineSHA256":value.identity.engineSHA256,"guestSHA256":value.identity.guestSHA256,"configurationSHA256":value.identity.configurationSHA256]]
    }
}
