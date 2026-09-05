import Darwin
import Foundation

@main
enum PureTestRunner {
    static func main() {
        let suites = clockTests + traceTests
        var failures = 0
        for (name, test) in suites {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures += 1
                FileHandle.standardError.write(Data("FAIL \(name)\n  \(error)\n".utf8))
            }
        }
        print("\(suites.count - failures) passed; \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
