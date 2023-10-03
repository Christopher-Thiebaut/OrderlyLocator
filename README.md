# OrderlyLocator
A Swift implementation of a service locator designed to make mistakes hard and testing easy

## Registration
Registration happens in rounds.  Registrations can use the locator to resolve dependencies, but registrations can only access services registered in a previous round.  This makes circular dependencies impossible.
Registration uses Swift's result builder syntax to allow each round or registrations to be written out as a list without repetitive calls to `locator.register` or a similar function.

Here is an example of what registration might look like:
```
let locator: UnsafeResolver = OrderlyLocator {
    Singleton {
       URLSession.shared as NetworkClient
    }
    Singleton {
      FileManager.default as Storage
    }
}.child { basicDependencies in
   Unique {
     try ViewModel(networkClient: basicDependencies.safeResolve())
   }
   /*
   Unique {
    try ViewController(viewModel: basicDependencies.safeResolve()) // resolution will fail because ViewModel was not registered in the same round, but a previous round
   }
   */
}
```
Each group of registrations is a list of dependencies being registered, each wrapped in the `Scope` that determines the lifetime of the dependency.  The two scopes that ship with the
library are `Singleton` and `Unique`.  `Singleton` returns the same instance each time the dependency is resolved whereas `Unique` returns a different instance each time.  It is also
possible to define a custom `Scope` by conforming to the `Scope` protocol.

In order to reduce the likelyhood or runtime issues, the locator is immutable.  Registrations cannot be modified once the locator is created.  The `child` function does not
modify existing registrations -- it creates a new service locator with access to the old one and forwards requests for unregistered dependencies to the previous locator.

## Resolution
`OrderlyLocator` conforms to both `SafeResolver` and `UnsafeResolver`.

```
public protocol SafeResolver {
    func safeResolve<Dependency>() throws -> Dependency
    func safeResolve<Configuration, Dependency>(configuration: Configuration) throws -> Dependency
}

public protocol UnsafeResolver {
    func resolve<Dependency>() -> Dependency
    func resolve<Configuration, Dependency>(configuration: Configuration) throws -> Dependency
}
```
Either can be used to resolve dependencies, depending on whether you would prefer the locator to throw so you can attempt to recover from these errors at runtime or whether you
consider failure to resolve a dependency unrecoverable and do not want to litter your code with `try!` statements.

However, in order to assist with testing, only `SafeResolver` is visible while registering new dependencies in a child locator.

## Configuration
Some dependencies may require configuration that is only available at runtime (such as the result of a user selection).  As such, it is possible to pass in some configuration while
resolving a dependency.

In order to accept configuration during dependency resolution, the closure passed to the `Scope` during registration must accept a parameter, as seen below:
```
let locator = OrderlyLocator { 
     Unique { (userID: String) in
         UserViewModel(userID: userID)
     }
}
```
The dependency can then be resolved using the version of the `resolve` function that requires a configuration as such:
```
let userViewModel: UserViewModel = locator.resolve(configuration: "ABC")
```

Mutliple dependencies of the same type may also be registered by using a type as a name.  For example:
```
let locator = OrderlyLocator {
    Singleton { (_: HomeTabKey) in
        Router()
    }
    Singleton { (_: SettingsTabKey) in
        Router()
    }
}
```
would allow multiple `Router` singletons to be registered that could be resolved separately like so:
```
let homeTabRouter: Router = locator.resolve(configuration: HomeTabKey())
let settingsTabRouter: Router = locator.resolve(configuration: SettingsTabKey())
```

## Testing
`OrderlyLocator` ships with several overloads of an `audit` function that is designed to simplify testing the validity of your object graph. Calling `audit` on an instance 
of `OrderlyLocator` attempts to create an instance of each dependency registered in the locator and all parents.  `audit` will throw an error if any registered dependency 
cannot be resolved.

For example:
```
try OrderlyLocator {
    Singleton { (_: HomeTabKey) in
        Router()
    }
}.child { parentLocator in
   Unique {
       SettingsView(router: parentLocator.safeResolve(configuration: SettingsTabKey()))
   }
}.audit()
```
will throw an error.  This allows you to easily test the validity of your registrations with an `XCTAssertNoThrow` assertion.

Note, however, that `audit` does not guarantee that nothing in the app attempts to resolve a dependency that was never registered at all.

`audit` may still be used if some dependencies require configuration.  In order to `audit` registrations that require configuration, you must provide a locator or set of 
registrations that provide an instance of each `Configuration` type in your registrations.  Failure to do so will cause `audit` to throw a `AuditMissingConfiguration` error.
`AuditMissingConfiguration` does not indicate an issue with your registrations.  It indicates you need to supply additional configuration to your test.

Consider the following registration:
```
static let locator = OrderlyLocator { 
     Unique { (userID: String) in
         UserViewModel(userID: userID)
     }
}
```
In order to `audit` the locator above, the test would need to provide a `String` in its configuration locator as follows:
```
furn testExample() {
       let configurableValues = OrderlyLocator {
            Singleton {
                "123"
            }
        }
        
        XCTAssertNoThrow(try locator.audit(configurableValues))
}
```








