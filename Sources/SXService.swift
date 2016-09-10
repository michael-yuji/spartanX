
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
//  Created by yuuji on 9/5/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

import Foundation
import swiftTLS

public class SXServerSocket : ServerSocket, KqueueManagable {
    
    public var address: SXSocketAddress?
    public var port: in_port_t?
    
    public var tlsContext: TLSServer?
    
    public var clientConf: ClientIOConf
    
    public var sockfd: Int32
    public var domain: SXSocketDomains
    public var type: SXSocketTypes
    public var `protocol`: Int32
    
    public var service: SXService
    
    internal var proceed: Bool = true
    
    public var ident: Int32 {
        get {
            return sockfd
        } set {
            sockfd = newValue
        }
    }
    
    public var backlog: Int
    
    internal var _accept: (_ from: SXServerSocket) throws -> ClientSocket
    
    public init(service: SXService,
                conf: SXRouteConf,
                tls: SXTLSContextInfo?,
                clientConf: ClientIOConf,
                accept: @escaping (_ from: SXServerSocket) throws -> ClientSocket) throws {
        
        self.service = service
        
        self.address = conf.address
        self.port = conf.port
        self.type = conf.type
        self.clientConf = clientConf
        self.`protocol` = conf.`protocol`
        self.domain = conf.domain
        self.backlog = conf.backlog
        
        self._accept = accept
        
        self.sockfd = socket(Int32(domain.rawValue), type.rawValue, `protocol`)
        
        if sockfd == -1 {
            throw SXSocketError.socket(String.errno)
        }
        
        if self.type == .stream {
            try self.bind()
        }
        
        if let tls = tls {
            self.tlsContext = try TLSServer(cert: tls.certificate.path,
                                            cert_passwd: tls.certificate.passwd,
                                            key: tls.privateKey.path,
                                            key_passwd: tls.privateKey.passwd)
        }
        
        try self.listen()
        SpartanXManager.default?.register(for: self)
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
    
    public func runloop(kdata: Int, udata: UnsafeRawPointer!) {
        do {
            
            let client = try self.accept()
            _ = try SXQueue(fd: client.sockfd, readFrom: client, writeTo: client, with: self.service)
            
        } catch {
            print(error)
        }
    }
    
    public func done() {
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
                    
                    if len == 0 {
                        return nil
                    }
                    
                    if len == -1 {
                        throw SXSocketError.recv(String.errno)
                    }
                    
                    return Data(bytes: buffer, count: len)
                }
            }
            
            let write = { (client: SXClientSocket, data: Data) throws -> () in
                
                if let tlsc = client.tlsContext {
                    _ = try tlsc.write(data: data)
                } else {
                    if send(client.sockfd, (data as NSData).bytes, data.length, 0) == -1 {
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
