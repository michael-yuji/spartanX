
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
import swiftTLS

public protocol Readable {
    var readBufsize: size_t { get set }
    var readFlags: Int32 { get set }
    var read: (Self) throws -> Data? { get set }
}

public protocol Writable {
    var writeFlags: Int32 { get set }
    var write: (Self, _ data: Data) throws -> () { get set }
}

public protocol SocketType {
    func clean()
    var cleaner: Cleaner { get }
    var sockfd: Int32 { get set }
    var domain: SXSocketDomains { get set }
    var type: SXSocketTypes { get set }
    var `protocol`: Int32 { get set }
    var additionalCleanup: ((Self) -> ())? { get set }
}

public extension SocketType {
    var cleaner: Cleaner {
        return Cleaner(fn: self.clean)
    }
    
    public func clean() {
        additionalCleanup?(self)
        close(sockfd)
    }
}

public protocol Addressable {
    var address: SXSocketAddress? { get set }
    var port: in_port_t? { get set }
}

public final class Cleaner {
    public var fn: () -> ()
    
    public init(fn: @escaping () -> ()) {
        self.fn = fn
    }
    
    deinit {
        fn()
    }
}

public protocol ServerSocket : SocketType, Addressable {
    associatedtype ClientSocketType
    var defaultClientConfiguation: ClientSocketConfiguation { get set }
    var accept: (Self) throws -> ClientSocketType { get set }
}

public protocol ClientSocket : SocketType, Readable, Writable {
    /* storing address */
    var address: SXSocketAddress? { get set }
}

public protocol ConnectionSocket : SocketType, Addressable, Readable, Writable {
    var address: SXSocketAddress? { get set }
    var port: in_port_t? { get set }
    func connect() throws
}

public struct ClientReadWriteFunctions<ClientSocketType> {
    var read: (ClientSocketType) throws -> Data
    var write: (ClientSocketType, _ data: Data) throws -> ()
    var clean: ((ClientSocketType) -> ())?
}

public struct ClientSocketConfiguation {
    var flags_r: Int32
    var flags_w: Int32
    var readBufsize: size_t
    
    public init(read: (bufsize: size_t, flags: Int32),
                writeFlags: Int32) {
        self.readBufsize = read.bufsize
        self.flags_r = read.flags
        self.flags_w = writeFlags
    }
}

public struct DefaultServerSocketSet {
    public static func tcp_inet_inet6(domain: SXSocketDomains,
                                      port: in_port_t,
                                      type: SXSocketTypes,
                                      `protocol`: Int32,
                                      sockConf: ClientSocketConfiguation) throws -> SXServerSocket<SXClientSocket> {
        
        let read = { (client: SXClientSocket) throws -> Data in
            let size = client.readBufsize
            let flags = client.readFlags
            var buffer = [UInt8](repeating: 0, count: size)
            let len = recv(client.sockfd, &buffer, size, flags)
            if len == -1 {throw SXSocketError.recv(String.errno)}
            return Data(bytes: buffer, count: len)
        }
        
        let write = { (client: SXClientSocket, data: Data) throws -> () in
            if Foundation.send(client.sockfd, data.bytesCopied, data.length, client.writeFlags) == -1 {
                throw SXSocketError.send("send: \(String.errno)")
            }
        }
        
        let fns = ClientReadWriteFunctions(read: read, write: write, clean: nil)
        
        let accept: @escaping (SXServerSocket<SXClientSocket>) throws -> SXClientSocket = {
            (server: SXServerSocket<SXClientSocket>) throws -> SXClientSocket in
            var addr = sockaddr()
            var socklen = socklen_t()
            let fd = Foundation.accept(server.sockfd, &addr, &socklen)
            getpeername(fd, &addr, &socklen)
            return try! SXClientSocket(fd: fd,
                                  addrinfo: (addr: addr, len: socklen),
                                  sockinfo: (type: type, protocol: `protocol`),
                                  rwconfig: server.defaultClientConfiguation,
                                  functions: fns)
            }
        
        let address = try SXSocketAddress(withDomain: SXSocketDomains(rawValue: domain.rawValue)!,
                                          port: port)
        
        return try SXServerSocket<SXClientSocket>(address: address, port: port, type: type, protocol: `protocol`, clientConf: sockConf, accept: accept)
    }
    
