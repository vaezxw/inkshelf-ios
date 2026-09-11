import Foundation
import SwiftData

@Model
final class BookEntity {
    @Attribute(.unique) var id: String
    var title: String
    var author: String?
    var originRaw: String
    var sourceId: String?
    var sourceName: String?
    var bookUrl: String?
    var coverUrl: String?
    var intro: String?
    var contentRelativePath: String
    var lastChapterIndex: Int
    var lastScrollOffset: Double
    var lastReadAt: Date?
    var addedAt: Date
    var chapterCount: Int
    var updatedAt: Date
    var cloudR2Key: String?

    @Relationship(deleteRule: .cascade, inverse: \ChapterEntity.book)
    var chapters: [ChapterEntity]

    @Relationship(deleteRule: .cascade, inverse: \BookmarkEntity.book)
    var bookmarks: [BookmarkEntity]

    var origin: BookOrigin {
        get { BookOrigin(rawValue: originRaw) ?? .local }
        set { originRaw = newValue.rawValue }
    }

    var isRemote: Bool { origin == .remote }

    var progress: Double {
        guard chapterCount > 0 else { return 0 }
        let idx = min(max(lastChapterIndex, 0), max(chapterCount - 1, 0))
        return (Double(idx) + 0.01) / Double(chapterCount)
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        author: String? = nil,
        origin: BookOrigin = .local,
        sourceId: String? = nil,
        sourceName: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        intro: String? = nil,
        contentRelativePath: String,
        lastChapterIndex: Int = 0,
        lastScrollOffset: Double = 0,
        lastReadAt: Date? = nil,
        addedAt: Date = .now,
        chapterCount: Int = 0,
        updatedAt: Date = .now,
        cloudR2Key: String? = nil,
        chapters: [ChapterEntity] = [],
        bookmarks: [BookmarkEntity] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.originRaw = origin.rawValue
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.intro = intro
        self.contentRelativePath = contentRelativePath
        self.lastChapterIndex = lastChapterIndex
        self.lastScrollOffset = lastScrollOffset
        self.lastReadAt = lastReadAt
        self.addedAt = addedAt
        self.chapterCount = chapterCount
        self.updatedAt = updatedAt
        self.cloudR2Key = cloudR2Key
        self.chapters = chapters
        self.bookmarks = bookmarks
    }

    func touch() {
        updatedAt = .now
    }
}

@Model
final class ChapterEntity {
    var id: String
    var index: Int
    var title: String
    var remoteUrl: String?
    var startOffset: Int
    var length: Int
    var book: BookEntity?

    init(
        id: String = UUID().uuidString,
        index: Int,
        title: String,
        remoteUrl: String? = nil,
        startOffset: Int = 0,
        length: Int = 0,
        book: BookEntity? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.remoteUrl = remoteUrl
        self.startOffset = startOffset
        self.length = length
        self.book = book
    }
}

@Model
final class BookmarkEntity {
    var id: String
    var chapterIndex: Int
    var title: String
    var scrollOffset: Double
    var createdAt: Date
    var updatedAt: Date
    var book: BookEntity?

    init(
        id: String = UUID().uuidString,
        chapterIndex: Int,
        title: String,
        scrollOffset: Double = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        book: BookEntity? = nil
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.title = title
        self.scrollOffset = scrollOffset
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.book = book
    }
}

@Model
final class BookSourceEntity {
    @Attribute(.unique) var id: String
    var name: String
    var sourceUrl: String
    var enabled: Bool
    var legadoRaw: String
    var groupName: String?
    var addedAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        sourceUrl: String,
        enabled: Bool = true,
        legadoRaw: String,
        groupName: String? = nil,
        addedAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sourceUrl = sourceUrl
        self.enabled = enabled
        self.legadoRaw = legadoRaw
        self.groupName = groupName
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }

    func touch() {
        updatedAt = .now
    }
}
