// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import CoreData

public final class BraveTodaySourceMO: NSManagedObject, CRUD {
    @NSManaged public var enabled: Bool
    @NSManaged public var publisherID: String
    
    public class func all() -> [BraveTodaySourceMO] {
        all() ?? []
    }
    
    public class func setEnabled(forId id: String, enabled: Bool) {
        setEnabledInternal(forId: id, enabled: enabled)
    }
    
    public class func resetSourceSelection() {
        deleteAll()
    }
    
    class func getInternal(fromId id: String, context: NSManagedObjectContext = DataController.viewContext) -> BraveTodaySourceMO? {
        let predicate = NSPredicate(format: "\(#keyPath(BraveTodaySourceMO.publisherID)) == %@", id)
        return first(where: predicate, context: context)
    }
    
    class func setEnabledInternal(forId id: String, enabled: Bool, context: WriteContext = .new(inMemory: false)) {
        DataController.perform(context: context) { context in
            if let source = getInternal(fromId: id, context: context) {
                source.enabled = enabled
            } else {
                insertInternal(publisherID: id, enabled: enabled, context: .existing(context))
            }
        }
    }
    
    class func insertInternal(publisherID: String, enabled: Bool, context: WriteContext = .new(inMemory: false)) {
        DataController.perform(context: context) { context in
            let source = BraveTodaySourceMO(entity: entity(in: context), insertInto: context)
            
            source.enabled = enabled
            source.publisherID = publisherID
        }
    }
    
    private class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: "BraveTodaySourceMO", in: context)!
    }
}
