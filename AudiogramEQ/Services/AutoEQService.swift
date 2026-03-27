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

    private let baseRawURL = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/measurements"
    private let apiBaseURL = "https://api.github.com/repos/jaakkopasanen/AutoEq"

    struct AutoEQEntry: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let path: String
        let source: String
        let category: String

        var displayName: String { name }
        var attribution: String { "Data from AutoEQ by Jaakko Pasanen (MIT License)" }
    }

    /// Fetch the index of available headphone measurements from the AutoEQ repo.
    /// Uses the GitHub API to list files under measurements/.
    func fetchIndex() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Step 1: Get the SHA of the measurements directory from the top-level tree
            let topTreeURL = URL(string: "\(apiBaseURL)/git/trees/master")!
            var topRequest = URLRequest(url: topTreeURL)
            topRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            topRequest.timeoutInterval = 30

            let (topData, topResponse) = try await URLSession.shared.data(for: topRequest)
            guard let topHTTP = topResponse as? HTTPURLResponse, topHTTP.statusCode == 200 else {
                throw AutoEQError.apiError("GitHub API returned non-200 status for top-level tree")
            }

            let topTree = try JSONDecoder().decode(GitHubTree.self, from: topData)
            guard let measurementsEntry = topTree.tree.first(where: { $0.path == "measurements" && $0.type == "tree" }) else {
                throw AutoEQError.apiError("Could not find measurements directory in repository")
            }

            // Step 2: Fetch the measurements subtree recursively
            let measURL = URL(string: "\(apiBaseURL)/git/trees/\(measurementsEntry.sha)?recursive=1")!
            var measRequest = URLRequest(url: measURL)
            measRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            measRequest.timeoutInterval = 60

            let (measData, measResponse) = try await URLSession.shared.data(for: measRequest)
            guard let measHTTP = measResponse as? HTTPURLResponse, measHTTP.statusCode == 200 else {
                throw AutoEQError.apiError("GitHub API returned non-200 status for measurements tree")
            }

            let measTree = try JSONDecoder().decode(GitHubTree.self, from: measData)

            // Find all .csv and .txt measurement files
            // Structure: <source>/data/<type>/<rig>/<headphone name>.<ext>
            var entries: [AutoEQEntry] = []
            let seen = NSMutableSet()

            for item in measTree.tree {
                guard item.type == "blob" else { continue }

                let isCSV = item.path.hasSuffix(".csv")
                let isTXT = item.path.hasSuffix(".txt")
                guard isCSV || isTXT else { continue }

                let pathComponents = item.path.components(separatedBy: "/")
                // Expected: <source>/data/<type>/<rig>/<name>.ext (5 components)
                // or: <source>/data/<type>/<name>.ext (4 components)
                // or: <source>/<name>.ext (2 components)
                guard pathComponents.count >= 2 else { continue }

                let source = pathComponents[0]
                let fileName = pathComponents.last!
                let ext = isCSV ? ".csv" : ".txt"
                let headphoneName = String(fileName.dropLast(ext.count))

                // Determine category (type) if available
                let category: String
                if pathComponents.count >= 4, pathComponents[1] == "data" {
                    category = pathComponents[2] // e.g. "over-ear", "in-ear", "earbud"
                } else {
                    category = ""
                }

                let entryID = "\(source)/\(headphoneName)"
                if !seen.contains(entryID) {
                    seen.add(entryID)
                    entries.append(AutoEQEntry(
                        id: entryID,
                        name: headphoneName,
                        path: "measurements/\(item.path)",
                        source: source,
                        category: category
                    ))
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
