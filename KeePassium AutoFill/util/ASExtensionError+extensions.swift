//  KeePassium Password Manager
//  Copyright © 2018–2022 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import AuthenticationServices

extension ASExtensionError.Code: CustomStringConvertible {
    public var description: String {
        switch self {
        case .failed:
            return ".failed"
        case .userCanceled:
            return ".userCanceled"
        case .userInteractionRequired:
            return ".userInteractionRequired"
        case .credentialIdentityNotFound:
            return ".credentialIdentityNotFound"
        @unknown default:
            return "(unknown)"
        }
    }
}
