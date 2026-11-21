import ArgumentParser
#if SWIFT_PACKAGE
import MacnitorCLICore
#endif

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct MacnitorExecutable: AsyncParsableCommand {
    static let configuration = MacnitorCommand.configuration
}
