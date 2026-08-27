import ActionCore

@main
struct ActionAgentMain {
    @MainActor
    static func main() {
        ActionAgentRuntime.run(arguments: CommandLine.arguments)
    }
}
