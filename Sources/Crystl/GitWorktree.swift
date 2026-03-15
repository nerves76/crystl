// GitWorktree.swift — Git worktree management for isolated agent sessions
//
// Contains:
//   - GitWorktree: Creates, lists, and removes git worktrees for sessions
//   - Worktrees live in .crystl/worktrees/{crystal-name} inside the project
//   - Branch names follow the pattern: crystl/{crystal-name}

import Foundation

class GitWorktree {

    /// Returns true if the directory is inside a git repository.
    static func isGitRepo(_ directory: String) -> Bool {
        let (_, status) = run("git", args: ["-C", directory, "rev-parse", "--is-inside-work-tree"])
        return status == 0
    }

    /// Returns the git root for a directory, or nil if not a git repo.
    static func gitRoot(_ directory: String) -> String? {
        let (output, status) = run("git", args: ["-C", directory, "rev-parse", "--show-toplevel"])
        guard status == 0 else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the current branch name.
    static func currentBranch(_ directory: String) -> String? {
        let (output, status) = run("git", args: ["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"])
        guard status == 0 else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Creates a worktree for the given crystal session name.
    /// Returns the worktree path on success, nil on failure.
    static func create(projectDir: String, crystalName: String) -> String? {
        guard let root = gitRoot(projectDir) else { return nil }

        let worktreeDir = root + "/.crystl/worktrees"
        let worktreePath = worktreeDir + "/" + crystalName
        let branchName = "crystl/" + crystalName

        // Ensure .crystl/worktrees directory exists
        let fm = FileManager.default
        try? fm.createDirectory(atPath: worktreeDir, withIntermediateDirectories: true)

        // Ensure .crystl/.gitignore exists with *
        let gitignorePath = root + "/.crystl/.gitignore"
        if !fm.fileExists(atPath: gitignorePath) {
            try? "*\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        }

        // Remove stale worktree if path exists but worktree is broken
        if fm.fileExists(atPath: worktreePath) {
            let (_, rmStatus) = run("git", args: ["-C", root, "worktree", "remove", "--force", worktreePath])
            if rmStatus != 0 {
                // Force remove directory if git can't clean it
                try? fm.removeItem(atPath: worktreePath)
            }
            // Also clean up the branch if it exists
            _ = run("git", args: ["-C", root, "branch", "-D", branchName])
        }

        // Create worktree with new branch from current HEAD
        let (output, status) = run("git", args: ["-C", root, "worktree", "add", "-b", branchName, worktreePath])
        if status != 0 {
            NSLog("Crystl: Failed to create worktree: \(output)")
            return nil
        }

        // Symlink untracked config files so agents can access them
        symlinkConfigs(from: root, to: worktreePath)

        NSLog("Crystl: Created worktree at \(worktreePath) on branch \(branchName)")
        return worktreePath
    }

    /// Symlinks key config files from the main project into the worktree
    /// if they exist in the source but not in the worktree (i.e. untracked/gitignored).
    private static func symlinkConfigs(from source: String, to worktree: String) {
        let fm = FileManager.default

        // Files to symlink
        let files = ["CLAUDE.md", "claude.md", "AGENTS.md", "agents.md", ".mcp.json"]
        for file in files {
            let srcPath = source + "/" + file
            let dstPath = worktree + "/" + file
            guard fm.fileExists(atPath: srcPath), !fm.fileExists(atPath: dstPath) else { continue }
            try? fm.createSymbolicLink(atPath: dstPath, withDestinationPath: srcPath)
            NSLog("Crystl: Symlinked \(file) into worktree")
        }

        // Directories to symlink
        let dirs = [".claude"]
        for dir in dirs {
            let srcPath = source + "/" + dir
            let dstPath = worktree + "/" + dir
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: srcPath, isDirectory: &isDir), isDir.boolValue,
                  !fm.fileExists(atPath: dstPath) else { continue }
            try? fm.createSymbolicLink(atPath: dstPath, withDestinationPath: srcPath)
            NSLog("Crystl: Symlinked \(dir)/ into worktree")
        }
    }

    /// Removes a worktree and its branch. Safe to call if already removed.
    static func remove(projectDir: String, crystalName: String) {
        guard let root = gitRoot(projectDir) else { return }

        let worktreePath = root + "/.crystl/worktrees/" + crystalName
        let branchName = "crystl/" + crystalName

        // Check if there are uncommitted changes
        let (diffOutput, _) = run("git", args: ["-C", worktreePath, "status", "--porcelain"])
        let hasChanges = !diffOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Check if there are commits ahead of the parent branch
        let hasCommits = commitsAhead(worktreePath: worktreePath, root: root) > 0

        if hasChanges || hasCommits {
            NSLog("Crystl: Worktree \(crystalName) has uncommitted changes or commits — keeping branch \(branchName)")
        }

        // Remove the worktree
        let (_, status) = run("git", args: ["-C", root, "worktree", "remove", "--force", worktreePath])
        if status != 0 {
            // Try harder
            try? FileManager.default.removeItem(atPath: worktreePath)
            _ = run("git", args: ["-C", root, "worktree", "prune"])
        }

        // Only delete the branch if it has no unique commits
        if !hasChanges && !hasCommits {
            _ = run("git", args: ["-C", root, "branch", "-D", branchName])
            NSLog("Crystl: Removed worktree and branch for \(crystalName)")
        } else {
            NSLog("Crystl: Removed worktree for \(crystalName), kept branch \(branchName)")
        }
    }

    /// Returns the number of commits the worktree branch is ahead of the base.
    static func commitsAhead(worktreePath: String, root: String) -> Int {
        // Find the merge base between the worktree HEAD and the main branch HEAD
        let (baseBranch, _) = run("git", args: ["-C", root, "rev-parse", "--abbrev-ref", "HEAD"])
        let base = baseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return 0 }

        let (countStr, status) = run("git", args: [
            "-C", worktreePath, "rev-list", "--count", "\(base)..HEAD"
        ])
        guard status == 0 else { return 0 }
        return Int(countStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Returns branch name for a worktree path.
    static func branchName(for worktreePath: String) -> String? {
        return currentBranch(worktreePath)
    }

    // MARK: - Shell Helpers

    private static func run(_ command: String, args: [String]) -> (String, Int32) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(command)")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("Error: \(error)", 1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, process.terminationStatus)
    }
}
