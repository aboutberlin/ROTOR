import Foundation

extension L10n {
    /// 设备页：把工具对这台设备的三项判断摊开给人看。
    public enum Device {
        public static let title = L10nKey("device.title", "Device")
        public static let notConnected = L10nKey("device.not_connected", "Not connected")
        public static let notConnectedDetail = L10nKey(
            "device.not_connected_detail",
            "Connect a motor to see what this tool was able to determine about it.")

        public static let identity = L10nKey("device.identity", "Identity")
        public static let identityDetail = L10nKey(
            "device.identity_detail",
            "Reported by the device during handshake. This is the only thing the tool is told; everything below is derived from it.")

        // MARK: 三个旋钮

        public static let profile = L10nKey("device.profile", "Device profile")
        public static let profileDetailRegistered = L10nKey(
            "device.profile_detail_registered",
            "This model is in the registry, so its capabilities and limits were entered deliberately and have been checked against hardware.")
        public static let profileDetailProvisional = L10nKey(
            "device.profile_detail_provisional",
            "No registry entry for this model. The profile was inferred from the protocol family alone — pole count, gear ratio, current limits and encoder type are all unverified. Editing, writing and detection stay disabled.")

        public static let schema = L10nKey("device.schema", "Parameter table")
        public static let schemaDetailMatch = L10nKey(
            "device.schema_detail_match",
            "The layout signature reported by the firmware matches the bundled table, so every value is decoded at the offset it was written to.")
        public static let schemaDetailMismatch = L10nKey(
            "device.schema_detail_mismatch",
            "The firmware reports a layout this build has no table for. Values would be decoded at the wrong offsets, so the parameter page is blocked entirely.")
        public static let schemaDetailUnread = L10nKey(
            "device.schema_detail_unread",
            "Not read yet. MIT-mode firmware does not expose the configuration channel, so there is nothing to compare against.")

        public static let upload = L10nKey("device.upload", "Firmware upload")
        public static let uploadDetail = L10nKey(
            "device.upload_detail",
            "Chosen by the profile. The two paths are not variations of one another — one erases a staging area and writes by offset, the other streams fixed blocks over a session-token handshake.")

        // MARK: 其余事实

        public static let capabilities = L10nKey("device.capabilities", "Capabilities")
        public static let capabilitiesNone = L10nKey("device.capabilities_none", "none claimed")
        public static let capabilitiesDetail = L10nKey(
            "device.capabilities_detail",
            "What the tool will let you do with this device. A capability is claimed only when the profile says so, never guessed from the firmware version.")
        public static let telemetryLayout = L10nKey("device.telemetry_layout", "Telemetry layout")
        public static let link = L10nKey("device.link", "Link")

        // MARK: 状态标记

        public static let stateConfirmed = L10nKey("device.state_confirmed", "confirmed")
        public static let stateInferred = L10nKey("device.state_inferred", "inferred")
        public static let stateBlocked = L10nKey("device.state_blocked", "blocked")
        public static let stateUnknown = L10nKey("device.state_unknown", "unknown")

        public static let whatIsMissing = L10nKey("device.what_is_missing", "To promote this device")
        public static let whatIsMissingDetail = L10nKey(
            "device.what_is_missing_detail",
            "The handshake already supplies the identity, protocol family, table signature and parameter count. Still needed, from the datasheet: pole count, gear ratio, continuous and peak current, encoder type. Deliberate policy: a motor is registered when it is actually going to be used, not in advance — an unverified entry would silently unlock writing.")

        public static let all: [L10nKey] = [
            title, notConnected, notConnectedDetail,
            identity, identityDetail,
            profile, profileDetailRegistered, profileDetailProvisional,
            schema, schemaDetailMatch, schemaDetailMismatch, schemaDetailUnread,
            upload, uploadDetail,
            capabilities, capabilitiesNone, capabilitiesDetail,
            telemetryLayout, link,
            stateConfirmed, stateInferred, stateBlocked, stateUnknown,
            whatIsMissing, whatIsMissingDetail,
        ]
    }
}
