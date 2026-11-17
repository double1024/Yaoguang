import Foundation
import SwiftData

/// 应用本地存储目录与 ModelContainer 的创建。
enum StoreLocation {
    struct Directories {
        let root: URL
        let database: URL
        let backups: URL
        let cache: URL
        let config: URL
    }

    /// 在 `~/Library/Application Support/Yaoguang/` 下建立目录结构。
    /// 沙盒应用会自动映射到容器内的 Application Support，仍以 .applicationSupportDirectory 为准。
    static func makeDirectories() throws -> Directories {
        let fm = FileManager.default
        let root = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
            .appendingPathComponent("Yaoguang", isDirectory: true)
        let database = root.appendingPathComponent("Database", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        let cache = root.appendingPathComponent("Cache", isDirectory: true)
        let config = root.appendingPathComponent("Config", isDirectory: true)
        for dir in [root, database, backups, cache, config] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return Directories(root: root, database: database, backups: backups, cache: cache, config: config)
    }

    /// 创建挂载到 Database/Yaoguang.store 的 ModelContainer。
    /// Schema 升级后旧库不兼容时不做迁移，直接重建新库（历史数据由用户手动删除）。
    static func makeModelContainer() throws -> ModelContainer {
        let dirs = try makeDirectories()
        let schema = Schema(versionedSchema: YaoguangSchemaV1.self)
        let url = dirs.database.appendingPathComponent("Yaoguang.store")
        let configuration = ModelConfiguration("Yaoguang", schema: schema, url: url)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // 旧库与新 Schema 不兼容：移除 store 与 WAL/SHM 后重建。
            let fm = FileManager.default
            for suffix in ["", "-wal", "-shm"] {
                let file = URL(fileURLWithPath: url.path + suffix)
                try? fm.removeItem(at: file)
            }
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
}
