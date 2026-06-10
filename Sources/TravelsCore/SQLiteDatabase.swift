// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import CSQLite
import Foundation

final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let message = SQLiteDatabase.message(from: handle)
            sqlite3_close(handle)
            handle = nil
            throw TravelsError.databaseOpenFailed(message)
        }
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close(handle)
    }

    func close() {
        lock.withLock {
            guard let handle else { return }
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    func execute(_ sql: String, parameters: [SQLiteValue] = []) throws {
        try lock.withLock {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(parameters, to: statement)
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                throw TravelsError.databaseExecutionFailed(Self.message(from: handle))
            }
        }
    }

    func query(_ sql: String, parameters: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        try lock.withLock {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(parameters, to: statement)

            var rows: [[String: SQLiteValue]] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    break
                }
                guard result == SQLITE_ROW else {
                    throw TravelsError.databaseExecutionFailed(Self.message(from: handle))
                }

                var row: [String: SQLiteValue] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    row[name] = SQLiteValue(statement: statement, index: index)
                }
                rows.append(row)
            }
            return rows
        }
    }

    func integrityCheck() throws -> [String] {
        try query("PRAGMA integrity_check").compactMap { row in
            row["integrity_check"]?.string ?? row.values.first?.string
        }
    }

    func lastInsertRowID() -> Int64 {
        lock.withLock {
            sqlite3_last_insert_rowid(handle)
        }
    }

    func transaction<T>(_ work: () throws -> T) throws -> T {
        try lock.withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let value = try work()
                try execute("COMMIT")
                return value
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TravelsError.databaseExecutionFailed(Self.message(from: handle))
        }
        return statement
    }

    private func bind(_ parameters: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, index, integer)
            case .real(let double):
                result = sqlite3_bind_double(statement, index, double)
            case .text(let string):
                result = sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            }
            guard result == SQLITE_OK else {
                throw TravelsError.databaseExecutionFailed(Self.message(from: handle))
            }
        }
    }

    private static func message(from handle: OpaquePointer?) -> String {
        guard let pointer = sqlite3_errmsg(handle) else { return "unknown SQLite error" }
        return String(cString: pointer)
    }
}

private extension NSRecursiveLock {
    @discardableResult
    func withLock<T>(_ work: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try work()
    }
}

enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)

    init(statement: OpaquePointer?, index: Int32) {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            self = .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            self = .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            self = .text(String(cString: sqlite3_column_text(statement, index)))
        default:
            self = .null
        }
    }

    var int64: Int64? {
        switch self {
        case .integer(let value): value
        case .real(let value): Int64(value)
        case .text(let value): Int64(value)
        case .null: nil
        }
    }

    var double: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .real(let value): value
        case .text(let value): Double(value)
        case .null: nil
        }
    }

    var string: String? {
        switch self {
        case .integer(let value): String(value)
        case .real(let value): String(value)
        case .text(let value): value
        case .null: nil
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