    public static func tcp_tls_inet_inet6(domain: SXSocketDomains,
                                          certInfo: (cert: String, key: String),
                                          port: in_port_t,
                                          type: SXSocketTypes,
                                          `protocol`: Int32,
                                          sockConf: ClientSocketConfiguation) throws -> SXTLSServerSocket<SXTLSClientSocket> {
        
        let read = { (client: SXTLSClientSocket) throws -> Data in
            let size = client.readBufsize
            let flags = client.readFlags
            var buffer = [UInt8](repeating: 0, count: size)
            let len = recv(client.sockfd, &buffer, size, flags)
            if len == -1 {throw SXSocketError.recv(String.errno)}
            return Data(bytes: buffer, count: len)
        }
        
        let write = { (client: SXTLSClientSocket, data: Data) throws -> () in
            if Foundation.send(client.sockfd, data.bytesCopied, data.length, client.writeFlags) == -1 {
                throw SXSocketError.send("send: \(String.errno)")
            }
        }
        
        let clean: (_ client: SXTLSClientSocket) -> () = {
            (client: SXTLSClientSocket) in
//            tls_free(client.tlsContext.rawValue)
        }
        
        let fns = ClientReadWriteFunctions(read: read, write: write, clean: clean)
        
        let accept: @escaping (SXTLSServerSocket<SXTLSClientSocket>) throws -> SXTLSClientSocket = {
            (server: SXTLSServerSocket<SXTLSClientSocket>) throws -> SXTLSClientSocket in
            var addr = sockaddr()
            var socklen = socklen_t()
            let fd = Foundation.accept(server.sockfd, &addr, &socklen)
            getpeername(fd, &addr, &socklen)
            let context = try server.tlsContext.accept(socket: fd)
            return try! SXTLSClientSocket(fd: fd,
                                          context: context,
                                           addrinfo: (addr: addr, len: socklen),
                                           sockinfo: (type: type, protocol: `protocol`),
                                           rwconfig: server.defaultClientConfiguation,
                                           functions: fns)
        }
        
        let address = try SXSocketAddress(withDomain: SXSocketDomains(rawValue: domain.rawValue)!,
                                          port: port)
        
        return try SXTLSServerSocket<SXTLSClientSocket>(address: address,
                                                        port: port,
                                                        type: type,
                                                        protocol: `protocol`,
                                                        certInfo: certInfo,
                                                        clientConf: sockConf,
                                                        accept: accept)
    }
}

public struct SXServerSocket<ClientSocketType> : ServerSocket {
    
    public var additionalCleanup: ((SXServerSocket) -> ())?
    
    public var address: SXSocketAddress?
    public var port: in_port_t?
    
    public var defaultClientConfiguation: ClientSocketConfiguation
    
    public var sockfd: Int32
    public var domain: SXSocketDomains
    public var type: SXSocketTypes
    public var `protocol`: Int32
    
    public var accept: (_ from: SXServerSocket) throws -> ClientSocketType
    
    public init(address: SXSocketAddress,
                port: in_port_t,
                type: SXSocketTypes,
                `protocol`: Int32,
                clientConf: ClientSocketConfiguation,
                cleanup: ((SXServerSocket) -> ())? = nil,
                accept: @escaping (_ from: SXServerSocket<ClientSocketType>) throws -> ClientSocketType) throws {
        
        self.address = address
        self.port = port
        self.type = type
        self.defaultClientConfiguation = clientConf
        self.`protocol` = `protocol`
        self.domain = address.resolveDomain()!
        self.accept = accept
        
        self.additionalCleanup = cleanup
        self.sockfd = socket(Int32(domain.rawValue), type.rawValue, `protocol`)
        
        if sockfd == -1 {
            throw SXSocketError.socket(String.errno)
        }
        
        try self.bind()
    }
    
    public func listen(backlog: Int) throws {
        if Foundation.listen(sockfd, Int32(backlog)) < 0 {
            throw SXSocketError.listen(String.errno)
        }
    }
}

public struct SXClientSocket : ClientSocket {
    
    public var read: (SXClientSocket) throws -> Data?
    public var write: (SXClientSocket, Data) throws -> ()
    public var additionalCleanup: ((SXClientSocket) -> ())?
    
    public var sockfd: Int32
    public var domain: SXSocketDomains
    public var type: SXSocketTypes
    public var `protocol`: Int32
    
    public var address: SXSocketAddress?
    
    public var readBufsize: size_t
    public var readFlags: Int32
    public var writeFlags: Int32
    
