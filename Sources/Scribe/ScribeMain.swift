import ArgumentParser
import Dispatch
import Foundation

/// A synchronous process entry point keeps the GUI on the initial AppKit main
/// thread. ArgumentParser's generated async entry point runs even synchronous
/// subcommands from a Swift task; entering `NSApplication.run()` there occupies
/// MainActor forever and prevents every later UI task from executing.
@main
enum ScribeMain {
    static func main() {
        do {
            var command = try ScribeCommand.parseAsRoot()
            if let asyncCommand = command as? any AsyncParsableCommand {
                let runner = AsyncCommandRunner(command: asyncCommand)
                Task {
                    do {
                        try await runner.run()
                        Foundation.exit(EXIT_SUCCESS)
                    } catch {
                        ScribeCommand.exit(withError: error)
                    }
                }
                dispatchMain()
            } else {
                try command.run()
            }
        } catch {
            ScribeCommand.exit(withError: error)
        }
    }
}

private final class AsyncCommandRunner: @unchecked Sendable {
    private var command: any AsyncParsableCommand

    init(command: any AsyncParsableCommand) {
        self.command = command
    }

    func run() async throws {
        try await command.run()
    }
}
