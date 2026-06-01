import Foundation

public enum ProjectConfigManager {
    public static let defaultDiscoveryRoots = [
        "\(NSHomeDirectory())/Documents/GitHub"
    ]

    public static func loadAll(from url: URL = URL(fileURLWithPath: ProjectConfigLoader.defaultConfigPath)) throws -> [ProjectConfig] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try ProjectConfigLoader.decode(data).projects
    }

    public static func save(
        _ projects: [ProjectConfig],
        to url: URL = URL(fileURLWithPath: ProjectConfigLoader.defaultConfigPath)
    ) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(ProjectsConfigFile(projects: projects))
        try data.write(to: url, options: .atomic)
    }

    public static func syncDiscoveredProjects(
        configURL: URL = URL(fileURLWithPath: ProjectConfigLoader.defaultConfigPath),
        discoveryRoots: [String] = defaultDiscoveryRoots
    ) throws -> ProjectConfigSyncResult {
        let current = try loadAll(from: configURL)
        let existing = current.filter { FileManager.default.fileExists(atPath: $0.path) }
        let removed = current.filter { !FileManager.default.fileExists(atPath: $0.path) }
        let knownPaths = Set(existing.map { canonicalPath($0.path) })
        let knownIDs = Set(existing.map(\.id))
        let discoveredPaths = discoverGitRepositories(roots: discoveryRoots)

        var usedIDs = knownIDs
        let added = discoveredPaths
            .filter { !knownPaths.contains(canonicalPath($0)) }
            .map { path -> ProjectConfig in
                let id = uniqueID(for: path, usedIDs: &usedIDs)
                let displayName = displayName(for: path)
                return ProjectConfig(
                    id: id,
                    shortName: shortName(for: displayName),
                    displayName: displayName,
                    path: path,
                    group: "AUTO",
                    enabled: true
                )
            }

        let next = (existing + added).sorted {
            if $0.group != $1.group { return $0.group < $1.group }
            return $0.shortName < $1.shortName
        }
        try save(next, to: configURL)

        return ProjectConfigSyncResult(
            added: added,
            removed: removed,
            total: next.count,
            configPath: configURL.path
        )
    }

    public static func addProject(
        path: String,
        shortName: String,
        displayName: String,
        group: String,
        configURL: URL = URL(fileURLWithPath: ProjectConfigLoader.defaultConfigPath)
    ) throws -> ProjectConfigSyncResult {
        let cleanedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPath.isEmpty else {
            throw ProjectConfigError.invalidPath
        }
        guard FileManager.default.fileExists(atPath: cleanedPath) else {
            throw ProjectConfigError.pathNotFound(cleanedPath)
        }

        var current = try loadAll(from: configURL)
        let canonical = canonicalPath(cleanedPath)
        guard !current.contains(where: { canonicalPath($0.path) == canonical }) else {
            throw ProjectConfigError.duplicatePath(cleanedPath)
        }

        var usedIDs = Set(current.map(\.id))
        let resolvedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: Self.displayName(for: cleanedPath))
        let resolvedShortName = shortName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: Self.shortName(for: resolvedDisplayName))
        let resolvedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: "MANUAL")
        let project = ProjectConfig(
            id: uniqueID(for: cleanedPath, usedIDs: &usedIDs),
            shortName: resolvedShortName,
            displayName: resolvedDisplayName,
            path: cleanedPath,
            group: resolvedGroup,
            enabled: true
        )

        current.append(project)
        try save(current, to: configURL)
        return ProjectConfigSyncResult(added: [project], removed: [], total: current.count, configPath: configURL.path)
    }

    public static func removeProject(
        id: String,
        configURL: URL = URL(fileURLWithPath: ProjectConfigLoader.defaultConfigPath)
    ) throws -> ProjectConfigSyncResult {
        let current = try loadAll(from: configURL)
        let removed = current.filter { $0.id == id }
        guard !removed.isEmpty else {
            throw ProjectConfigError.projectNotFound(id)
        }

        let next = current.filter { $0.id != id }
        try save(next, to: configURL)
        return ProjectConfigSyncResult(added: [], removed: removed, total: next.count, configPath: configURL.path)
    }

    public static func discoverGitRepositories(roots: [String], maxDepth: Int = 2) -> [String] {
        var repositories = Set<String>()
        let skippedNames = ["node_modules", ".build", ".git", "DerivedData", "Library"]

        for rootPath in roots {
            let root = URL(fileURLWithPath: rootPath)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if skippedNames.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }

                let depth = url.pathComponents.count - root.pathComponents.count
                if depth > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }

                if isGitRepositoryPath(url.path) {
                    repositories.insert(url.path)
                    enumerator.skipDescendants()
                }
            }

            if isGitRepositoryPath(root.path) {
                repositories.insert(root.path)
            }
        }

        return repositories.sorted()
    }

    public enum ProjectConfigError: LocalizedError, Equatable {
        case invalidPath
        case pathNotFound(String)
        case duplicatePath(String)
        case projectNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .invalidPath:
                return "Project path is required."
            case .pathNotFound(let path):
                return "Project path not found: \(path)"
            case .duplicatePath(let path):
                return "Project already exists in config: \(path)"
            case .projectNotFound(let id):
                return "Project not found in config: \(id)"
            }
        }
    }

    private static func isGitRepositoryPath(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent(".git").path)
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func displayName(for path: String) -> String {
        URL(fileURLWithPath: path)
            .lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private static func shortName(for displayName: String) -> String {
        let words = displayName.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        let initials = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        if !initials.isEmpty {
            return String(initials.prefix(6))
        }
        return String(displayName.prefix(6)).uppercased()
    }

    private static func uniqueID(for path: String, usedIDs: inout Set<String>) -> String {
        let raw = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let base = raw
            .map { character -> Character in
                if character.isLetter || character.isNumber { return character }
                return "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .nonEmpty(or: "project")

        var candidate = base
        var suffix = 2
        while usedIDs.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        usedIDs.insert(candidate)
        return candidate
    }
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