    internal init(fd: Int32,
                addrinfo: (addr: sockaddr, len: socklen_t),
                sockinfo: (type: SXSocketTypes, `protocol`: Int32),
                rwconfig: ClientSocketConfiguation,
                functions: ClientReadWriteFunctions<SXClientSocket>) throws {
        self.address = try SXSocketAddress(addrinfo.addr, socklen: addrinfo.len)
        self.sockfd = fd
        
        switch Int(addrinfo.len) {
        case MemoryLayout<sockaddr_in>.size:
            self.domain = .inet
        case MemoryLayout<sockaddr_in6>.size:
            self.domain = .inet6
        case MemoryLayout<sockaddr_un>.size:
            self.domain = .unix
        default:
            throw SXSocketError.socket("Unknown domain")
        }
        
        self.type = sockinfo.type
        self.`protocol` = sockinfo.`protocol`
        self.readBufsize = rwconfig.readBufsize
        self.readFlags = rwconfig.flags_r
        self.writeFlags = rwconfig.flags_w
        
        self.read = functions.read
        self.write = functions.write
    }

}

public struct SXTLSServerSocket<ClientSocketType> : ServerSocket {
    
    public var additionalCleanup: ((SXTLSServerSocket) -> ())?
    
    public var address: SXSocketAddress?
    public var port: in_port_t?
    
    public var defaultClientConfiguation: ClientSocketConfiguation
    
    public var sockfd: Int32
    public var domain: SXSocketDomains
    public var type: SXSocketTypes
    public var `protocol`: Int32
    
    public var tlsContext: TLSServer
    
    public var accept: (_ from: SXTLSServerSocket) throws -> ClientSocketType
    
    public init(address: SXSocketAddress,
                port: in_port_t,
                type: SXSocketTypes,
                `protocol`: Int32,
                certInfo: (cert: String, key: String),
                clientConf: ClientSocketConfiguation,
                cleanup: ((SXTLSServerSocket) -> ())? = nil,
                accept: @escaping (_ from: SXTLSServerSocket<ClientSocketType>) throws -> ClientSocketType) throws {
        
        self.address = address
        self.port = port
        self.type = type
        self.defaultClientConfiguation = clientConf
        self.`protocol` = `protocol`
        self.domain = address.resolveDomain()!
        self.accept = accept
        
        self.additionalCleanup = cleanup
        self.sockfd = socket(Int32(domain.rawValue), type.rawValue, `protocol`)
        
        var conf = TLSConfig()
        conf.certificateFile = certInfo.cert
        conf.keyFile = certInfo.key
        
        self.tlsContext = try TLSServer(with: conf)!
        
        if sockfd == -1 {
            throw SXSocketError.socket(String.errno)
        }
    }
}

public struct SXTLSClientSocket : ClientSocket {
    
    public var read: (SXTLSClientSocket) throws -> Data?
    public var write: (SXTLSClientSocket, Data) throws -> ()
    public var additionalCleanup: ((SXTLSClientSocket) -> ())?
    
    public var sockfd: Int32
    public var domain: SXSocketDomains
    public var type: SXSocketTypes
    public var `protocol`: Int32
    
    public var address: SXSocketAddress?
    
    public var readBufsize: size_t
    public var readFlags: Int32
    public var writeFlags: Int32
    
    public var tlsContext: TLSClient
    
    internal init(fd: Int32,
                  context: TLSClient,
                  addrinfo: (addr: sockaddr, len: socklen_t),
                  sockinfo: (type: SXSocketTypes, `protocol`: Int32),
                  rwconfig: ClientSocketConfiguation,
                  functions: ClientReadWriteFunctions<SXTLSClientSocket>) throws {
        self.address = try SXSocketAddress(addrinfo.addr, socklen: addrinfo.len)
        self.sockfd = fd
        
        switch Int(addrinfo.len) {
        case MemoryLayout<sockaddr_in>.size:
            self.domain = .inet
        case MemoryLayout<sockaddr_in6>.size:
            self.domain = .inet6
        case MemoryLayout<sockaddr_un>.size:
            self.domain = .unix
        default:
            throw SXSocketError.socket("Unknown domain")
        }
        
        self.tlsContext = context
        
        self.type = sockinfo.type
        self.`protocol` = sockinfo.`protocol`
        self.readBufsize = rwconfig.readBufsize
        self.readFlags = rwconfig.flags_r
        self.writeFlags = rwconfig.flags_w
        
        self.read = functions.read
        self.write = functions.write
    }
    
}
