import Foundation
import CryptoKit

struct PS3GameUpdatePackage: Identifiable, Hashable {
    let version: String
    let size: UInt64
    let sha1: String
    let url: String
    let requiredSystemVersion: String

    var id: String { "\(version)|\(url)" }
}

enum PS3GameUpdateManifest {
    static func parse(_ data: Data) throws -> [PS3GameUpdatePackage] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? NSError(
                domain: "RPCS3.GameUpdateManifest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Sony's game-update manifest is invalid XML."]
            )
        }

        let unique = Dictionary(grouping: delegate.packages, by: \.id)
            .compactMap { $0.value.first }
        return unique.sorted { compareVersions($0.version, $1.version) == .orderedAscending }
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compareVersions(candidate, installed) == .orderedDescending
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }

        return lhs.localizedStandardCompare(rhs)
    }

    private static func versionComponents(_ value: String) -> [Int] {
        value.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var packages: [PS3GameUpdatePackage] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName.caseInsensitiveCompare("package") == .orderedSame else {
                return
            }

            let version = attributeDict["version"] ?? ""
            let url = attributeDict["url"] ?? ""
            let sha1 = (attributeDict["sha1sum"] ?? attributeDict["sha1"] ?? "").uppercased()
            let system = attributeDict["ps3_system_ver"] ?? attributeDict["system_ver"] ?? ""
            guard !version.isEmpty,
                  !url.isEmpty,
                  let sizeText = attributeDict["size"],
                  let size = UInt64(sizeText),
                  size > 0 else {
                return
            }

            packages.append(PS3GameUpdatePackage(
                version: version,
                size: size,
                sha1: sha1,
                url: url,
                requiredSystemVersion: system
            ))
        }
    }
}

enum PS3PackageIntegrity {
    static func sha1Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = Insecure.SHA1()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02X", $0) }.joined()
    }
}
