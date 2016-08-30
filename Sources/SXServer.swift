
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

public class SXRouter {
    var socket: SXServerSocket<SXClientSocket>
    var backlog: Int
    
    var handlers: SXQueueHandlers<SXClientSocket, SXClientSocket>
    public init(port: in_port_t,
                domain: SXSocketDomains,
                `protocol`: Int32 = 0,
                maxGuest: Int,
                backlog: Int,
                bufsize: Int = 16384,
                dataHandler: @escaping (SXQueue<SXClientSocket, SXClientSocket>, Data) -> Bool) throws {
        
        self.socket = try DefaultServerSocketSet.tcp_inet_inet6(domain: domain, port: port, type: .stream, protocol: `protocol`, sockConf: ClientSocketConfiguation(read: (bufsize: bufsize, flags: 0), writeFlags: 0))
        self.backlog = backlog
        self.handlers = SXQueueHandlers(dataHandler: dataHandler, errHandler: nil, willTerminateHandler: nil, didTerminateHandler: nil)
        self.start()
    }
    
    public func start() {
        let b = backlog

        SXThreadPool.default.execute {
            do {
                try self.socket.listen(backlog: b)
                let sock = try self.socket.accept(self.socket)
                var queue = SXQueue<SXClientSocket, SXClientSocket>(readFrom: sock, writeTo: sock, with: self.handlers)
                SXThreadPool.default.execute {
                    queue.start()
                }
            } catch {
                print(error)
            }
        }

    }
}
