import Foundation
import Network
import Security
import CryptoKit

@available(macOS 15.0, *)
struct FixtureIdentity {
    let identity:SecIdentity
    let der:Data
    var pin:Data { Data(SHA256.hash(data:der)) }
    init(root:URL,name:String,password:String) throws {
        let data=try Data(contentsOf:root.appendingPathComponent(name+".p12"))
        der=try Data(contentsOf:root.appendingPathComponent(name+".der"))
        var items:CFArray?
        let options:[String:Any]=[kSecImportExportPassphrase as String:password,kSecImportToMemoryOnly as String:true]
        let status=SecPKCS12Import(data as CFData,options as CFDictionary,&items)
        guard status==errSecSuccess,let values=items as? [[String:Any]],values.count==1,
              let raw=values[0][kSecImportItemIdentity as String],
              CFGetTypeID(raw as CFTypeRef)==SecIdentityGetTypeID() else { throw GateError.failed("fixture import status \(status)") }
        identity=raw as! SecIdentity
    }
}
enum GateError:Error { case failed(String) }
struct PeerOutcome:Codable,Sendable { let side:String;let authenticated:Bool;let scopeValid:Bool }
/// Native callbacks use distinct queues; lock protects every mutable access.
final class PairResults:@unchecked Sendable {
    private let lock=NSLock()
    private let group=DispatchGroup()
    private var values:[PeerOutcome]=[]
    init(){group.enter();group.enter()}
    func append(_ side:String,_ result:Result<PeerTLSProbe.Result,Error>,pin:Data,generation:UUID) {
        let outcome:PeerOutcome
        switch result {
        case .success(let value):
            outcome = .init(side:side,authenticated:true,scopeValid:value.peerCertificateSHA256==pin && value.pairingGeneration==generation && value.localNonce.count==32 && value.peerNonce.count==32 && value.localNonce != value.peerNonce)
        case .failure:outcome = .init(side:side,authenticated:false,scopeValid:false)
        }
        lock.lock();values.append(outcome);lock.unlock();group.leave()
    }
    func wait()->Bool { group.wait(timeout:.now()+45) == .success }
    func snapshot()->[PeerOutcome] { lock.lock();defer{lock.unlock()};return values.sorted{$0.side<$1.side} }
}
struct GateResult:Codable {
    let name:String;let expectedAuthentication:Bool;let timedOut:Bool;let peers:[PeerOutcome];let passed:Bool;let seconds:Double
}
@main
@available(macOS 15.0, *)
struct NativePeerGate {
    static func run(_ name:String,server:FixtureIdentity,expectedClient:FixtureIdentity,presentedClient:FixtureIdentity,generationMismatch:Bool=false,wantSuccess:Bool) throws -> GateResult {
        let serverGeneration=UUID(),clientGeneration=generationMismatch ? UUID() : serverGeneration
        let serverPair=try PeerTLSProbePair(identity:server.identity,scannedPeerSHA256:expectedClient.pin,peerCertificateDER:expectedClient.der,generation:serverGeneration)
        let clientPair=try PeerTLSProbePair(identity:presentedClient.identity,scannedPeerSHA256:server.pin,peerCertificateDER:server.der,generation:clientGeneration)
        let listener=PeerTLSProbe(pair:serverPair),client=PeerTLSProbe(pair:clientPair),results=PairResults()
        let clientPin=server.pin,serverPin=expectedClient.pin,start=Date()
        listener.listen(on:.any,ready:{port in
            client.connect(to:.hostPort(host:"127.0.0.1",port:port)){result in
                results.append("client",result,pin:clientPin,generation:clientGeneration)
            }
        },completion:{result in results.append("server",result,pin:serverPin,generation:serverGeneration)})
        let completed=results.wait()
        listener.cancel();client.cancel()
        let peers=results.snapshot()
        let passed=completed && peers.count==2 && (wantSuccess ? peers.allSatisfy{$0.authenticated && $0.scopeValid} : peers.allSatisfy{!$0.authenticated})
        return .init(name:name,expectedAuthentication:wantSuccess,timedOut:!completed,peers:peers,passed:passed,seconds:Date().timeIntervalSince(start))
    }
    static func main() async throws {
        guard CommandLine.arguments.count==3 else { throw GateError.failed("usage: gate FIXTURE_DIR RESULTS_JSON") }
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        let password=try String(contentsOf:root.appendingPathComponent("passphrase.txt"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
        let a=try FixtureIdentity(root:root,name:"a",password:password),b=try FixtureIdentity(root:root,name:"b",password:password),c=try FixtureIdentity(root:root,name:"c",password:password)
        var results:[GateResult]=[]
        func record(_ result:GateResult)throws {
            results.append(result)
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(results).write(to:output,options:.atomic)
            print("\(result.name): \(result.passed ? "PASS" : "FAIL")")
        }
        try record(run("valid-pair",server:a,expectedClient:b,presentedClient:b,wantSuccess:true))
        try record(run("unpaired-client",server:a,expectedClient:b,presentedClient:c,wantSuccess:false))
        try record(run("generation-mismatch",server:a,expectedClient:b,presentedClient:b,generationMismatch:true,wantSuccess:false))
        for name in ["expired","future","wrong-usage","critical","bad-signature"] {
            let fixture=try FixtureIdentity(root:root,name:name,password:password)
            try record(run(name,server:a,expectedClient:fixture,presentedClient:fixture,wantSuccess:false))
        }
        try NativeChannelChecks.run(root: root, password: password, output: output.deletingLastPathComponent().appendingPathComponent("channel-results.json"))
        try await NativeTextExchangeChecks.run(root: root, password: password, output: output.deletingLastPathComponent().appendingPathComponent("text-exchange-results.json"))
        try await NativeAutomaticSyncChecks.run(root: root, password: password, output: output.deletingLastPathComponent().appendingPathComponent("automatic-sync-results.json"))
        guard results.allSatisfy(\.passed) else { throw GateError.failed("Native pairing acceptance failed; probe must remain disabled.") }
    }
}
