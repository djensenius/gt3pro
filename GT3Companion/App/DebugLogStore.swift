//
//  DebugLogStore.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// In-memory ring buffer of diagnostic log entries, viewable and exportable from Settings.
///
/// Warnings and errors are always captured. Debug/info messages are only recorded when
/// the user enables "Verbose Logging" in Settings. Call `DebugLogStore.shared.log(…)`
/// from BLE, auth, upload, and pairing code paths to capture diagnostics.
@MainActor
final class DebugLogStore: ObservableObject {
    static let shared = DebugLogStore()

    private static let maxEntries = 500

    @Published private(set) var entries: [LogEntry] = []
    @AppStorage("verboseLoggingEnabled") var verboseLoggingEnabled = true

    private init() {}

    func log(_ message: String, category: String = "App", level: LogEntry.Level = .info) {
        guard verboseLoggingEnabled || level == .warning || level == .error else { return }
        entries.append(LogEntry(timestamp: Date(), category: category, level: level, message: message))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    func clear() { entries.removeAll() }

    func export() -> String {
        let header = "GT3 Companion Debug Log — \(Date().formatted(.iso8601))\n\n"
        let body = entries.map { entry in
            let timestamp = entry.timestamp.formatted(.iso8601)
            let lvl = entry.level.rawValue.uppercased()
            return "[\(timestamp)] [\(lvl)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
        return header + (body.isEmpty ? "(no entries)" : body)
    }

    /// A suggested filename that includes the current date so saved files don't collide.
    var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "gt3-debug-\(formatter.string(from: Date())).log"
    }

    func makeFileDocument() -> LogFileDocument {
        LogFileDocument(content: export(), filename: exportFilename)
    }
}

// MARK: - LogFileDocument

/// A plain-text log file that can be saved directly to the Files app via `fileExporter`.
struct LogFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var content: String
    var filename: String

    init(content: String, filename: String = "gt3-debug.log") {
        self.content = content
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        content = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
        filename = "gt3-debug.log"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

// MARK: - LogEntry

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: String
    let level: Level
    let message: String

    enum Level: String {
        case debug, info, warning, error

        var symbol: String {
            switch self {
            case .debug:   return "⚙️"
            case .info:    return "ℹ️"
            case .warning: return "⚠️"
            case .error:   return "🔴"
            }
        }
    }
}
