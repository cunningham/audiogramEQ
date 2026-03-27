import Foundation

/// Service for browsing and fetching headphone/speaker frequency response data
/// from the AutoEQ GitHub repository (jaakkopasanen/AutoEq).
///
/// Data source: https://github.com/jaakkopasanen/AutoEq
/// License: MIT — Attribution provided in UI.
@MainActor @Observable
final class AutoEQService {
    var headphoneIndex: [AutoEQEntry] = []
    var isLoading = false
    var errorMessage: String?
    var searchResults: [AutoEQEntry] = []

    private let baseRawURL = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results"
    private let apiBaseURL = "https://api.github.com/repos/jaakkopasanen/AutoEq"

    struct AutoEQEntry: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let path: String
        let source: String

        var displayName: String { name }
        var attribution: String { "Data from AutoEQ by Jaakko Pasanen (MIT License)" }
    }

    /// Fetch the index of available headphone measurements from the AutoEQ repo.
    /// Uses the GitHub API to list directories under results/.
    func fetchIndex() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Use the GitHub Trees API for efficient directory listing
            let treeURL = URL(string: "\(apiBaseURL)/git/trees/master?recursive=1")!
            var request = URLRequest(url: treeURL)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw AutoEQError.apiError("GitHub API returned non-200 status")
            }

            let tree = try JSONDecoder().decode(GitHubTree.self, from: data)

            // Find all ParametricEQ.txt files — these are the usable EQ files
            // Also find raw FR CSV files
            var entries: [AutoEQEntry] = []
            let seen = NSMutableSet()

            for item in tree.tree {
                // Look for frequency response CSV files in results/
                guard item.path.hasPrefix("results/") else { continue }
                guard item.type == "blob" else { continue }

                let pathComponents = item.path.components(separatedBy: "/")
                // Typical structure: results/<source>/<headphone name>/<headphone name>.csv
                guard pathComponents.count >= 3 else { continue }

                let isCSV = item.path.hasSuffix(".csv")

                if isCSV {
                    let source = pathComponents[1]
                    let headphoneName: String
                    if pathComponents.count >= 4 {
                        headphoneName = pathComponents[2]
                    } else {
                        headphoneName = pathComponents.last!.replacingOccurrences(of: ".csv", with: "")
                    }

                    let entryID = "\(source)/\(headphoneName)"
                    if !seen.contains(entryID) {
                        seen.add(entryID)
                        entries.append(AutoEQEntry(
                            id: entryID,
                            name: headphoneName,
                            path: item.path,
                            source: source
                        ))
                    }
                }
            }

            entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            self.headphoneIndex = entries
            self.searchResults = entries
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to fetch AutoEQ index: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    /// Search the index by headphone name
    func search(_ query: String) {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            searchResults = headphoneIndex
        } else {
            let lowered = query.lowercased()
            searchResults = headphoneIndex.filter {
                $0.name.lowercased().contains(lowered) ||
                $0.source.lowercased().contains(lowered)
            }
        }
    }

    /// Fetch the actual frequency response data for a specific entry
    func fetchFrequencyResponse(for entry: AutoEQEntry) async throws -> FrequencyResponseCurve {
        let rawURL = URL(string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/\(entry.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.path)")!

        var request = URLRequest(url: rawURL)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AutoEQError.downloadFailed("Could not download data for \(entry.name)")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw AutoEQError.parseError("Could not decode file content")
        }

        let parser = DeviceResponseParser()
        var curve = try parser.parse(from: text, deviceName: entry.name, deviceType: .headphone)
        curve.source = entry.attribution
        return curve
    }

    enum AutoEQError: LocalizedError {
        case apiError(String)
        case downloadFailed(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .apiError(let msg): msg
            case .downloadFailed(let msg): msg
            case .parseError(let msg): msg
            }
        }
    }
}

// MARK: - GitHub API Models

private struct GitHubTree: Codable {
    let sha: String
    let tree: [TreeEntry]
    let truncated: Bool

    struct TreeEntry: Codable {
        let path: String
        let mode: String
        let type: String
        let sha: String
        let size: Int?
    }
}
