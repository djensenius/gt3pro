//
//  NinebotAuth.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation

/// Authentication state for the Ninebot 3-phase handshake.
enum AuthState: Sendable {
    case idle
    case preComm
    case setPwd
    case auth
    case authenticated
    case failed(String)
}

/// 3-phase authentication handshake state machine for the Ninebot Enc2 protocol.
///
/// Flow: PRE_COMM → SET_PWD → AUTH → Authenticated
/// With stored password: PRE_COMM → AUTH (skip SET_PWD)
actor NinebotAuth {
    private(set) var state: AuthState = .idle
    private var btName: String
    private var crypto: NinebotCrypto
    private var authParam: Data?
    private var serialNumber: Data?
    private var password: Data?
    private var storedPassword: Data?
    private var deviceHasStoredPassword = false
    private var setPwdRetryCount = 0

    init(btName: String, crypto: NinebotCrypto, storedPassword: Data? = nil) {
        self.btName = btName
        self.storedPassword = storedPassword
        self.crypto = crypto
    }

    /// Convenience initializer for tests — creates a NinebotCrypto derived from btName.
    /// Production code should inject a shared crypto instance via the primary initializer
    /// so auth and transport stay in sync.
    init(btName: String, storedPassword: Data? = nil) {
        let key = KeyDerivation.deriveKey(key1: Data(btName.utf8), key2: nil)
        self.btName = btName
        self.storedPassword = storedPassword
        self.crypto = NinebotCrypto(key: key, counter: 0)
    }

    /// Start the handshake by generating the PRE_COMM frame.
    func startAuth() -> Data {
        state = .preComm
        let plainFrame = NinebotFrameBuilder.buildAuthFrame(cmd: .preComm, data: Data())
        return plainFrame
    }

    /// Process a decrypted response frame and advance state.
    /// Returns the next frame to send, or nil if waiting/done/failed.
    func processResponse(_ parsed: NinebotFrameBuilder.ParsedFrame) -> Data? {
        switch state {
        case .preComm:
            return handlePreCommResponse(parsed)
        case .setPwd:
            return handleSetPwdResponse(parsed)
        case .auth:
            return handleAuthResponse(parsed)
        default:
            return nil
        }
    }

    // MARK: - PRE_COMM

    private func handlePreCommResponse(
        _ parsed: NinebotFrameBuilder.ParsedFrame
    ) -> Data? {
        guard parsed.cmd == BLEConstants.Command.preComm.rawValue
                || parsed.cmd == BLEConstants.Command.readAck.rawValue else {
            return nil
        }

        let responseData = parsed.payload
        guard responseData.count >= 30 else {
            state = .failed("PRE_COMM response too short: \(responseData.count) bytes")
            return nil
        }

        authParam = Data(responseData[0..<16])
        serialNumber = Data(responseData[16..<30])
        deviceHasStoredPassword = parsed.index != 0

        crypto.updateAuthParam(authParam!)
        crypto.enableSNMode()

        // If we have a stored password AND device has one, skip SET_PWD.
        // Normal handshake consumes counter=1 for SET_PWD, so AUTH expects counter=2.
        if let stored = storedPassword, deviceHasStoredPassword {
            password = stored
            let authKey = KeyDerivation.deriveKey(key1: stored, key2: authParam!)
            crypto.updateKey(authKey)
            crypto.updateAuthParam(authParam!)
            crypto.setCounter(2)
            state = .auth
            return buildAuthFrame()
        }

        // Otherwise go to SET_PWD
        let setPwdKey = KeyDerivation.deriveKey(key1: Data(btName.utf8), key2: authParam!)
        crypto.updateKey(setPwdKey)

        password = JavaLCG.generatePassword(authParam: authParam!)
        state = .setPwd
        setPwdRetryCount = 0
        return buildSetPwdFrame()
    }

    // MARK: - SET_PWD

    private func buildSetPwdFrame() -> Data {
        NinebotFrameBuilder.buildAuthFrame(cmd: .setPwd, data: password!)
    }

    private func handleSetPwdResponse(
        _ parsed: NinebotFrameBuilder.ParsedFrame
    ) -> Data? {
        guard parsed.cmd == BLEConstants.Command.setPwd.rawValue
                || parsed.cmd == BLEConstants.Command.readAck.rawValue else {
            return nil
        }

        if parsed.index == 1 {
            // Accepted — move to AUTH
            let authKey = KeyDerivation.deriveKey(key1: password!, key2: authParam!)
            crypto.updateKey(authKey)
            state = .auth
            return buildAuthFrame()
        }

        // INDEX=0 means waiting for button press on scooter
        setPwdRetryCount += 1
        if setPwdRetryCount >= BLEConstants.setPwdMaxRetries {
            state = .failed("SET_PWD timed out waiting for button press")
            return nil
        }

        // Return same frame to retry (caller should wait 2s between sends)
        return buildSetPwdFrame()
    }

    // MARK: - AUTH

    private func buildAuthFrame() -> Data {
        NinebotFrameBuilder.buildAuthFrame(cmd: .auth, data: serialNumber!)
    }

    private func handleAuthResponse(
        _ parsed: NinebotFrameBuilder.ParsedFrame
    ) -> Data? {
        guard parsed.cmd == BLEConstants.Command.auth.rawValue
                || parsed.cmd == BLEConstants.Command.readAck.rawValue else {
            return nil
        }

        if parsed.index == 1 {
            state = .authenticated
            return nil
        }

        // AUTH failed
        if storedPassword != nil {
            // Clear stored password and retry from SET_PWD
            storedPassword = nil
            let setPwdKey = KeyDerivation.deriveKey(
                key1: Data(btName.utf8),
                key2: authParam!
            )
            crypto.updateKey(setPwdKey)
            password = JavaLCG.generatePassword(authParam: authParam!)
            state = .setPwd
            setPwdRetryCount = 0
            return buildSetPwdFrame()
        }

        state = .failed("AUTH rejected by device")
        return nil
    }

    // MARK: - Accessors

    func getSerialNumber() -> String? {
        guard let data = serialNumber else { return nil }
        return String(data: data, encoding: .ascii)
    }

    func getPassword() -> Data? {
        password
    }

    /// Perform a crypto operation while keeping the mutable crypto engine
    /// encapsulated inside actor isolation.
    func withCrypto<T: Sendable>(
        _ operation: (NinebotCrypto) throws -> T
    ) rethrows -> T {
        try operation(crypto)
    }
}
