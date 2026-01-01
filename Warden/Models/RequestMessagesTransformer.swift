
import Foundation

@objc(RequestMessagesTransformer)
class RequestMessagesTransformer: NSSecureUnarchiveFromDataTransformer {

    static let name = NSValueTransformerName(rawValue: "RequestMessagesTransformer")

    override class func transformedValueClass() -> AnyClass {
        return NSData.self
    }

    override class func allowsReverseTransformation() -> Bool {
        return true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let messages = value as? [[String: String]] else {
            return nil
        }
        return try? NSKeyedArchiver.archivedData(withRootObject: messages, requiringSecureCoding: true)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else {
            return nil
        }

        let allowedClasses: [AnyClass] = [
            NSArray.self,
            NSDictionary.self,
            NSString.self
        ]

        guard let unarchived = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: allowedClasses,
            from: data
        ) else {
            return nil
        }

        guard let array = unarchived as? [Any] else {
            return nil
        }

        var result: [[String: String]] = []
        result.reserveCapacity(array.count)

        for element in array {
            guard let dictionary = element as? [String: String] else {
                return nil
            }
            result.append(dictionary)
        }

        return result
    }
}
