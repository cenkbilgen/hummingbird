//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2023-2024 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Hummingbird
import HummingbirdCore
import Logging
import NIOCore
import ServiceLifecycle

/// TestApplication used to wrap Application being tested.
///
/// This is needed to override the `onServerRunning` function
internal struct TestApplication<BaseApp: ApplicationProtocol>: ApplicationProtocol, Service {
    typealias Responder = BaseApp.Responder

    let base: BaseApp

    var responder: Responder {
        get async throws { try await self.base.responder }
    }

    var server: HTTPServerBuilder {
        self.base.server
    }

    /// Event loop group used by application
    var eventLoopGroup: EventLoopGroup { self.base.eventLoopGroup }
    /// Configuration
    var configuration: ApplicationConfiguration { self.base.configuration.with(address: .hostname("localhost", port: 0)) }
    /// Logger
    var logger: Logger { self.base.logger }
    /// On server running
    @Sendable func onServerRunning(_ channel: Channel) async {
        await self.base.onServerRunning(channel)
        await self.portPromise.complete(channel.localAddress!.port!)
    }

    /// Services attached to the application.
    var services: [any Service] { self.base.services }

    /// Processes run before server start
    public var processesRunBeforeServerStart: [@Sendable () async throws -> Void] { self.base.processesRunBeforeServerStart }

    let portPromise: Promise<Int> = .init()
}

/// Promise type.
actor Promise<Value> {
    enum State {
        case blocked([CheckedContinuation<Value, Never>])
        case unblocked(Value)
    }

    var state: State

    init() {
        self.state = .blocked([])
    }

    /// wait from promise to be completed
    func wait() async -> Value {
        switch self.state {
        case .blocked(var continuations):
            return await withCheckedContinuation { cont in
                continuations.append(cont)
                self.state = .blocked(continuations)
            }
        case .unblocked(let value):
            return value
        }
    }

    /// complete promise with value
    func complete(_ value: Value) {
        switch self.state {
        case .blocked(let continuations):
            for cont in continuations {
                cont.resume(returning: value)
            }
            self.state = .unblocked(value)
        case .unblocked:
            break
        }
    }
}
