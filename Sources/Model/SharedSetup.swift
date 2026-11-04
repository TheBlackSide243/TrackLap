import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// A car setup exported from TrackLap, the .tracklapsetup file declared in Info.plist.
    static let trackLapSetup = UTType(exportedAs: "com.local.tracklap.setup")
}

/// A setup sent as a file: setups never go online, a file is the only way they leave the phone.
/// With the car it was made for, so the one who opens it knows what it is for.
struct SharedSetup: Codable {
    static let version = 1

    var format = SharedSetup.version
    var car: String
    var setup: CarSetup

    enum ReadError: LocalizedError {
        case unreadable, newer

        var errorDescription: String? {
            switch self {
            case .unreadable: L("Questo file non è un assetto di TrackLap.")
            case .newer: L("Questo assetto viene da una versione più nuova di TrackLap: aggiorna l'app.")
            }
        }
    }

    static func read(_ url: URL) throws -> SharedSetup {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if let head = try? JSONDecoder().decode(Head.self, from: data), head.format > version { throw ReadError.newer }
        guard let s = try? JSONDecoder().decode(SharedSetup.self, from: data) else { throw ReadError.unreadable }
        return s
    }

    /// Written to a temporary file named after the car and the setup.
    func write() throws -> URL {
        let name = [car, setup.displayName]
            .map { $0.filter { $0.isLetter || $0.isNumber || $0 == " " } }
            .joined(separator: " - ")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("setups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name + ".tracklapsetup")
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        return url
    }

    private struct Head: Decodable { var format: Int }
}

/// What the share sheet sends: the file is written only once a destination is picked.
struct SharedSetupFile: Transferable {
    let shared: SharedSetup

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .trackLapSetup) { item in
            SentTransferredFile(try item.shared.write())
        }
    }
}
