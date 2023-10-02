import XCTest
@testable import OrderlyLocator

final class OrderlyLocatorTests: XCTestCase {
    func test_whenADependencyIsRegistered_itCanBeResolved() throws {
        let locator = OrderlyLocator {
            Singleton { 5 }
        }
        let highFive: Int = locator.resolve()
        XCTAssertEqual(highFive, 5)
    }
    
    func test_whenADependencyIsRegisteredInAParent_itCanBeResolved() throws {
        let locator = OrderlyLocator {
            Singleton { 5 }
        }.child { parent in
            Unique {
                try Count(value: parent.safeResolve())
            }
        }
        
        let highFive: Count = locator.resolve()
        let highestOfFives: Int = locator.resolve()
        
        XCTAssertEqual(highFive, Count(value: 5))
        XCTAssertEqual(highestOfFives, 5)
    }
    
    func test_whenADependencyRequiresConfiguration_itCanBeInjectedAtResolution() throws {
        let locator = OrderlyLocator {
            Unique { (value: Int) in
                Count(value: value)
            }
        }
        
        let highFive: Count = locator.resolve(configuration: 5)
        
        XCTAssertEqual(highFive, Count(value: 5))
    }
    
    func test_whenADependencyIsRegisteredWithMultipleConfigurationTypes_theyCanBeIndependentlyResolved() throws {
        let locator = OrderlyLocator {
            Unique { (value: Int) in
                Count(value: value)
            }
            Singleton {
                Count(value: 5)
            }
        }
        
        let loneliestNumber: Count = locator.resolve(configuration: 1)
        let highFive: Count = locator.resolve()
        
        XCTAssertEqual(loneliestNumber, Count(value: 1))
        XCTAssertEqual(highFive, Count(value: 5))
    }
    
    func test_whenDependencyIsNotResolvable_auditThrows() throws {
        let locator = OrderlyLocator {
            Singleton {
                "This string is not important"
            }
        }.child { parent in
            Singleton {
                try Count(value: parent.safeResolve())
            }
        }
        
        XCTAssertThrowsError(try locator.audit())
    }
    
    func test_whenEverythingIsResolvable_auditShouldNotThrow() {
        let locator = OrderlyLocator {
            Unique {
                ""
            }
            Singleton {
                5.0
            }
            Unique { (value: Int) in
                Count(value: value)
            }
        }
        
        let configurableValues = OrderlyLocator {
            Singleton {
                5
            }
        }
        
        XCTAssertNoThrow(try locator.audit(configurableValues))
    }
    
    func test_whenAParentLocatorHasAnUnresolvableDependency_auditShouldStillFail() {
        let locator = OrderlyLocator {
            Unique { 5.0 }
        }.child { parent in
            Unique { try Count(value: parent.safeResolve()) }
        }.child { parent in
            Unique { 5 }
        }
        
        XCTAssertThrowsError(try locator.audit())
    }
    
    func test_whenAuditCannotFinishDueToMissingConfiguration_errorIsDescriptive() throws {
        let locator = OrderlyLocator {
            Unique { (value: Int) in
                Count(value: value)
            }
        }
        
        do {
            try locator.audit()
        } catch {
            let auditError = try XCTUnwrap(error as? AuditMissingConfiguration)
            XCTAssertEqual(auditError.description, "Could not complete audit due to missing configuration for type: Int.Type for output Count.Type")
        }
    }
    
    func test_singletonRegistrations_returnSameInstance() throws {
        let locator = OrderlyLocator {
            Singleton {
                NSObject()
            }
        }
        
        let myObject: NSObject = locator.resolve()
        let ourObject: NSObject = locator.resolve()
        
        XCTAssertIdentical(myObject, ourObject)
    }
    
    func test_uniqueRegistrations_returnUniqueInstances() {
        let locator = OrderlyLocator {
            Unique {
                NSObject()
            }
        }
        
        let myObject: NSObject = locator.resolve()
        let yourObject: NSObject = locator.resolve()
        
        XCTAssertNotIdentical(myObject, yourObject)
    }
}

struct Count: Equatable {
    let value: Int
}
