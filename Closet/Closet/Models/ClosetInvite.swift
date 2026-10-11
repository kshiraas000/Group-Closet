import Foundation

enum ClosetInvite {
    /// Codes are stored unformatted; the dash is presentation only. The join
    /// RPC strips non-alphanumerics and compares case-insensitively, so a
    /// pasted code works with or without it.
    static func formatted(_ code: String) -> String {
        guard code.count == 10 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 5)
        return "\(code[..<mid])-\(code[mid...])"
    }

    static func shareMessage(closetName: String, inviteCode: String) -> String {
        """
        Join my closet "\(closetName)" on Closet

        Invite code: \(formatted(inviteCode))
        """
    }
}
