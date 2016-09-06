
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

public struct ClientFunctions<ClientSocketType> {
    var read: (ClientSocketType) throws -> Data?
    var write: (ClientSocketType, _ data: Data) throws -> ()
    var clean: ((ClientSocketType) -> ())?
}

public protocol ClientIOConf {
    
}

public struct SXClientIOConf: ClientIOConf {
    var flags_r: Int32
    var flags_w: Int32
    var readBufsize: size_t
    
    public static var `default` = SXClientIOConf(read: (bufsize: 10240, flags: 0),
                                                 writeFlags: 0)
    
    public init(read: (bufsize: size_t, flags: Int32),
                writeFlags: Int32) {
        self.readBufsize = read.bufsize
        self.flags_r = read.flags
        self.flags_w = writeFlags
    }
}

public struct SXClientSocket : ClientSocket {
    
    internal var _read: (SXClientSocket) throws -> Data?
    internal var _write: (SXClientSocket, Data) throws -> ()
    internal var _clean: ((SXClientSocket) -> ())?
    
    public var sockfd: Int32
    public var domain: SXSocketDomains
    public var type: SXSocketTypes
    public var `protocol`: Int32
    
    public var address: SXSocketAddress?
    
    public var tlsContext: TLSClient?
    
    public var readBufsize: size_t
    public var readFlags: Int32
    public var writeFlags: Int32
    
    internal init(fd: Int32,
                  tls: TLSClient?,
                  addrinfo: (addr: sockaddr, len: socklen_t),
                  sockinfo: (type: SXSocketTypes, `protocol`: Int32),
                  rwconfig: SXClientIOConf,
                  functions: ClientFunctions<SXClientSocket>) throws {
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
        
        self._read = functions.read
        self._write = functions.write
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
    }
}
