//
//  Linux.swift
//  spartanX
//
//  Created by yuuji on 7/13/16.
//
//

import Foundation

#if os(Linux)
public typealias Data = NSMutableData

    public extension Data {
        
        public var count: Int {
            return self.length
        }
        public func findBytes(bytes b: UnsafeMutablePointer<Void>, offset: Int = 0, len: Int) -> Int? {
            if offset < 0 || len < 0 || self.length == 0 || len + offset > self.length
            { return nil }
            
            var i = 0
            let mcmp = {memcmp(b, self.bytes.advancedBy(offset + i), len)}
            
            
            while (mcmp() != 0) {
                if i + offset == self.length {
                    break
                }
                i += 1
            }
            
            return i + offset
        }
    }

    public struct DataReader {
        public var origin: Data
        public var currentOffset: Int = 0
        
        init(fromData data: Data) {
            self.origin = data
        }
    }
    
    extension DataReader {
        
        public mutating func rangeOfNextSegmentOfData(separatedBy bytes: [UInt8]) -> NSRange? {
            var bytes = bytes
            return rangeOfNextSegmentOfData(separatedBy: &bytes)
        }
        public mutating func rangeOfNextSegmentOfData(separatedBy bytes: inout [UInt8]) -> NSRange? {
            guard let endpoint = origin.findBytes(bytes: &bytes,
                                                  offset: currentOffset,
                                                  len: bytes.count) else {
                                                    return nil
            }
            let begin = currentOffset
            let length = endpoint - currentOffset
            currentOffset = endpoint + bytes.count
            return NSMakeRange(begin, length)
        }
    }
    extension DataReader {
        
        public mutating func segmentOfData(separatedBy bytes: [UInt8], atIndex count: Int) -> Data? {
            var bytes = bytes
            return segmentOfData(separatedBy: &bytes, atIndex: count)
        }
        
        public mutating func segmentOfData(separatedBy bytes: inout [UInt8], atIndex count: Int) -> Data? {
            var holder: NSRange?
            var i = 0
            
            repeat {
                holder = rangeOfNextSegmentOfData(separatedBy: &bytes)
                i += 1
            } while i <= count && holder != nil
            
            if holder == nil {
                return nil
            }
            return origin.subdataWithRange(holder!).mutableCopy() as? Data
        }
    }
    
    extension DataReader {
        
        public mutating func nextSegmentOfData(separatedBy bytes: [UInt8]) -> Data? {
            var bytes = bytes
            return nextSegmentOfData(separatedBy: &bytes)
        }
        
        public mutating func nextSegmentOfData(separatedBy bytes: inout [UInt8]) -> Data? {
            if let range = rangeOfNextSegmentOfData(separatedBy: &bytes) {
                return origin.subdataWithRange(range).mutableCopy() as? Data
            }
            return nil
        }
    }
    
    extension DataReader {
        
        public mutating func forallSegments(separatedBy bytes: [UInt8], handler: (Data) -> Bool) {
            var bytes = bytes
            return forallSegments(separatedBy: &bytes, handler: handler)
        }
        
        public mutating func forallSegments(separatedBy bytes: inout [UInt8], handler: (Data) -> Bool) {
            var data = nextSegmentOfData(separatedBy: &bytes)
            while data != nil {
                if !handler(data!) {
                    break
                }
                data = nextSegmentOfData(separatedBy: &bytes)
            }
        }
        
    }
#endif
