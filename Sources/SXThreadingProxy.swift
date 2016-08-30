//
//  SXThreadingProxy.swift
//  spartanX
//
//  Created by yuuji on 7/8/16.
//
//

import Foundation
import Dispatch
import CKit

#if os(Linux) || os(FreeBSD)
public typealias DispatchQueue = dispatch_queue_t
    
extension DispatchQueue {
    public func async(execute block: () -> Void) {
        dispatch_async(self, block)
    }
    
    public static func global(_ qos: dispatch_queue_priority_t = DISPATCH_QUEUE_PRIORITY_DEFAULT) -> DispatchQueue {
        return dispatch_get_global_queue(qos, 0)
    }
}
#endif

public protocol SXThreadingProxy {
    mutating func execute(block: @escaping () -> Void)
}

public struct GrandCentralDispatchQueue : SXThreadingProxy {

    public var queue: DispatchQueue
    
    public init(_ queue: DispatchQueue) {
        self.queue = queue
    }
    
    public func execute(block: @escaping () -> Void) {
        queue.async(execute: block)
    }
}

public class SXThreadPool : SXThreadingProxy {
    public var numberOfThreads: Int
    var threads: [SXThread]
    
    public static let `default` = SXThreadPool(nthreads: 550)
    
    public func execute(block: @escaping ()->Void) {
        threads.sorted{ $0.queue.count < $1.queue.count }.first!.execute(block: block)
    }
    
    public init(nthreads: Int) {
        numberOfThreads = nthreads
        threads = [SXThread](count: nthreads) { _ in SXThread() }
    }
}

public class SXThread {
    
    class BlockQueue {
        
        var count: Int = 0
        var mutex: pthread_mutex_t = pthread_mutex_t()
        var blocks = [() -> Void]()
        
        var mutexPointer: UnsafeMutablePointer<pthread_mutex_t> {
            return mutablePointer(of: &mutex)
        }
        
        init() {
            pthread_mutex_init(&mutex, nil)
        }
    }
    
    #if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
    var thread: pthread_t?
    #elseif os(Linux) || os(FreeBSD)
    var thread: pthread_t = pthread_t()
    #endif
    
    var queue = BlockQueue()
    
    public func execute(block: @escaping () -> Void) {
        pthread_mutex_lock(queue.mutexPointer)
        queue.blocks.append(block)
        queue.count += 1
        if queue.blocks.count == 1 {
            #if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
            pthread_kill(thread!, SIGUSR1)
            #else
            pthread_kill(thread, SIGUSR1)
            #endif
        }
        pthread_mutex_unlock(queue.mutexPointer)
    }
    
    public init() {
        
        #if os(Linux)
        var blk_sigs = sigset_t()
        sigemptyset(&blk_sigs)
        sigaddset(&blk_sigs, SIGUSR1)
        pthread_sigmask(SIG_BLOCK, &blk_sigs, nil)
        #endif
        
        pthread_create(&thread, nil, { (pointer) -> UnsafeMutableRawPointer? in
            
            #if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
            let blockQueue = pointer.cast(to: BlockQueue.self).pointee
            #else
            let blockQueue = pointer!.cast(to: BlockQueue.self).pointee
            #endif
            
            var signals = sigset_t()
            var caught: Int32 = 0
            sigemptyset(&signals)
            sigaddset(&signals, SIGUSR1)
            
            while true {
                while blockQueue.count > 0 {
                    blockQueue.blocks.first!()
                    pthread_mutex_lock(blockQueue.mutexPointer)
                    _ = blockQueue.blocks.removeFirst()
                    blockQueue.count -= 1
                    pthread_mutex_unlock(blockQueue.mutexPointer)
                }
            sigwait(&signals, &caught)
            }
            
        }, UnsafeMutableRawPointer(mutablePointer(of: &self.queue)))
    }
}
