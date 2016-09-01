
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
//  Created by Yuji on 6/4/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

import Foundation
import CKit

public extension Addressable where Self : SocketType {
    public func bind() throws {
        var err: Int32 = 0
        
        var yes = true
        
        if setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, UInt32(MemoryLayout<Int32>.size)) == -1 {
            throw SXSocketError.setSockOpt(String.errno)
        }
        
        guard let address = address else {
            throw SXSocketError.bind("address is nil")
        }
        
        switch address {
        case var .inet(addr):
            err = Foundation.bind(sockfd, pointer(of: &addr).cast(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_in>.size))
            
        case var .inet6(addr):
            err = Foundation.bind(sockfd, pointer(of: &addr).cast(to : sockaddr.self), socklen_t(MemoryLayout<sockaddr_in6>.size))
            
        case var .unix(addr):
            err = Foundation.bind(sockfd, pointer(of: &addr).cast(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_un>.size))
        }
        
        if err == -1 {
            throw SXSocketError.bind(String.errno)
        }
    }
}

public extension SXServerSocket {
    public func listen() throws {
        if Foundation.listen(sockfd, Int32(self.backlog)) < 0 {
            throw SXSocketError.listen(String.errno)
        }
    }
    
    public func accept() throws -> ClientSocket {
        return try self._accept(self)
    }
    
    public func start(on thread: SXThreadingProxy) {
        var thread = thread
        thread.execute {
            while self.proceed {
                do {
                    try self.listenloop()
                    let client = try self.accept()
                    client.route(to: self.service, using: SXThreadingProxyDefault)
                } catch {
                    print(error)
                }
            }
        }
    }
    
    public mutating func done() {
        self.proceed = false
        close(self.sockfd)
    }
    
    private func listenloop() throws {
        try self.listen()
    }
}

public extension SXServerSocket {
    public static func `default`(service: SXService,
                                 conf: SXRouteConf,
                                 tls: SXTLSContextInfo?,
                                 clientConf: SXClientIOConf)
        
        throws -> SXServerSocket {
            
            let read = { (client: SXClientSocket) throws -> Data? in
                let size = client.readBufsize
                if let tlsc = client.tlsContext {
                    return try? tlsc.read(size: size)
                } else {
                    
                    var buffer = [UInt8](repeating: 0, count: size)
                    let flags = client.readFlags
                    
        
                    let len = recv(client.sockfd, &buffer, size, flags)
                    
                    if len == -1 {
                        return nil
                    }
                    
                    if len == 0 {
                        return nil
                    }
                    return Data(bytes: buffer, count: len)
                }
            }
            
            let write = { (client: SXClientSocket, data: Data) throws -> () in
                if let tlsc = client.tlsContext {
                    _ = try tlsc.write(data: data)
                } else {
                    if Foundation.send(client.sockfd, data.bytesCopied, data.length, client.writeFlags) == -1 {
                        throw SXSocketError.send("send: \(String.errno)")
                    }
                }
            }
            
            let clean: (_ client: SXClientSocket) -> () = {
                (client: SXClientSocket) in
                client.tlsContext?.close()
            }
            
            let fns = ClientFunctions(read: read, write: write, clean: clean)
            
            let accept: @escaping (SXServerSocket) throws -> SXClientSocket = {
                (server: SXServerSocket) throws -> SXClientSocket in
                
                var addr = sockaddr()
                var socklen = socklen_t()
                let fd = Foundation.accept(server.sockfd, &addr, &socklen)
                getpeername(fd, &addr, &socklen)
                
                let context = try server.tlsContext?.accept(socket: fd)
                
                return try! SXClientSocket(fd: fd,
                                           tls: context,
                                           addrinfo: (addr: addr, len: socklen),
                                           sockinfo: (type: conf.type, protocol: conf.`protocol`),
                                           rwconfig: server.clientConf as! SXClientIOConf,
                                           functions: fns)
            }
            
            return try SXServerSocket(service: service,
                                      conf: conf,
                                      tls: tls,
                                      clientConf: clientConf,
                                      accept: accept)
    }
}

public extension SXClientSocket {
    public func write(data: Data) throws {
        try self._write(self, data)
    }
    
    public func read() throws -> Data? {
        return try self._read(self)
    }
    
    public func done() {
        self._clean?(self)
        close(self.sockfd)
        print("Connection Done")
    }
}

public extension ClientSocket {
    public func route(to service: SXService, using thread: SXThreadingProxy) {
        if var queue = try? SXQueue(fd: self.sockfd, readFrom: self, writeTo: self, with: service) {
            var thread = thread
            thread.execute {
                queue.start()
            }
        }
    }
}
