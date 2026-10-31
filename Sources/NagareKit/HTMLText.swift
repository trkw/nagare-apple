import Foundation

public enum HTMLText {
    /// Plain text of an HTML fragment, for speech and previews.
    public static func plain(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<br\\s*/?>|</(p|div|li|h[1-6]|blockquote)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&amp;": "&"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum PushToken {
    /// APNs device tokens are sent to the server as lowercase hex.
    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
