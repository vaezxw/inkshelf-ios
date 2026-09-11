import Foundation
import SwiftData
import Combine

@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var isSyncing = false
    @Published var lastError: String?
    @Published var lastMessage: String?

    private var pushTask: Task<Void, Never>?
    private var boundContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: .inkshelfPrefsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.notePrefsChanged()
            }
            .store(in: &cancellables)
    }

    func bind(context: ModelContext) {
        boundContext = context
    }

    func notePrefsChanged() {
        guard let boundContext else { return }
        schedulePush(context: boundContext)
    }

    func requestOTP(email: String) async throws -> String? {
        let res = try await CloudAPIClient.requestOTP(email: email)
        return res.echoCode
    }

    func login(email: String, code: String) async throws {
        let res = try await CloudAPIClient.verifyOTP(email: email, code: code)
        CloudAuthStore.token = res.token
        CloudAuthStore.email = res.user.email
        CloudAuthStore.userId = res.user.id
        lastMessage = "已登录 \(res.user.email)"
    }

    func logout() {
        CloudAuthStore.clear()
        lastMessage = "已退出登录"
    }

    func syncNow(context: ModelContext, forceFullPull: Bool = false) async {
        guard CloudAuthStore.isLoggedIn, CloudConfig.syncEnabled else { return }
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let since = forceFullPull ? nil : CloudConfig.lastSyncAt
            let pulled = try await CloudAPIClient.pull(since: since)
            try applyPull(pulled, context: context)

            let pushBody = try buildPush(context: context)
            _ = try await CloudAPIClient.push(pushBody)

            if CloudConfig.syncLocalTxt {
                try await uploadLocalTXTIfNeeded(context: context)
                try await downloadMissingTXT(context: context, pulled: pulled)
                // Push again so r2Key metadata lands after optional TXT upload.
                let again = try buildPush(context: context)
                _ = try await CloudAPIClient.push(again)
            }

            CloudConfig.lastSyncAt = CloudAPIClient.date(from: pulled.serverTime) ?? .now
            lastMessage = "同步完成 · \(CloudAPIClient.isoString(CloudConfig.lastSyncAt ?? .now))"
        } catch {
            lastError = error.localizedDescription
            lastMessage = nil
        }
    }

    func schedulePush(context: ModelContext) {
        guard CloudAuthStore.isLoggedIn, CloudConfig.syncEnabled else { return }
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await syncNow(context: context)
        }
    }

    private func buildPush(context: ModelContext) throws -> CloudPushBody {
        let books = try context.fetch(FetchDescriptor<BookEntity>())
        let sources = try context.fetch(FetchDescriptor<BookSourceEntity>())
        let bookmarks = books.flatMap(\.bookmarks)

        let bookItems: [CloudSyncItem<CloudSyncBookPayload>] = books.map { book in
            let updated = book.updatedAt
            let chapterPayload: [CloudSyncChapterPayload]? = book.isRemote
                ? book.chapters.sorted { $0.index < $1.index }.map {
                    CloudSyncChapterPayload(index: $0.index, title: $0.title, remoteUrl: $0.remoteUrl)
                }
                : nil
            return CloudSyncItem(
                id: book.id,
                updatedAt: CloudAPIClient.isoString(updated),
                payload: CloudSyncBookPayload(
                    id: book.id,
                    title: book.title,
                    author: book.author,
                    originRaw: book.originRaw,
                    sourceId: book.sourceId,
                    sourceName: book.sourceName,
                    bookUrl: book.bookUrl,
                    coverUrl: book.coverUrl,
                    intro: book.intro,
                    lastChapterIndex: book.lastChapterIndex,
                    lastScrollOffset: book.lastScrollOffset,
                    lastReadAt: book.lastReadAt.map(CloudAPIClient.isoString),
                    addedAt: CloudAPIClient.isoString(book.addedAt),
                    chapterCount: book.chapterCount,
                    r2Key: book.cloudR2Key,
                    chapters: chapterPayload
                )
            )
        }

        let bookmarkItems: [CloudSyncItem<CloudSyncBookmarkPayload>] = bookmarks.map { bm in
            CloudSyncItem(
                id: bm.id,
                updatedAt: CloudAPIClient.isoString(bm.updatedAt),
                payload: CloudSyncBookmarkPayload(
                    id: bm.id,
                    bookId: bm.book?.id ?? "",
                    chapterIndex: bm.chapterIndex,
                    title: bm.title,
                    scrollOffset: bm.scrollOffset,
                    createdAt: CloudAPIClient.isoString(bm.createdAt)
                )
            )
        }.filter { !$0.payload.bookId.isEmpty }

        let sourceItems: [CloudSyncItem<CloudSyncSourcePayload>] = sources.map { src in
            CloudSyncItem(
                id: src.id,
                updatedAt: CloudAPIClient.isoString(src.updatedAt),
                payload: CloudSyncSourcePayload(
                    id: src.id,
                    name: src.name,
                    sourceUrl: src.sourceUrl,
                    enabled: src.enabled,
                    legadoRaw: src.legadoRaw,
                    groupName: src.groupName,
                    addedAt: CloudAPIClient.isoString(src.addedAt)
                )
            )
        }

        let prefs = ReaderPrefs.shared
        let prefsItem = CloudSyncItem(
            id: "prefs",
            updatedAt: CloudAPIClient.isoString(prefs.updatedAt),
            payload: CloudSyncPrefsPayload(
                readMode: prefs.readMode.rawValue,
                fontSize: prefs.fontSize,
                lineHeight: prefs.lineHeight,
                themeMode: prefs.themeMode.rawValue,
                autoReadEnabled: prefs.autoReadEnabled,
                autoReadSpeed: prefs.autoReadSpeed,
                followSystemBrightness: prefs.followSystemBrightness,
                brightness: prefs.brightness
            )
        )

        return CloudPushBody(
            books: bookItems,
            bookmarks: bookmarkItems,
            sources: sourceItems,
            prefs: prefsItem
        )
    }

    private func applyPull(_ pulled: CloudPullResponse, context: ModelContext) throws {
        let existingBooks = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<BookEntity>()).map { ($0.id, $0) })
        for item in pulled.books {
            let remoteUpdated = CloudAPIClient.date(from: item.updatedAt) ?? .distantPast
            if let local = existingBooks[item.id], local.updatedAt >= remoteUpdated {
                continue
            }
            let p = item.payload
            let book: BookEntity
            if let local = existingBooks[item.id] {
                book = local
            } else {
                book = BookEntity(
                    id: p.id,
                    title: p.title,
                    author: p.author,
                    origin: BookOrigin(rawValue: p.originRaw) ?? .local,
                    sourceId: p.sourceId,
                    sourceName: p.sourceName,
                    bookUrl: p.bookUrl,
                    coverUrl: p.coverUrl,
                    intro: p.intro,
                    contentRelativePath: BookFileStore.relativeContentPath(bookId: p.id),
                    lastChapterIndex: p.lastChapterIndex,
                    lastScrollOffset: p.lastScrollOffset,
                    lastReadAt: CloudAPIClient.date(from: p.lastReadAt),
                    addedAt: CloudAPIClient.date(from: p.addedAt) ?? .now,
                    chapterCount: p.chapterCount
                )
                context.insert(book)
            }
            book.title = p.title
            book.author = p.author
            book.originRaw = p.originRaw
            book.sourceId = p.sourceId
            book.sourceName = p.sourceName
            book.bookUrl = p.bookUrl
            book.coverUrl = p.coverUrl
            book.intro = p.intro
            book.lastChapterIndex = p.lastChapterIndex
            book.lastScrollOffset = p.lastScrollOffset
            book.lastReadAt = CloudAPIClient.date(from: p.lastReadAt)
            book.chapterCount = p.chapterCount
            book.cloudR2Key = p.r2Key
            book.updatedAt = remoteUpdated
            if book.contentRelativePath.isEmpty {
                book.contentRelativePath = BookFileStore.relativeContentPath(bookId: book.id)
            }
            if book.isRemote, let remoteChapters = p.chapters, !remoteChapters.isEmpty {
                let existingByIndex = Dictionary(uniqueKeysWithValues: book.chapters.map { ($0.index, $0) })
                for meta in remoteChapters {
                    if let local = existingByIndex[meta.index] {
                        local.title = meta.title
                        local.remoteUrl = meta.remoteUrl
                    } else {
                        let ch = ChapterEntity(
                            index: meta.index,
                            title: meta.title,
                            remoteUrl: meta.remoteUrl,
                            book: book
                        )
                        book.chapters.append(ch)
                        context.insert(ch)
                    }
                }
                book.chapterCount = max(book.chapterCount, remoteChapters.count)
            }

        let booksById = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<BookEntity>()).map { ($0.id, $0) })
        let existingMarks = Dictionary(
            uniqueKeysWithValues: booksById.values.flatMap(\.bookmarks).map { ($0.id, $0) }
        )
        for item in pulled.bookmarks {
            let remoteUpdated = CloudAPIClient.date(from: item.updatedAt) ?? .distantPast
            if let local = existingMarks[item.id], local.updatedAt >= remoteUpdated { continue }
            guard let book = booksById[item.payload.bookId] else { continue }
            let p = item.payload
            if let local = existingMarks[item.id] {
                local.chapterIndex = p.chapterIndex
                local.title = p.title
                local.scrollOffset = p.scrollOffset
                local.updatedAt = remoteUpdated
            } else {
                let mark = BookmarkEntity(
                    id: p.id,
                    chapterIndex: p.chapterIndex,
                    title: p.title,
                    scrollOffset: p.scrollOffset,
                    createdAt: CloudAPIClient.date(from: p.createdAt) ?? .now,
                    book: book
                )
                mark.updatedAt = remoteUpdated
                book.bookmarks.append(mark)
                context.insert(mark)
            }
        }

        let existingSources = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<BookSourceEntity>()).map { ($0.id, $0) })
        for item in pulled.sources {
            let remoteUpdated = CloudAPIClient.date(from: item.updatedAt) ?? .distantPast
            if let local = existingSources[item.id], local.updatedAt >= remoteUpdated { continue }
            let p = item.payload
            if let local = existingSources[item.id] {
                local.name = p.name
                local.sourceUrl = p.sourceUrl
                local.enabled = p.enabled
                local.legadoRaw = p.legadoRaw
                local.groupName = p.groupName
                local.updatedAt = remoteUpdated
            } else {
                let src = BookSourceEntity(
                    id: p.id,
                    name: p.name,
                    sourceUrl: p.sourceUrl,
                    enabled: p.enabled,
                    legadoRaw: p.legadoRaw,
                    groupName: p.groupName,
                    addedAt: CloudAPIClient.date(from: p.addedAt) ?? .now
                )
                src.updatedAt = remoteUpdated
                context.insert(src)
            }
        }

        if let prefsItem = pulled.prefs {
            let remoteUpdated = CloudAPIClient.date(from: prefsItem.updatedAt) ?? .distantPast
            let prefs = ReaderPrefs.shared
            if prefs.updatedAt < remoteUpdated {
                let p = prefsItem.payload
                prefs.applyFromCloud(
                    readMode: ReadMode(rawValue: p.readMode) ?? prefs.readMode,
                    fontSize: p.fontSize,
                    lineHeight: p.lineHeight,
                    themeMode: ReaderThemeMode(rawValue: p.themeMode) ?? prefs.themeMode,
                    autoReadEnabled: p.autoReadEnabled,
                    autoReadSpeed: p.autoReadSpeed,
                    followSystemBrightness: p.followSystemBrightness,
                    brightness: p.brightness,
                    updatedAt: remoteUpdated
                )
            }
        }

        try context.save()
    }

    private func uploadLocalTXTIfNeeded(context: ModelContext) async throws {
        let books = try context.fetch(FetchDescriptor<BookEntity>()).filter { !$0.isRemote }
        for book in books {
            if book.cloudR2Key != nil { continue }
            let url = BookFileStore.contentURL(bookId: book.id)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { continue }
            let res = try await CloudAPIClient.uploadTXT(bookId: book.id, data: data)
            book.cloudR2Key = res.key
            book.updatedAt = CloudAPIClient.date(from: res.updatedAt) ?? .now
        }
        try context.save()
    }

    private func downloadMissingTXT(context: ModelContext, pulled: CloudPullResponse) async throws {
        for item in pulled.books where item.payload.originRaw == BookOrigin.local.rawValue {
            let bookId = item.payload.id
            let url = BookFileStore.contentURL(bookId: bookId)
            if FileManager.default.fileExists(atPath: url.path) { continue }
            guard item.payload.r2Key != nil || CloudConfig.syncLocalTxt else { continue }
            do {
                let data = try await CloudAPIClient.downloadTXT(bookId: bookId)
                try BookFileStore.writeContentData(bookId: bookId, data: data)
                let text = String(data: data, encoding: .utf8) ?? NovelTextDecoder.decode(data)
                let ranges = ChapterSplitter.split(text)
                try BookFileStore.writeChapters(bookId: bookId, text: text, ranges: ranges)
                if let book = try context.fetch(FetchDescriptor<BookEntity>()).first(where: { $0.id == bookId }) {
                    // Rebuild chapter entities if empty
                    if book.chapters.isEmpty {
                        for (i, range) in ranges.enumerated() {
                            let ch = ChapterEntity(
                                index: i,
                                title: range.title,
                                startOffset: range.start,
                                length: range.length,
                                book: book
                            )
                            book.chapters.append(ch)
                            context.insert(ch)
                        }
                        book.chapterCount = ranges.count
                    }
                    book.cloudR2Key = item.payload.r2Key
                    book.updatedAt = CloudAPIClient.date(from: item.updatedAt) ?? book.updatedAt
                }
            } catch {
                // Keep going for other books
                continue
            }
        }
        try context.save()
    }
}
