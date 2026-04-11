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
        let key = KeyDerivation.deriveKey(key1: Data(btName.utf8), key2: BLEConstants.dataBasic)
        self.btName = btName
        self.storedPassword = storedPassword
        self.crypto = NinebotCrypto(key: key, counter: 0)
    }

    /// Start the handshake by generating the PRE_COMM frame.
    func startAuth() -> Data {
        state = .preComm
        print("[GT3] [AUTH] startAuth — btName: \"\(btName)\"")
        let plainFrame = NinebotFrameBuilder.buildAuthFrame(cmd: .preComm, data: Data())
        print("[GT3] [AUTH] Sending PRE_COMM: \(plainFrame.hexString)")
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
        print("[GT3] [AUTH] handlePreCommResponse — cmd: 0x\(String(parsed.cmd, radix: 16))" +
              " idx: \(parsed.index) payload(\(parsed.payload.count)): \(parsed.payload.hexString)")
        guard parsed.cmd == BLEConstants.Command.preComm.rawValue
                || parsed.cmd == BLEConstants.Command.readAck.rawValue else {
            print("[GT3] [AUTH] PRE_COMM: unexpected cmd 0x\(String(parsed.cmd, radix: 16)), ignoring")
            return nil
        }

        let responseData = parsed.payload
        guard responseData.count >= 30 else {
            state = .failed("PRE_COMM response too short: \(responseData.count) bytes")
            print("[GT3] [AUTH] PRE_COMM too short: \(responseData.count) bytes")
            return nil
        }

        authParam = Data(responseData[0..<16])
        serialNumber = Data(responseData[16..<30])
        deviceHasStoredPassword = parsed.index != 0
        print("[GT3] [AUTH] authParam: \(authParam!.hexString)")
        print("[GT3] [AUTH] serialNumber: \(serialNumber!.hexString)" +
              " → \(String(data: serialNumber!, encoding: .ascii) ?? "?")")
        print("[GT3] [AUTH] deviceHasStoredPassword: \(deviceHasStoredPassword) (index=\(parsed.index))")
        print("[GT3] [AUTH] storedPassword in app: \(storedPassword != nil ? storedPassword!.hexString : "nil")")

        crypto.updateAuthParam(authParam!)
        crypto.enableSNMode()

        // If we have a stored password AND device has one, skip SET_PWD.
        // Normal handshake consumes counter=1 for SET_PWD, so AUTH expects counter=2.
        if let stored = storedPassword, deviceHasStoredPassword {
            password = stored
            let authKey = KeyDerivation.deriveKey(key1: stored, key2: authParam!)
            print("[GT3] [AUTH] Fast-path: authKey=\(authKey.hexString), setting counter=2")
            crypto.updateKey(authKey)
            crypto.updateAuthParam(authParam!)
            crypto.setCounter(2)
            state = .auth
            let frame = buildAuthFrame()
            print("[GT3] [AUTH] Sending AUTH (fast-path): \(frame.hexString)")
            return frame
        }

        // Otherwise go to SET_PWD
        let setPwdKey = KeyDerivation.deriveKey(key1: Data(btName.utf8), key2: authParam!)
        print("[GT3] [AUTH] SET_PWD path: setPwdKey=\(setPwdKey.hexString)")
        crypto.updateKey(setPwdKey)

        password = JavaLCG.generatePassword(authParam: authParam!)
        print("[GT3] [AUTH] Generated password: \(password!.hexString)")
        state = .setPwd
        setPwdRetryCount = 0
        let frame = buildSetPwdFrame()
        print("[GT3] [AUTH] Sending SET_PWD: \(frame.hexString)")
        return frame
    }

    // MARK: - SET_PWD

    private func buildSetPwdFrame() -> Data {
        NinebotFrameBuilder.buildAuthFrame(cmd: .setPwd, data: password!)
    }

    private func handleSetPwdResponse(
        _ parsed: NinebotFrameBuilder.ParsedFrame
    ) -> Data? {
        print("[GT3] [AUTH] handleSetPwdResponse — cmd: 0x\(String(parsed.cmd, radix: 16)) idx: \(parsed.index)")
        guard parsed.cmd == BLEConstants.Command.setPwd.rawValue
                || parsed.cmd == BLEConstants.Command.readAck.rawValue else {
            print("[GT3] [AUTH] SET_PWD: unexpected cmd 0x\(String(parsed.cmd, radix: 16)), ignoring")
            return nil
        }

        if parsed.index == 1 {
            // Accepted — move to AUTH
            let authKey = KeyDerivation.deriveKey(key1: password!, key2: authParam!)
            print("[GT3] [AUTH] SET_PWD accepted — authKey: \(authKey.hexString)")
            crypto.updateKey(authKey)
            state = .auth
            let frame = buildAuthFrame()
            print("[GT3] [AUTH] Sending AUTH: \(frame.hexString)")
            return frame
        }

        // INDEX=0 means waiting for button press on scooter
        setPwdRetryCount += 1
        print("[GT3] [AUTH] SET_PWD waiting for button press" +
              " (retry \(setPwdRetryCount)/\(BLEConstants.setPwdMaxRetries))")
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
        print("[GT3] [AUTH] handleAuthResponse — cmd: 0x\(String(parsed.cmd, radix: 16)) idx: \(parsed.index)")
        guard parsed.cmd == BLEConstants.Command.auth.rawValue
                || parsed.cmd == BLEConstants.Command.readAck.rawValue else {
            print("[GT3] [AUTH] AUTH: unexpected cmd 0x\(String(parsed.cmd, radix: 16)), ignoring")
            return nil
        }

        if parsed.index == 1 {
            print("[GT3] [AUTH] ✅ AUTH accepted — authenticated!")
            state = .authenticated
            return nil
        }

        print("[GT3] [AUTH] 🔴 AUTH rejected (index=\(parsed.index))," +
              " storedPassword was: \(storedPassword != nil ? "set" : "nil")")
        // AUTH failed
        if storedPassword != nil {
            // Clear stored password and retry from SET_PWD
            storedPassword = nil
            let setPwdKey = KeyDerivation.deriveKey(
                key1: Data(btName.utf8),
                key2: authParam!
            )
            print("[GT3] [AUTH] Falling back to SET_PWD — setPwdKey: \(setPwdKey.hexString)")
            crypto.updateKey(setPwdKey)
            password = JavaLCG.generatePassword(authParam: authParam!)
            print("[GT3] [AUTH] Generated fallback password: \(password!.hexString)")
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
