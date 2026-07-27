import Foundation
import SwiftData

@MainActor
enum SolidFoodCatalogService {
    @discardableResult
    static func create(
        name: String,
        photoDraft: PhotoAttachmentDraft?,
        existingItems: [SolidFoodCatalogItem],
        context: ModelContext,
        now: Date = Date()
    ) -> SolidFoodCatalogItem? {
        let cleanedName = SolidFoodSelection.cleanedName(name)
        let normalizedName = SolidFoodSelection.normalizedName(cleanedName)
        guard !normalizedName.isEmpty else { return nil }

        if let existing = existingItems.first(where: { $0.normalizedName == normalizedName }) {
            return existing
        }

        if let photoDraft {
            insertPhoto(photoDraft, context: context)
        }
        let item = SolidFoodCatalogItem(
            name: cleanedName,
            photoAttachmentID: photoDraft?.id,
            createdAt: now,
            updatedAt: now
        )
        context.insert(item)
        guard PersistenceService.save(context: context) else { return nil }
        return item
    }

    @discardableResult
    static func update(
        _ item: SolidFoodCatalogItem,
        name: String,
        photoDraft: PhotoAttachmentDraft?,
        removeExistingPhoto: Bool,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let cleanedName = SolidFoodSelection.cleanedName(name)
        let normalizedName = SolidFoodSelection.normalizedName(cleanedName)
        guard !normalizedName.isEmpty else { return false }

        if let photoDraft {
            if let currentPhotoID = item.photoAttachmentID {
                PhotoAttachmentStore.deleteAttachments(with: [currentPhotoID], context: context)
            }
            insertPhoto(photoDraft, context: context)
            item.photoAttachmentID = photoDraft.id
        } else if removeExistingPhoto, let currentPhotoID = item.photoAttachmentID {
            PhotoAttachmentStore.deleteAttachments(with: [currentPhotoID], context: context)
            item.photoAttachmentID = nil
        }

        item.name = cleanedName
        item.normalizedName = normalizedName
        item.updatedAt = now
        return PersistenceService.save(context: context)
    }

    @discardableResult
    static func delete(
        _ item: SolidFoodCatalogItem,
        context: ModelContext
    ) -> Bool {
        if let photoAttachmentID = item.photoAttachmentID {
            PhotoAttachmentStore.deleteAttachments(
                with: [photoAttachmentID],
                context: context
            )
        }
        context.delete(item)
        return PersistenceService.save(context: context)
    }

    private static func insertPhoto(
        _ draft: PhotoAttachmentDraft,
        context: ModelContext
    ) {
        context.insert(PhotoAttachment(
            id: draft.id,
            profileID: nil,
            ownerKind: .solidFood,
            contentType: draft.contentType,
            filename: draft.filename,
            imageData: draft.imageData,
            thumbnailData: draft.thumbnailData,
            createdAt: draft.createdAt,
            updatedAt: draft.createdAt
        ))
    }
}
