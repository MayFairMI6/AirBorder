import Foundation

struct GTFSStopTime: Equatable, Sendable {
    let tripID: String
    let arrivalTime: String
    let departureTime: String
    let stopID: String
    let stopSequence: Int
}

struct GTFSService: Sendable {
    func parseStops(_ csv: String) throws -> [TransitStop] {
        let rows = parseCSV(csv)
        guard let header = rows.first else { return [] }
        let index = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        guard let idIndex = index["stop_id"], let nameIndex = index["stop_name"],
              let latIndex = index["stop_lat"], let lonIndex = index["stop_lon"] else {
            throw GTFSParseError.missingRequiredColumn
        }
        return try rows.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { row in
            guard row.indices.contains(idIndex), row.indices.contains(nameIndex),
                  row.indices.contains(latIndex), row.indices.contains(lonIndex),
                  let latitude = Double(row[latIndex]), let longitude = Double(row[lonIndex]) else {
                throw GTFSParseError.invalidRow
            }
            let wheelchair = index["wheelchair_boarding"].flatMap { row.indices.contains($0) ? Int(row[$0]) : nil }
            return TransitStop(id: row[idIndex], name: row[nameIndex], latitude: latitude, longitude: longitude, wheelchairBoarding: wheelchair)
        }
    }

    func parseStopTimes(_ csv: String) throws -> [GTFSStopTime] {
        let rows = parseCSV(csv)
        guard let header = rows.first else { return [] }
        let index = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        let required = ["trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence"]
        guard required.allSatisfy({ index[$0] != nil }) else { throw GTFSParseError.missingRequiredColumn }
        return try rows.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { row in
            func value(_ key: String) throws -> String {
                guard let position = index[key], row.indices.contains(position) else { throw GTFSParseError.invalidRow }
                return row[position]
            }
            guard let sequence = Int(try value("stop_sequence")) else { throw GTFSParseError.invalidRow }
            return GTFSStopTime(tripID: try value("trip_id"), arrivalTime: try value("arrival_time"), departureTime: try value("departure_time"), stopID: try value("stop_id"), stopSequence: sequence)
        }
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if character == "\n", !isQuoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

enum GTFSParseError: Error, Equatable, Sendable {
    case missingRequiredColumn
    case invalidRow
}

