//
//  Conf.swift
//  spartanX
//
//  Created by yuuji on 9/5/16.
//
//

#if os(Linux) || os(FreeBSD)
import Glibc
#else
import Darwin
#endif

public struct SocketInfo {
    var sockfd: Int32
    var address: SXSocketAddress
}

public struct SXRouteConf {
    public var address: SXSocketAddress
    public var port: in_port_t
    
    public var domain: SXSocketDomains {
        return address.sockdomain()!
    }
    
    public var type: SXSocketTypes
    public var `protocol`: Int32
    public var backlog : Int
    
    public init(domain: SXSocketDomains,
                type: SXSocketTypes,
                port: in_port_t,
                backlog: Int = 50,
                using `protocol`: Int32 = 0) {
        self.address = try! SXSocketAddress(withDomain: domain, port: port)
        self.type = type
        self.port = port
        self.backlog = backlog
        self.`protocol` = `protocol`
    }
}
