import ArgumentParser
#if SWIFT_PACKAGE
import MactricsCLICore
#endif

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct MactricsExecutable: AsyncParsableCommand {
    static let configuration = MactricsCommand.configuration
}
