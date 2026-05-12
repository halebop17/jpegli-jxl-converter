import Foundation
import CLcms2

/// Thin Little CMS wrapper. Currently only used to validate ICC profile
/// bytes before attaching them to a destination via libexiv2.
///
/// Profile parsing/conversion is reserved for future work — the Python
/// pipeline does not transform image data through ICC, it merely embeds
/// the profile, and we mirror that behaviour.
enum ColorManager {

    /// Returns true if the given byte buffer parses as a valid ICC profile.
    static func isValidProfile(_ data: Data) -> Bool {
        var ok = false
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            if let profile = cmsOpenProfileFromMem(base, cmsUInt32Number(raw.count)) {
                cmsCloseProfile(profile)
                ok = true
            }
        }
        return ok
    }
}
