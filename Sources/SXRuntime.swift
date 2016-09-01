
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

private struct __KqueueInternalInfo {
    var __pointer: UnsafeMutableRawPointer
    var __exec: () -> ()
    init<T: __KqueueInternalRoute>(_ x: inout T) {
        self.__pointer = UnsafeMutableRawPointer(&x)
        self.__exec = x.runloopMain
    }
    
    init<T: __KqueueInternalRoute>(_ x: UnsafeMutablePointer<T>) {
        self.__pointer = UnsafeMutableRawPointer(x)
        self.__exec = x.pointee.runloopMain
    }
}


typealias _kevent = kevent
class UnixEventManager {
    var queue: Int32 = kqueue()
    var changelist = [_kevent]()
    var events = [_kevent](repeating: _kevent(), count: 1024)
    var event_max = 1024
    
    static var `default` = UnixEventManager()
    
    private var routeingTable = [Int32: __KqueueInternalInfo]()
    
    func register<T: __KqueueInternalRoute>(_ item: inout T) {
        let item_ptr = UnsafeMutableRawPointer(&item)
        self.pendings.append {
            var event = _kevent()
            event.ident = UInt(item_ptr.assumingMemoryBound(to: T.self).pointee.ident)
            event.filter = Int16(EVFILT_READ)
            event.flags = UInt16(Int(EV_ADD) | Int(EV_ENABLE))
            event.data = 0
            event.udata = item_ptr
            self.changelist.append(event)
            self.routeingTable[item_ptr.assumingMemoryBound(to: T.self).pointee.ident] = __KqueueInternalInfo(item_ptr.assumingMemoryBound(to: T.self))
        }
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
//    
//    func resume(_ item: inout __KqueueInternalRoute) {
//        var event = _kevent()
//        event.ident = UInt(item.ident)
//        event.filter = Int16(EVFILT_READ)
//        event.flags = UInt16(Int(EV_ENABLE))
//        event.data = 0
//        event.udata = UnsafeMutableRawPointer(&item)
//        changelist.append(event)
//    }
    
    var pendings = [() -> ()]()

    init() {
        SXThreadPool.default.execute {
            while (true) {
                
                for pending in self.pendings {
                    pending()
                }
                
                let n = kevent(self.queue,
                               &self.changelist,
                               Int32(self.changelist.count),
                               &self.events, Int32(self.event_max), nil)

                self.pendings.removeAll(keepingCapacity: true)
                
                for i in 0 ..< Int(n) {
                    let event = self.events[i]
                    let info = self.routeingTable[Int32(event.ident)]
                    info?.__exec()
                }
                
            }
        }
    }
}

public protocol SXRuntimeObject {
    
    var status: SXStatus { get }

    func statusDidChange(status: SXStatus)
    
    func close()
}

