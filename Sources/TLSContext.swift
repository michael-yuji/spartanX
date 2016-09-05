//
//  TLSContext.swift
//  spartanX
//
//  Created by yuuji on 9/5/16.
//
//

//import Foundation

public struct SXTLSContextInfo {
    public var certificate: (path: String, passwd: String?)
    public var privateKey: (path: String, passwd: String?)
    public var ca: (path: String, passwd: String?)?
    public var ca_path: String?
    
    public init(certificate: (path: String, passwd: String?),
                privateKey: (path: String, passwd: String?),
                ca: (path: String, passwd: String?)? = nil,
                ca_path: String? = nil) {
        self.certificate = certificate
        self.privateKey = privateKey
        self.ca = ca
        self.ca_path = ca_path
    }
}
