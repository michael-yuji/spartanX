
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
//  Created by Yuji on 6/2/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

import Foundation
import CKit

#if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
public let UNIX_PATH_MAX = 104
#elseif os(FreeBSD) || os(Linux)
public let UNIX_PATH_MAX = 108
#endif

public enum DNSLookupHint {
    case Flags(Int32)
    case Family(Int32)
    case SockType(Int32)
    case `Protocol`(Int32)
    case Canonname(String)
}

extension sockaddr_in {
    init(port: in_port_t, addr: in_addr = in_addr(s_addr: 0)) {
        #if os(Linux)
            self = sockaddr_in(sin_family: sa_family_t(AF_INET),
                               sin_port: port,
                               sin_addr: in_addr(s_addr: 0),
                               sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        #else
            self = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
                               sin_family: sa_family_t(AF_INET),
                               sin_port: port,
                               sin_addr: in_addr(s_addr:0),
                               sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        #endif
    }
}

extension sockaddr_in6 {
    init(port: in_port_t, addr: in6_addr = in6addr_any) {
        #if os(Linux)
            self = sockaddr_in6(sin6_family: sa_family_t(AF_INET6),
                                sin6_port: port,
                                sin6_flowinfo: 0,
                                sin6_addr: addr,
                                sin6_scope_id: 0)
        #else
            self = sockaddr_in6(sin6_len: UInt8(MemoryLayout<sockaddr_in6>.size),
                                sin6_family: sa_family_t(AF_INET6),
                                sin6_port: port,
                                sin6_flowinfo: 0,
                                sin6_addr: addr,
                                sin6_scope_id: 0)
        #endif
    }
}

public enum SXSocketAddress {
    case inet(sockaddr_in)
    case inet6(sockaddr_in6)
    case unix(sockaddr_un)
    
    public var ipaddress: String {
        #if swift(>=3)
            var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        #else
            var buffer = [Int8](count: Int(255), repeatedValue: 0)
        #endif
        switch self {
        case var .inet(`in`):
            inet_ntop(AF_INET, pointer(of: &`in`.sin_addr) , &buffer, socklen_t(MemoryLayout<sockaddr_in>.size))
        case var .inet6(in6):
            inet_ntop(AF_INET6, pointer(of: &in6.sin6_addr) , &buffer, socklen_t(MemoryLayout<sockaddr_in6>.size))
        case var .unix(un):
            strncpy(&buffer, pointer(of: &un.sun_path).cast(to: Int8.self), Int(PATH_MAX))
        }
        #if swift(>=3)
            return String(cString: buffer)
        #else
            return String(CString: buffer, encoding: NSASCIIStringEncoding)!
        #endif
    }
    
    public func sockdomain() -> SXSocketDomains? {
        switch self.socklen {
        case UInt32(MemoryLayout<sockaddr_in>.size):
            return .inet
        case UInt32(MemoryLayout<sockaddr_in6>.size):
            return .inet6
        case UInt32(MemoryLayout<sockaddr_un>.size):
            return .unix
        default: return nil
        }
    }
    
    public init(_ addr_: sockaddr, socklen: socklen_t) throws {
        var addr = addr_
        switch socklen {
        case UInt32(MemoryLayout<sockaddr_in>.size):
            self = .inet(mutablePointer(of: &addr).cast(to: sockaddr_in.self).pointee)
        case UInt32(MemoryLayout<sockaddr_in6>.size):
            self = .inet6(mutablePointer(of: &addr).cast(to: sockaddr_in6.self).pointee)
            
        default:
            throw SXSocketError.nonImplementedDomain
        }
    }
    
    public static func boardcastAddr(port: in_port_t = 0) throws -> SXSocketAddress {
        return SXSocketAddress(address: "255.255.255.255", withDomain: .inet, port: port)!
    }
    
    public init(withDomain domain: SXSocketDomains, port: in_port_t) throws {
        switch domain {
        case .inet:
            self = SXSocketAddress.inet(sockaddr_in(port: port.bigEndian))
        case .inet6:
            self = SXSocketAddress.inet6(sockaddr_in6(port: port.bigEndian))
        default:
            throw SXSocketError.nonImplementedDomain
        }
    }
    
