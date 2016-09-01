
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

protocol __KqueueInternalRoute {
    var ident: Int32 { get set }
    func runloopMain()
}

#if os(OSX) || os(FreeBSD) || os(iOS) || os(watchOS) || os(tvOS)

private struct __KqueueInternalInfo {
    var __pointer: UnsafeMutableRawPointer
    var __exec: () -> ()
    var bytes: Int
    var alignment: Int
    init<T: __KqueueInternalRoute>(_ x: inout T) {
        self.__pointer = UnsafeMutableRawPointer(&x)
        self.__exec = x.runloopMain
        self.bytes = MemoryLayout<T>.size
        self.alignment = MemoryLayout<T>.alignment
    }
    
    init<T: __KqueueInternalRoute>(_ x: UnsafeMutablePointer<T>) {
        self.__pointer = UnsafeMutableRawPointer(x)
        self.__exec = x.pointee.runloopMain
        self.bytes = MemoryLayout<T>.size
        self.alignment = MemoryLayout<T>.alignment
    }
}


typealias _kevent = kevent
class UnixEventManager {
    var queue: Int32 = kqueue()
    var changelist = [_kevent]()
    var events = [_kevent]()
    var event_max = 1024
    
    static var `default` = UnixEventManager()
    private var eva = 0
    
    private var routeingTable = [Int32: __KqueueInternalInfo]()
    
    func register<T: __KqueueInternalRoute>(_ item: inout T) throws {
        let item_ptr = UnsafeMutableRawPointer(UnsafeMutableRawPointer.allocate(bytes: MemoryLayout<T>.size,
                                                        alignedTo: MemoryLayout<T>.alignment).initializeMemory(as: T.self, to: item))
        
        guard self.routeingTable[item.ident] == nil else {
            throw SXError.duplicatedIdentInRoutingTable
        }
        
        self.pendings.append ({
            
            var event = _kevent()
            print(item_ptr)
            event.ident = UInt(item_ptr.assumingMemoryBound(to: T.self).pointee.ident)
            event.filter = Int16(EVFILT_READ)
            event.flags = UInt16(Int(EV_ADD) | Int(EV_ENABLE))
            event.data = 0
            event.udata = item_ptr
            self.changelist.append(event)
            self.routeingTable[item_ptr.assumingMemoryBound(to: T.self).pointee.ident] = __KqueueInternalInfo(item_ptr.assumingMemoryBound(to: T.self))
        })
    }
    
    func ignore<T: __KqueueInternalRoute>(_ item: inout T) {
        let item_ptr = UnsafeMutableRawPointer(&item)
        self.pendings.append {
            var event = _kevent()
            event.ident = UInt(item_ptr.assumingMemoryBound(to: T.self).pointee.ident)
            event.filter = Int16(EVFILT_READ)
            event.flags = UInt16(Int(EV_DISABLE))
            event.data = 0
            event.udata = item_ptr
            self.changelist.append(event)
        }
    }
    
    func unregister(_ ident: Int32) {
        if let info = self.routeingTable[ident] {
            info.__pointer.deallocate(bytes: info.bytes, alignedTo: info.alignment)
            self.pendings.append {
                var event = _kevent()
                event.ident = UInt(ident)
                event.filter = Int16(EVFILT_READ)
                event.flags = UInt16(Int(EV_DELETE | EV_DISABLE))
                event.data = 0
                event.udata = nil
                self.changelist.append(event)
                self.routeingTable[ident] = nil
            }
        }
    }
    
    var pendings = [() -> ()]()

    init() {
        self.events.reserveCapacity(1024)
        SXThreadingProxyDefault.execute {
            while (true) {
                print("KEVENT INIT")
                
                print(self.pendings)
                
//                for pending in self.pendings {
//                    pending()
//                }
//
//                print(self.changelist.count)
//                print(self.events.count)
//                
                while !self.pendings.isEmpty {
                    self.pendings.removeFirst()()
                }
                
                if self.changelist.count == 0 && self.events.count == 0 {
                    sleep(1)
                    continue
                }
//
                var timeout = timespec(tv_sec: 10, tv_nsec: 0)
                
                let n = kevent(self.queue,
                               &self.changelist,
                               Int32(self.changelist.count),
                               &self.events, Int32(self.event_max), nil)
                
                
                print("kevent")
                
                for event in self.events {
                    self.routeingTable[Int32(event.ident)]?.__exec()
                }
            }
        }
    }
}

#endif


public protocol SXRuntimeObject {
    
    var status: SXStatus { get }

    func statusDidChange(status: SXStatus)
    
    func close()
}

