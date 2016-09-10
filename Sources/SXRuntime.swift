
//  Copyright (c) 2016, Yuji
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
//  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  The views and conclusions contained in the software and documentation are those
//  of the authors and should not be interpreted as representing official policies,
//  either expressed or implied, of the FreeBSD Project.
//
//  Created by Yuji on 6/3/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

import Foundation
import CKit

public enum SXStatus {
    case idle
    case running
    case resumming
    case suspended
    case shouldTerminate
}

public protocol KqueueManagable {
    var ident: Int32 { get set }
    func runloop(kdata: Int, udata: UnsafeRawPointer!)
}

public extension Array {
    subscript(_ i: Int32) -> Element {
        return self[Int(i)]
    }
}

internal struct __sxqueue_wrap {
    var q: KqueueManagable
    init(_ q: KqueueManagable) { self.q = q }
}

#if os(OSX) || os(FreeBSD) || os(iOS) || os(watchOS) || os(tvOS)
    typealias _kevent = Foundation.kevent
    
    public struct SpartanXManager {
        public static var `default`: SpartanXManager?
        var kernels = [SXKernel]()
        var map = [Int32 : SXKernel]()
    }
    
    public extension SpartanXManager {
        
        public static func initializeDefault() {
            `default` = SpartanXManager(maxCPU: 3, evs_cpu: 5120)
        }
        
        internal mutating func register(service: SXService, queue: SXQueue) {
            let queue = __sxqueue_wrap(queue)
            register(queue: queue)
        }
        
        internal mutating func register(for socket: SXServerSocket) {
            let queue = __sxqueue_wrap(socket)
            register(queue: queue)
        }
        
        @inline(__always)
        internal mutating func register(queue: __sxqueue_wrap) {
            let _leastBusyKernel = leastBusyKernel()
            map[queue.q.ident] = _leastBusyKernel
            _leastBusyKernel?.register(queue: queue)
        }
        
        internal mutating func unregister(for ident: Int32) {
            let kernel = map[ident]
            kernel?.remove(ident: ident)
            map[ident] = nil
        }
        
        @inline(__always)
        func leastBusyKernel() -> SXKernel? {
            return kernels.sorted {
                $0.queues.count < $1.queues.count
                }.first
        }
    }
    
    public extension SpartanXManager {
        init(maxCPU: Int, evs_cpu: Int) {
            self.kernels = [SXKernel](count: maxCPU) {_ in
                return SXKernel(events_count: evs_cpu)
            }
        }
    }
    
    public class SXKernel {
        
        public var thread: SXThread
        var mutex: pthread_mutex_t
        var kq: Int32
        
        // change list and eventlist
        var events: [_kevent]
        var changes: [_kevent]
        
        // user queues
        var queues: [Int32: KqueueManagable]
        
        // events count
        var count = 0
        
        // active events count
        var actived = false
        
        init(events_count: Int) {
            thread = SXThread()
            mutex = pthread_mutex_t()
            kq = kqueue()
            self.queues = [:]
            self.events = [_kevent](repeating: _kevent(), count: events_count)
            self.changes = [_kevent]()
            
            pthread_mutex_init(&mutex, nil)
        }
        
    }
    
    
    // Kevent
    extension SXKernel {
        
        func activate() {
            self.withMutex{
                actived = true
            }
            
            self.thread.execute {
                
                kqueue_loop: while true {
                    
                    if (self.withMutex { () -> Bool in
                        
                        if self.changes.count != 0 {
                            
                            kevent(self.kq, self.changes, Int32(self.changes.count), nil, 0, nil)
                            self.changes.removeAll(keepingCapacity: true)
                        }
                        
                        if self.count == 0 {
                            return true
                        }
                        return false
                        }) {
            
                        break kqueue_loop
                    }
                    
                    
                    
                    let nev = kevent(self.kq, nil, 0, &self.events, Int32(self.events.count), nil)
                    
                    
                    switch nev {
                    case 0:
                        break kqueue_loop
                    case 1..<Int32.max:
                        continue kqueue_loop
                    default:
                        break
                    }

                    for i in 0..<Int(nev) {
                        let event = self.events[Int(i)]
                        
                        let queue = self.queues[Int32(event.ident)]
                        queue?.runloop(kdata: event.data, udata: event.udata)
                    }

                }
                
                self.withMutex {
                    self.actived = false
                }
            }
        }
        
        func register(queue: __sxqueue_wrap) {
            withMutex {
                self.queues[queue.q.ident] = queue.q
                
                let k = _kevent(ident: UInt(queue.q.ident),
                                filter: Int16(EVFILT_READ),
                                flags: UInt16(EV_ADD | EV_ENABLE | EV_RECEIPT),
                                fflags: 0, data: 0,
                                udata: nil)
                count += 1
                
                changes.append(k);
            }
            
            if !actived {
                
                activate()
            }
        }
        
        func remove(ident: Int32) {
            withMutex {
                self.queues[ident] = nil
                let k = _kevent(ident: UInt(ident),
                                filter: Int16(EVFILT_READ),
                                flags: UInt16(EV_DELETE | EV_DISABLE | EV_RECEIPT),
                                fflags: 0,
                                data: 0,
                                udata: nil)
                count -= 1
                
                changes.append(k)
            }
        }
    }
    
    // Helper
    extension SXKernel {
        func withMutex<Result>(_ execute: () -> Result) -> Result {
            pthread_mutex_lock(&mutex)
            let r = execute()
            pthread_mutex_unlock(&mutex)
            return r
        }
    }
#endif