    public init?(address: String, withDomain domain: SXSocketDomains, port: in_port_t) {
        switch domain {
            
        case .inet:
            var sockaddr = sockaddr_in(port: port.bigEndian)
            inet_pton(AF_INET,
                  address.cString(using: .ascii),
                  UnsafeMutableRawPointer(mutablePointer(of: &sockaddr.sin_addr)))

            self = .inet(sockaddr)
            
        case .inet6:
            var sockaddr = sockaddr_in6(port: port.bigEndian)
            inet_pton(AF_INET6,
                      address.cString(using: .ascii),
                      UnsafeMutableRawPointer(mutablePointer(of: &sockaddr.sin6_addr)))

            self = .inet6(sockaddr)
            
        case .unix:
            var sockaddr = sockaddr_un()
            sockaddr.sun_family = sa_family_t(AF_UNIX)
            #if !os(Linux)
            sockaddr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            #endif
            let cstr = address.cString(using: .utf8)!
            strncpy(mutablePointer(of: &(sockaddr.sun_path)).cast(to: Int8.self), cstr, UNIX_PATH_MAX)
            
            self = .unix(sockaddr)
            
        default:
            return nil
        }
    }
    
    public var socklen: socklen_t {
        get {
            switch self {
            case .inet6(_):
                return socklen_t(MemoryLayout<sockaddr_in6>.size)
            case .inet(_):
                return socklen_t(MemoryLayout<sockaddr_in>.size)
            case .unix(_):
                return socklen_t(MemoryLayout<sockaddr_un>.size)
            }
        }
    }

    public static func DNSLookup(hostname: String, service: String, hints: [DNSLookupHint] = []) throws -> SXSocketAddress? {
        
        var info: UnsafeMutablePointer<addrinfo>? = nil
        var cinfo: UnsafeMutablePointer<addrinfo>? = nil
        var ret: SXSocketAddress
        
        var hint = addrinfo()
        for hint_ in hints {
            switch hint_ {
            case var .Flags(i): hint.ai_flags = i
            case var .Family(i): hint.ai_family = i
            case var .SockType(i): hint.ai_socktype = i
            case var .Protocol(i): hint.ai_protocol = i
            case var .Canonname(s):
                var ss = s.cInt8String ?? []
                hint.ai_canonname = UnsafeMutablePointer<Int8>(mutating: ss)
            }
        }
        
        if getaddrinfo(hostname.cString(using: .ascii)!,
                       service.cString(using: .ascii)!,
                       &hint,
                       &info) != 0 {
            
            throw SXAddrError.getAddrInfo(String.errno)
        }
        
        defer {
            freeaddrinfo(info)
        }
        
        cinfo = info
        
        while cinfo != nil {
            cinfo = cinfo!.pointee.ai_next
            let port = (UInt16(getservbyname(service.cString(using: String.Encoding.ascii)!, nil).pointee.s_port))
            let addr = cinfo!.pointee.ai_addr
            switch cinfo!.pointee.ai_family {
            case AF_INET:
                ret = SXSocketAddress.inet(sockaddr_in(port: port,
                                                        addr: addr!.cast(to: sockaddr_in.self).pointee.sin_addr))
                return ret
                
            case AF_INET6:
                ret = SXSocketAddress.inet6(sockaddr_in6(port: port,
                                                         addr: addr!.cast(to: sockaddr_in6.self).pointee.sin6_addr))
                return ret
                
            default:
                continue;
            }
        }
        
        return nil
    }
    
    public static func DNSLookup(hostname: String, service: String, hints: [DNSLookupHint] = []) throws -> [SXSocketAddress] {
        
        var info: UnsafeMutablePointer<addrinfo>? = nil
        var cinfo: UnsafeMutablePointer<addrinfo>? = nil
        var ret = [SXSocketAddress]()
        
        var hint = addrinfo()
        for hint_ in hints {
            switch hint_ {
            case var .Flags(i): hint.ai_flags = i
            case var .Family(i): hint.ai_family = i
            case var .SockType(i): hint.ai_socktype = i
            case var .Protocol(i): hint.ai_protocol = i
            case var .Canonname(s):
                var ss = s.cInt8String ?? []
                hint.ai_canonname = UnsafeMutablePointer<Int8>(mutating: ss)
            }
        }
        
        if getaddrinfo(hostname.cString(using: .ascii)!,
                       service.cString(using: .ascii)!,
                       &hint,
                       &info) != 0 {
            
            throw SXAddrError.getAddrInfo(String.errno)
        }
        
        func clean() {
            freeaddrinfo(info)
        }
        
        defer {
            clean()
        }
        
        cinfo = info
        
        while cinfo != nil {
            cinfo = cinfo!.pointee.ai_next
            
            let port = (UInt16(getservbyname(service.cString(using: String.Encoding.ascii)!, nil).pointee.s_port))
            
            let addr = cinfo!.pointee.ai_addr
            
            switch cinfo!.pointee.ai_family {
                
            case AF_INET:
                let addr = SXSocketAddress.inet(sockaddr_in(port: port,
                                                            addr: addr!.cast(to: sockaddr_in.self).pointee.sin_addr))
                ret.append(addr)
                
            case AF_INET6:
                let addr = SXSocketAddress.inet6(sockaddr_in6(port: port,
                                                              addr: addr!.cast(to: sockaddr_in6.self).pointee.sin6_addr))
                ret.append(addr)
                
            default:
                continue;
            }
        }
        
        return ret
    }
    
