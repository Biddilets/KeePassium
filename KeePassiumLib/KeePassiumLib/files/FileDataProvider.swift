//  KeePassium Password Manager
//  Copyright © 2022 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public final class FileDataProvider: Synchronizable {
    public static let defaultTimeout = URLReference.defaultTimeout
    
    public typealias FileOperationResult<T> = Result<T, FileAccessError>
    public typealias FileOperationCompletion<T> = (FileOperationResult<T>) -> Void
    
    fileprivate static let backgroundQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "FileDataProvider"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 8
        return queue
    }()
    
    fileprivate static let coordinatorWaitingQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "FileCoordinatorQueue"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 8
        return queue
    }()
}

extension FileDataProvider {
    
    public static func bookmarkFile(
        at fileURL: URL,
        location: URLReference.Location,
        completionQueue: OperationQueue,
        completion: @escaping FileOperationCompletion<URLReference>
    ) {
        let isAccessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        let operationQueue = FileDataProvider.backgroundQueue
        coordinateFileOperation(
            intent: .readingIntent(with: fileURL, options: [.withoutChanges]),
            fileProvider: nil, 
            byTime: .now() + FileDataProvider.defaultTimeout,
            queue: operationQueue,
            fileOperation: { url in
                assert(operationQueue.isCurrent)
                do {
                    let fileRef = try URLReference(from: url, location: location)
                    completionQueue.addOperation {
                        completion(.success(fileRef))
                    }
                } catch {
                    Diag.error("Failed to create file reference [message: \(error.localizedDescription)]")
                    let fileAccessError = FileAccessError.systemError(error)
                    completionQueue.addOperation {
                        completion(.failure(fileAccessError))
                    }
                }
            },
            completionQueue: completionQueue,
            completion: completion
        )
    }
    
    public static func readFileInfo(
        at fileURL: URL,
        fileProvider: FileProvider?,
        canUseCache: Bool,
        byTime: DispatchTime = .now() + FileDataProvider.defaultTimeout,
        completionQueue: OperationQueue? = nil,
        completion: @escaping FileOperationCompletion<FileInfo>
    ) {
        let operationQueue = FileDataProvider.backgroundQueue
        let completionQueue = completionQueue ?? FileDataProvider.backgroundQueue
        let isAccessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        coordinateFileOperation(
            intent: .readingIntent(with: fileURL, options: [.resolvesSymbolicLink, .withoutChanges]),
            fileProvider: fileProvider,
            byTime: byTime,
            queue: operationQueue,
            fileOperation: { url in
                assert(operationQueue.isCurrent)
                if let inputStream = InputStream(url: url) {
                    defer {
                        inputStream.close()
                    }
                    var dummyBuffer = [UInt8](repeating: 0, count: 8)
                    inputStream.read(&dummyBuffer, maxLength: dummyBuffer.count)
                } else {
                    Diag.warning("Failed to fetch the file")
                }
                
                url.readFileInfo(
                    canUseCache: canUseCache,
                    completionQueue: completionQueue,
                    completion: completion
                )
            },
            completionQueue: completionQueue,
            completion: completion
        )
    }
    
    public static func read(
        _ fileRef: URLReference,
        queue: OperationQueue? = nil,
        byTime: DispatchTime = .now() + FileDataProvider.defaultTimeout,
        completionQueue: OperationQueue? = nil,
        completion: @escaping FileOperationCompletion<ByteArray>
    ) {
        let operationQueue = queue ?? FileDataProvider.backgroundQueue
        let completionQueue = completionQueue ?? FileDataProvider.backgroundQueue
        fileRef.resolveAsync(byTime: byTime, callbackQueue: operationQueue) {
            assert(operationQueue.isCurrent)
            switch $0 {
            case .success(let fileURL):
                read(
                    fileURL,
                    fileProvider: fileRef.fileProvider,
                    queue: operationQueue,
                    byTime: byTime,
                    completionQueue: completionQueue,
                    completion: completion
                )
            case .failure(let fileAccessError):
                Diag.error("Failed to resolve file reference [message: \(fileAccessError.localizedDescription)]")
                completionQueue.addOperation {
                    completion(.failure(fileAccessError))
                }
            }
        }
    }
    
    public static func read(
        _ fileURL: URL,
        fileProvider: FileProvider?,
        queue: OperationQueue? = nil,
        byTime: DispatchTime = .now() + FileDataProvider.defaultTimeout,
        completionQueue: OperationQueue? = nil,
        completion: @escaping FileOperationCompletion<ByteArray>
    ) {
        let operationQueue = queue ?? FileDataProvider.backgroundQueue
        let completionQueue = completionQueue ?? FileDataProvider.backgroundQueue
        let isAccessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        coordinateFileOperation(
            intent: .readingIntent(with: fileURL, options: [.forUploading]),
            fileProvider: fileProvider,
            byTime: byTime,
            queue: operationQueue,
            fileOperation: { (url) in
                assert(operationQueue.isCurrent)
                do {
                    let fileData = try ByteArray(contentsOf: url, options: [.uncached, .mappedIfSafe])
                    completionQueue.addOperation {
                        completion(.success(fileData))
                    }
                } catch {
                    Diag.error("Failed to read file [message: \(error.localizedDescription)]")
                    let fileAccessError = FileAccessError.systemError(error)
                    completionQueue.addOperation {
                        completion(.failure(fileAccessError))
                    }
                }
            },
            completionQueue: completionQueue,
            completion: completion
        )
    }
    
