// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

public protocol SafeResolver {
    func safeResolve<Dependency>() throws -> Dependency
    func safeResolve<Configuration, Dependency>(configuration: Configuration) throws -> Dependency
}

public protocol UnsafeResolver {
    func resolve<Dependency>() -> Dependency
    func resolve<Configuration, Dependency>(configuration: Configuration) throws -> Dependency
}

public final class OrderlyLocator: SafeResolver, UnsafeResolver {
    struct Identifier: Hashable {
        let input: ObjectIdentifier
        let output: ObjectIdentifier
    }
    fileprivate var storage: [Identifier: any Scope] = [:]
    private let parent: OrderlyLocator?
    
    public convenience init(@RegistrationBuilder _ registrations: () -> Registrar) {
        self.init(parent: nil, registrations)
    }
    
    init(parent: OrderlyLocator?, @RegistrationBuilder _ registrations: () -> Registrar) {
        self.parent = parent
        let registrar = registrations()
        registrar.finalize(context: self)
    }
    
    private init(parent: OrderlyLocator, registrar: Registrar) {
        self.parent = parent
        registrar.finalize(context: self)
    }
    
    public func child(@RegistrationBuilder _ registrations: (SafeResolver) -> Registrar) -> OrderlyLocator {
        let registrar = registrations(self)
        return OrderlyLocator(parent: self, registrar: registrar)
    }
    
    public func resolve<Dependency>() -> Dependency {
        try! safeResolve(configuration: ())
    }
    
    public func resolve<Configuration, Dependency>(configuration: Configuration) -> Dependency {
        try! safeResolve(configuration: configuration)
    }
    
    private func identifier<Input, Output>(input: Input.Type, output: Output.Type) -> Identifier {
        Identifier(
            input: ObjectIdentifier(Input.self),
            output: ObjectIdentifier(Output.self)
        )
    }
    
    public func safeResolve<Dependency>() throws -> Dependency {
        try safeResolve(configuration: ())
    }
    
    public func safeResolve<Configuration, Dependency>(configuration: Configuration) throws -> Dependency {
        let identifier = identifier(input: Configuration.self, output: Dependency.self)
        let resolver = storage[identifier] as? any Scope<Configuration, Dependency>
        print("resolving \(Dependency.self)")
        
        if let dependency = try resolver?.resolve(configuration) {
            return dependency
        } else {
            guard let parent = parent else {
                throw UnregisteredDependency(configuration: configuration, output: Dependency.self)
            }
            return try parent.safeResolve(configuration: configuration)
        }
    }
    
    func register<I, O>(_ resolver: some Scope<I, O>) {
        storage[identifier(input: I.self, output: O.self)] = resolver
    }
    
    public func audit() throws {
        try self.audit {
            Singleton { () }
        }
    }
    
    public func audit(_ configurations: OrderlyLocator) throws {
        let configurationsLocator = configurations
            .child { _ in
                Singleton {
                    ()
                }
            }
        for resolver in storage.values {
            try audit(resolver: resolver, with: configurationsLocator)
        }
        try parent?.audit(configurations)
    }
    
    public func audit(@RegistrationBuilder configurations: () -> Registrar) throws {
        let configurationLocator = OrderlyLocator(configurations)
        try audit(configurationLocator)
    }
    
    private func audit<R: Scope>(resolver: R, with configurations: OrderlyLocator) throws {
        do {
            let configuration: R.Input = try configurations.safeResolve()
            _ = try resolver.resolve(configuration)
        } catch {
            throw AuditMissingConfiguration(R.Input.self, output: R.Output.self)
        }
    }
}

public struct AuditMissingConfiguration: Error {
    let description: String
    init<Configuration, Output>(_ configuration: Configuration, output: Output) {
        description = "Could not complete audit due to missing configuration for type: \(Configuration.self) for output \(Output.self)"
    }
}

public struct UnregisteredDependency<Configuration, Output>: Error {
    let configuration: Configuration
    let output: Output.Type
}

public class Registrar {
    private var registrations: [(OrderlyLocator) -> Void] = []
    func register(_ resolver: some Scope) {
        registrations.append { context in
            context.register(resolver)
        }
    }
    
    func finalize(context: OrderlyLocator) {
        for registration in registrations {
            registration(context)
        }
    }
}

public final class Singleton<Input, Dependency>: Scope {
    @Atomic var cachedDependency: Dependency?
    var builder: (Input) throws -> Dependency
    
    public init(_ builder: @escaping (Input) throws -> Dependency) {
        self.builder = builder
    }
    
    public func resolve(_ input: Input) throws -> Dependency {
        if let cachedDependency {
            return cachedDependency
        } else {
            let dependency = try builder(input)
            cachedDependency = dependency
            return dependency
        }
    }
}

@propertyWrapper
struct Atomic<Value> {
  private let queue = DispatchQueue(label: "tech.helpfulnerd.\(UUID().uuidString)")
  private var value: Value

  public init(wrappedValue: Value) {
    self.value = wrappedValue
  }

  public var wrappedValue: Value {
    get {
      return queue.sync { value }
    }
    set {
      queue.sync { value = newValue }
    }
  }
}

public struct Unique<Input, Output>: Scope {
    let builder: (Input) throws -> Output

    public init(_ builder: @escaping (Input) throws -> Output) {
        self.builder = builder
    }
    
    public func resolve(_ input: Input) throws -> Output {
        try builder(input)
    }
}

public protocol Scope<Input, Output> {
    associatedtype Input
    associatedtype Output
    init(_ builder: @escaping (Input) throws -> Output)
    func resolve(_ input: Input) throws -> Output
}

public extension Scope where Input == Void {
    init(_ builder: @escaping () throws -> Output) {
        self.init({ _ in try builder() })
    }
}

@resultBuilder
public struct RegistrationBuilder {
    public static func buildPartialBlock<S: Scope>(first: S) -> Registrar {
        let registrar = Registrar()
        registrar.register(first)
        return registrar
    }
    
    public static func buildPartialBlock<S: Scope>(accumulated: Registrar, next: S) -> Registrar {
        accumulated.register(next)
        return accumulated
    }
}
