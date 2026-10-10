import Foundation

public enum Identity {
    /// Bundle identifier of the app; the helper only accepts XPC clients signed with this identifier + its own Team ID.
    public static let appID = "com.hamardikan.smart-work"
    public static let helperMachService = "com.hamardikan.smart-work.helper"
    /// File name of the launchd plist in Contents/Library/LaunchDaemons.
    public static let helperPlist = "com.hamardikan.smart-work.helper.plist"
    /// Present while the helper has SleepDisabled on; lets a restarted helper undo a crash.
    public static let markerPath = "/var/db/com.hamardikan.smart-work.sleep-disabled"
}
