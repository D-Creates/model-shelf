import Foundation

/// Launch arguments used by tests, screenshots and manual QA:
/// `-resetData` wipes demo files and saved notes/tags, `-demo` generates tiny
/// fake header files and opens them, `-tab=N` selects the initial tab.
public enum LaunchArguments {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    /// Combined single-token form: "-cfg=tab=2|demo=1|reset=1" (simulator
    /// launches may drop extra argv tokens, so tests pass both forms).
    private static func cfgValue(_ key: String) -> String? {
        for arg in args where arg.hasPrefix("-cfg=") {
            for pair in arg.dropFirst("-cfg=".count).split(separator: "|") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 && kv[0] == key { return String(kv[1]) }
            }
        }
        return nil
    }

    public static var resetData: Bool { args.contains("-resetData") || cfgValue("reset") == "1" || cfgValue("resetData") == "1" }
    public static var demo: Bool { args.contains("-demo") || cfgValue("demo") == "1" }
    public static var seedScreenshots: Bool { args.contains("-seedScreenshots") || cfgValue("seedScreenshots") == "1" }
    public static var scrollToNotes: Bool { args.contains("-scrollToNotes") || cfgValue("scrollToNotes") == "1" }

    public static var tab: Int? {
        if let v = cfgValue("tab") { return Int(v) }
        for arg in args where arg.hasPrefix("-tab=") {
            return Int(arg.dropFirst("-tab=".count))
        }
        return nil
    }
}
