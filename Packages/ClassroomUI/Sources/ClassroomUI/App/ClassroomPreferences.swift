import Foundation

/// Per-user preferences of the Class area, shared with the host app through UserDefaults.
public enum ClassroomPreferences {
    /// "Follow the whole class": the host app adds every published lesson (required and
    /// optional) to the student's Homework weeks and keeps progress in step both ways.
    public static func followWholeClassKey(for userID: UUID) -> String {
        "classroom.followWholeClass.\(userID.uuidString.lowercased())"
    }
}
