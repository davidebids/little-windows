import Foundation

protocol ProfileScopedRecord: AnyObject {
    var profileID: UUID? { get set }
}

extension CareEvent: ProfileScopedRecord {}
extension SleepPredictionRecord: ProfileScopedRecord {}
extension MilestoneEntry: ProfileScopedRecord {}
extension DoctorAppointment: ProfileScopedRecord {}
extension AppointmentFollowUp: ProfileScopedRecord {}
extension HouseholdAttentionAcknowledgement: ProfileScopedRecord {}
extension HouseholdAttentionClaim: ProfileScopedRecord {}
extension CaregiverHandoffNote: ProfileScopedRecord {}
extension AgeGuideReadState: ProfileScopedRecord {}
extension PuppyStageGuideReadState: ProfileScopedRecord {}

extension ProfileScopedRecord {
    func matchesProfile(_ selectedProfileID: UUID?) -> Bool {
        guard let selectedProfileID else { return true }
        return profileID == selectedProfileID
    }
}
