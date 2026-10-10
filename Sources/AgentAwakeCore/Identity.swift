import Foundation

public enum Identity {
    /// Bundle identifier of the app; the helper only accepts XPC clients signed with this identifier + its own Team ID.
    public static let appID = "com.hamardikan.agent-awake"
    public static let helperMachService = "com.hamardikan.agent-awake.helper"
    /// File name of the launchd plist in Contents/Library/LaunchDaemons.
    public static let helperPlist = "com.hamardikan.agent-awake.helper.plist"
    /// Present while the helper has SleepDisabled on; lets a restarted helper undo a crash.
    public static let markerPath = "/var/db/com.hamardikan.agent-awake.sleep-disabled"
}