    public static func DNSLookup(hostname: String, port: in_port_t, hints: [DNSLookupHint] = []) throws -> SXSocketAddress? {
        
        var info: UnsafeMutablePointer<addrinfo>? = nil
        var cinfo: UnsafeMutablePointer<addrinfo>? = nil
        var ret: SXSocketAddress
        
        var hint = addrinfo()
        for hint_ in hints {
            switch hint_ {
            case var .Flags(i): hint.ai_flags = i
            case var .Family(i): hint.ai_family = i
            case var .SockType(i): hint.ai_socktype = i
            case var .Protocol(i): hint.ai_protocol = i
            case var .Canonname(s):
                var ss = s.cInt8String ?? []
                hint.ai_canonname = UnsafeMutablePointer<Int8>(mutating: ss)
            }
        }
        
        if getaddrinfo(hostname.cString(using: .ascii)!,
                       nil,
                       &hint,
                       &info) != 0 {
            
            throw SXAddrError.getAddrInfo(String.errno)
        }
        
        func clean() {
            freeaddrinfo(info)
        }
        
        defer {
            clean()
        }
        
        cinfo = info
        
        while cinfo != nil {
            cinfo = cinfo!.pointee.ai_next

            let addr = cinfo!.pointee.ai_addr
            
            switch cinfo!.pointee.ai_family {
            case AF_INET:
                ret = SXSocketAddress.inet(sockaddr_in(port: port,
                                                            addr: addr!.cast(to: sockaddr_in.self).pointee.sin_addr))
                return ret
                
            case AF_INET6:
                ret = SXSocketAddress.inet6(sockaddr_in6(port: port,
                                                         addr: addr!.cast(to: sockaddr_in6.self).pointee.sin6_addr))
                return ret
                
            default:
                continue;
            }
        }
        
        return nil
    }
    
    public static func DNSLookup(hostname: String, port:in_port_t, hints: [DNSLookupHint] = []) throws -> [SXSocketAddress] {
        
        var info: UnsafeMutablePointer<addrinfo>? = nil
        var cinfo: UnsafeMutablePointer<addrinfo>? = nil
        var ret = [SXSocketAddress]()
        
        var hint = addrinfo()
        for hint_ in hints {
            switch hint_ {
            case var .Flags(i): hint.ai_flags = i
            case var .Family(i): hint.ai_family = i
            case var .SockType(i): hint.ai_socktype = i
            case var .Protocol(i): hint.ai_protocol = i
            case var .Canonname(s):
                var ss = s.cInt8String ?? []
                hint.ai_canonname = UnsafeMutablePointer<Int8>(mutating: ss)
            }
        }
        
        if getaddrinfo(hostname.cString(using: .ascii)!,
                       nil,
                       &hint,
                       &info) != 0 {
            
            throw SXAddrError.getAddrInfo(String.errno)
        }
        
        
        defer {
            freeaddrinfo(info)
        }
        
        cinfo = info
        
        while cinfo != nil {
            cinfo = cinfo!.pointee.ai_next
            let addr = cinfo!.pointee.ai_addr
            switch cinfo!.pointee.ai_family {
            case AF_INET:
                let addr = SXSocketAddress.inet(sockaddr_in(port: port,
                                                            addr: addr!.cast(to: sockaddr_in.self).pointee.sin_addr))
                ret.append(addr)
            case AF_INET6:
                let addr = SXSocketAddress.inet6(sockaddr_in6(port: port,
                                                              addr: addr!.cast(to: sockaddr_in6.self).pointee.sin6_addr))
                ret.append(addr)
            default:
                continue;
            }
        }
        
        return ret
    }
}

