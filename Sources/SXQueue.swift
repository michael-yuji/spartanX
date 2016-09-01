
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
//  Created by yuuji on 6/2/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

import Foundation

public struct SXQueue: __KqueueInternalRoute {
    
    public var fd_r: Readable
    public var fd_w: Writable
    
    public var ident: Int32
    
    internal var status: SXStatus = .idle
    public var service: SXService
    
    public var currentStatus: SXStatus {
        return self.status
    }
    
    init(fd: Int32, readFrom r: Readable, writeTo w: Writable, with SXServer: SXService) {
        self.ident = fd
        self.fd_r = r
        self.fd_w = w
        self.service = SXServer
        
        UnixEventManager.default.register(&self)
    }
    
    public mutating func suspend() {
        self.status = .suspended
    }
    
    public mutating func resume() {
        
        if self.status != .suspended {
            return
        }
        
        self.status = .resumming
    }
    
    public mutating func start() {
        self.status = .running
        runloopMain()
    }
    
    public func terminate() {
        self.fd_r.done()
        self.fd_w.done()
    }
    
    public mutating func rebind(to service: SXService) {
        self.service = service
    }
    
    func runloopMain() {
        do {
            if let data = try self.fd_r.read() {
                if !self.service.dataHandler(self, data) {
                    return terminate()
                }
            }
            
        } catch {
            self.service.errHandler?(self, error)
        }

        return self.runloopMain()
    }
}
