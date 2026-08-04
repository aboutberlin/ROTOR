import Foundation

extension L10n {
    public enum CANStatus {
        public static let level1Title = L10nKey("can_status.level_1_title", "RPM / Current")
        public static let level2Title = L10nKey("can_status.level_2_title", "Amp-hours")
        public static let level3Title = L10nKey("can_status.level_3_title", "Watt-hours")
        public static let level4Title = L10nKey("can_status.level_4_title", "Temperature / Position")
        public static let level5Title = L10nKey("can_status.level_5_title", "Mileage / Voltage")
        public static let status1Detail = L10nKey("can_status.status_1_detail", "STATUS_1: ERPM, Motor Current, Duty Cycle")
        public static let status2Detail = L10nKey("can_status.status_2_detail", "STATUS_2: Amp-hour Consumption, Regeneration")
        public static let status3Detail = L10nKey("can_status.status_3_detail", "STATUS_3: Watt-hour Consumption, Regeneration")
        public static let status4Detail = L10nKey("can_status.status_4_detail", "STATUS_4: MOS Temperature, Motor Temperature, Input Current, PID Position")
        public static let status5Detail = L10nKey("can_status.status_5_detail", "STATUS_5: Mileage, Input Voltage")
        public static let boxTooltipLevel = L10nKey("can_status.box_tooltip_level", "Level %@: Broadcasting %@ status frames below")
        public static let boxTooltipCumulative = L10nKey("can_status.box_tooltip_cumulative", "Levels accumulate; enabling this level also enables all preceding levels.")
        public static let boxTooltipWrite = L10nKey("can_status.box_tooltip_write", "Changes only affect pending configuration; click 'Write to Motor' in the top-right to apply.")
        public static let tooltipIntro = L10nKey("can_status.tooltip_intro", "send_can_status: CAN periodic status frame switch; levels accumulate.")
        public static let tooltipOff = L10nKey("can_status.tooltip_off", "0 Disabled; no status frames broadcast.")
        public static let tooltipDefault = L10nKey("can_status.tooltip_default", "Factory default is 1; temperature, input current, position, mileage, and input voltage are unavailable by default.")
        public static let tooltipNote = L10nKey("can_status.tooltip_note", "Increasing this level requires no firmware changes; it's just an application configuration byte.")

        public static let all: [L10nKey] = [
            level1Title, level2Title, level3Title, level4Title, level5Title,
            status1Detail, status2Detail, status3Detail, status4Detail, status5Detail,
            boxTooltipLevel, boxTooltipCumulative, boxTooltipWrite,
            tooltipIntro, tooltipOff, tooltipDefault, tooltipNote,
        ]
    }
}
