import Foundation

protocol ProfileScopedRecord {
    var profileID: UUID? { get set }
}

extension BabyEvent: ProfileScopedRecord {}
extension SleepPredictionRecord: ProfileScopedRecord {}
extension MilestoneEntry: ProfileScopedRecord {}
extension DoctorAppointment: ProfileScopedRecord {}
extension AgeGuideReadState: ProfileScopedRecord {}
extension PuppyStageGuideReadState: ProfileScopedRecord {}

extension ProfileScopedRecord {
    func matchesProfile(_ selectedProfileID: UUID?) -> Bool {
        guard let selectedProfileID else { return true }
        return profileID == selectedProfileID
    }
}