    public static func write(
        _ data: ByteArray,
        to fileURL: URL,
        fileProvider: FileProvider?,
        queue: OperationQueue? = nil,
        byTime: DispatchTime = .now() + FileDataProvider.defaultTimeout,
        completionQueue: OperationQueue? = nil,
        completion: @escaping (Result<Void, FileAccessError>) -> Void
    ) {
        let operationQueue = queue ?? FileDataProvider.backgroundQueue
        let completionQueue = completionQueue ?? FileDataProvider.backgroundQueue
        let isAccessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        coordinateFileOperation(
            intent: .writingIntent(with: fileURL, options: [.forMerging]),
            fileProvider: fileProvider,
            byTime: byTime,
            queue: operationQueue,
            fileOperation: { url in
                assert(operationQueue.isCurrent)
                do {
                    try data.write(to: url, options: [])
                    completionQueue.addOperation {
                        completion(.success)
                    }
                } catch {
                    Diag.error("Failed to write file [message: \(error.localizedDescription)")
                    let fileAccessError = FileAccessError.systemError(error)
                    completionQueue.addOperation {
                        completion(.failure(fileAccessError))
                    }
                }
            },
            completionQueue: completionQueue,
            completion: completion
        )
    }
    
    public static func readThenWrite(
        to fileURL: URL,
        fileProvider: FileProvider?,
        queue: OperationQueue? = nil,
        dataSource: @escaping (_ remoteURL: URL, _ remoteData: ByteArray) throws -> ByteArray?,
        byTime: DispatchTime = .now() + FileDataProvider.defaultTimeout,
        completionQueue: OperationQueue? = nil,
        completion: @escaping (Result<Void, FileAccessError>) -> Void
    ) {
        let operationQueue = queue ?? FileDataProvider.backgroundQueue
        let completionQueue = completionQueue ?? FileDataProvider.backgroundQueue
        let isAccessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        coordinateReadThenWriteOperation(
            fileURL: fileURL,
            fileProvider: fileProvider,
            byTime: byTime,
            queue: operationQueue,
            fileOperation: { readURL, writeURL in
                assert(operationQueue.isCurrent)
                if let inputStream = InputStream(url: readURL) {
                    defer {
                        inputStream.close()
                    }
                    var dummyBuffer = [UInt8](repeating: 0, count: 8)
                    inputStream.read(&dummyBuffer, maxLength: dummyBuffer.count)
                } else {
                    Diag.warning("Failed to fetch the file")
                }
                

                do {
                    let fileData = try ByteArray(contentsOf: readURL, options: [.uncached, .mappedIfSafe])
                    if let dataToWrite = try dataSource(readURL, fileData) { 
                        try dataToWrite.write(to: writeURL, options: [])
                    }
                    completionQueue.addOperation {
                        completion(.success)
                    }
                } catch let fileAccessError as FileAccessError {
                    Diag.error("Failed to write file [message: \(fileAccessError.localizedDescription)")
                    completionQueue.addOperation {
                        completion(.failure(fileAccessError))
                    }
                } catch {
                    Diag.error("Failed to write file [message: \(error.localizedDescription)")
                    let fileAccessError = FileAccessError.systemError(error)
                    completionQueue.addOperation {
                        completion(.failure(fileAccessError))
                    }
                }
            },
            completionQueue: completionQueue,
            completion: completion
        )
    }
}


extension FileDataProvider {
    private static func coordinateFileOperation<T>(
        intent: NSFileAccessIntent,
        fileProvider: FileProvider?,
        byTime: DispatchTime,
        queue: OperationQueue,
        fileOperation: @escaping (URL) -> Void,
        completionQueue: OperationQueue,
        completion: @escaping FileOperationCompletion<T>
    ) {
        coordinatorWaitingQueue.addOperation {
            let semaphore = DispatchSemaphore(value: 0)
            
            let fileCoordinator = NSFileCoordinator()
            fileCoordinator.coordinate(with: [intent], queue: queue) {
                (coordinatorError) in
                assert(queue.isCurrent)
                guard semaphore.signal() != 0 else { 
                    return
                }
                
                if let coordinatorError = coordinatorError {
                    completionQueue.addOperation {
                        completion(.failure(.systemError(coordinatorError)))
                    }
                    return
                }
                
                fileOperation(intent.url)
            }
            
            if semaphore.wait(timeout: byTime) == .timedOut {
                fileCoordinator.cancel()
                completionQueue.addOperation {
                    completion(.failure(.timeout(fileProvider: fileProvider)))
                }
                return
            }
        }
    }
    
    private static func coordinateReadThenWriteOperation<T>(
        fileURL: URL,
        fileProvider: FileProvider?,
        byTime: DispatchTime,
        queue: OperationQueue,
        fileOperation: @escaping (URL, URL) -> Void,
        completionQueue: OperationQueue,
        completion: @escaping FileOperationCompletion<T>
    ) {
        coordinatorWaitingQueue.addOperation {
            let semaphore = DispatchSemaphore(value: 0)
            
            let fileCoordinator = NSFileCoordinator()
            let readingIntent = NSFileAccessIntent.readingIntent(with: fileURL, options: [])
            let writingIntent = NSFileAccessIntent.writingIntent(with: fileURL, options: [.forMerging])
            fileCoordinator.coordinate(with: [readingIntent, writingIntent], queue: queue) {
                (coordinatorError) in
                assert(queue.isCurrent)
                guard semaphore.signal() != 0 else { 
                    return
                }
                
                if let coordinatorError = coordinatorError {
                    completionQueue.addOperation {
                        completion(.failure(.systemError(coordinatorError)))
                    }
                    return
                }
                
                fileOperation(readingIntent.url, writingIntent.url)
            }
            
            if semaphore.wait(timeout: byTime) == .timedOut {
                fileCoordinator.cancel()
                completionQueue.addOperation {
                    completion(.failure(.timeout(fileProvider: fileProvider)))
                }
                return
            }
        }
    }
}