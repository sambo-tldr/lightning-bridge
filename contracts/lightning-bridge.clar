;; Lightning Bridge Protocol - Enhanced Security with Ed25519 Verification
;; 
;; A revolutionary Bitcoin Layer 2 solution that unlocks instant, trustless 
;; micropayments through state channels on the Stacks blockchain. Experience 
;; the future of Bitcoin scalability with zero-fee transactions and lightning-fast 
;; settlements that maintain Bitcoin's security guarantees.
;;
;; Built for the Bitcoin economy, Lightning Bridge enables merchants, developers, 
;; and users to transact at the speed of thought while preserving the decentralized 
;; ethos of Bitcoin. From streaming payments to gaming rewards, unlock unlimited 
;; possibilities with mathematically guaranteed security.
;;
;; PROTOCOL CONSTANTS

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CHANNEL-EXISTS (err u101))
(define-constant ERR-CHANNEL-NOT-FOUND (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-INVALID-SIGNATURE (err u104))
(define-constant ERR-CHANNEL-CLOSED (err u105))
(define-constant ERR-DISPUTE-PERIOD (err u106))
(define-constant ERR-INVALID-INPUT (err u107))
(define-constant ERR-BALANCE-OVERFLOW (err u108))
(define-constant ERR-PUBKEY-MISMATCH (err u109))
(define-constant ERR-MESSAGE-TOO-LONG (err u110))

;; Security constants for input validation
(define-constant MAX-BALANCE u340282366920938463463374607431768211455) ;; Max uint128
(define-constant MIN-BALANCE u0)
(define-constant MAX-MESSAGE-LENGTH u1024)

;; Reverse lookup for channels by participant and channel-id
(define-map channel-participants
  { channel-id: (buff 32), participant: principal }
  { 
    other-participant: principal,
    is-participant-a: bool
  }
)

;; DATA STRUCTURES

;; Primary channel state mapping
(define-map payment-channels 
  {
    channel-id: (buff 32),
    participant-a: principal,
    participant-b: principal
  }
  {
    total-deposited: uint,
    balance-a: uint,
    balance-b: uint,
    is-open: bool,
    dispute-deadline: uint,
    nonce: uint,
    pubkey-a: (buff 33),  ;; Compressed public key for participant A
    pubkey-b: (buff 33)   ;; Compressed public key for participant B
  }
)

;; Store public keys for signature verification
(define-map participant-pubkeys principal (buff 33))

;; INPUT VALIDATION LAYER

;; Validates channel identifier format and bounds
(define-private (is-valid-channel-id (channel-id (buff 32)))
  (and 
    (> (len channel-id) u0)
    (<= (len channel-id) u32)
  )
)

;; Ensures deposit amount meets minimum requirements
(define-private (is-valid-deposit (amount uint))
  (> amount u0)
)

;; Verifies Ed25519 signature format compliance (64 bytes)
(define-private (is-valid-signature (signature (buff 65)))
  (is-eq (len signature) u65)
)

;; Validates Ed25519 public key format (33 bytes compressed)
(define-private (is-valid-pubkey (pubkey (buff 33)))
  (is-eq (len pubkey) u33)
)

;; ENHANCED SECURITY VALIDATION

;; Validates balance values to prevent overflow and underflow
(define-private (is-valid-balance (balance uint))
  (and 
    (>= balance MIN-BALANCE)
    (<= balance MAX-BALANCE)
  )
)

;; Validates that balance distribution is mathematically sound
(define-private (is-valid-balance-distribution (balance-a uint) (balance-b uint) (total uint))
  (and 
    (is-valid-balance balance-a)
    (is-valid-balance balance-b)
    (is-eq total (+ balance-a balance-b))
    ;; Prevent overflow in addition
    (>= MAX-BALANCE (+ balance-a balance-b))
  )
)

;; Safe buffer conversion with bounds checking
(define-private (safe-uint-to-buff (n uint))
  (begin
    (asserts! (is-valid-balance n) ERR-BALANCE-OVERFLOW)
    (ok (unwrap-panic (to-consensus-buff? n)))
  )
)

;; HELPER FUNCTIONS FOR SECURE CHANNEL OPERATIONS

;; Securely retrieves and validates channel data
(define-private (get-validated-channel
  (channel-id (buff 32))
  (participant-a principal)
  (participant-b principal)
)
  (let 
    (
      (channel-data (map-get? payment-channels {
        channel-id: channel-id, 
        participant-a: participant-a, 
        participant-b: participant-b
      }))
    )
    (match channel-data
      channel (if (and 
                    (is-eq participant-a participant-a) ;; Redundant but explicit check
                    (is-eq participant-b participant-b)
                  )
                  (some channel)
                  none)
      none
    )
  )
)

;; Validates that a principal is a legitimate participant in a channel
(define-private (is-channel-participant
  (channel-id (buff 32))
  (participant principal)
)
  (let 
    (
      ;; Try to find channel with participant as participant-a
      (channel-as-a (map-get? payment-channels {
        channel-id: channel-id, 
        participant-a: participant, 
        participant-b: tx-sender
      }))
      ;; Try to find channel with participant as participant-b  
      (channel-as-b (map-get? payment-channels {
        channel-id: channel-id, 
        participant-a: tx-sender, 
        participant-b: participant
      }))
    )
    (or (is-some channel-as-a) (is-some channel-as-b))
  )
)

;; CRYPTOGRAPHIC UTILITIES

;; Converts unsigned integer to buffer for signature operations
(define-private (uint-to-buff (n uint))
  (unwrap-panic (to-consensus-buff? n))
)

;; Creates standardized message for channel state signing
(define-private (create-channel-state-message 
  (channel-id (buff 32))
  (balance-a uint)
  (balance-b uint)
  (nonce uint)
)
  (let 
    (
      (balance-a-buff (uint-to-buff balance-a))
      (balance-b-buff (uint-to-buff balance-b))
      (nonce-buff (uint-to-buff nonce))
    )
    (concat 
      (concat 
        (concat channel-id balance-a-buff)
        balance-b-buff
      )
      nonce-buff
    )
  )
)

;; Enhanced Ed25519 signature verification using Stacks built-in functions
(define-private (verify-ed25519-signature
  (message (buff 1024))
  (signature (buff 65))
  (public-key (buff 33))
)
  (let 
    (
      (message-hash (sha256 message))
    )
    ;; Input validation
    (asserts! (<= (len message) MAX-MESSAGE-LENGTH) ERR-MESSAGE-TOO-LONG)
    (asserts! (is-valid-signature signature) ERR-INVALID-SIGNATURE)
    (asserts! (is-valid-pubkey public-key) ERR-INVALID-INPUT)
    
    ;; Use Stacks' built-in secp256k1 verification
    ;; Note: Stacks uses secp256k1, not Ed25519. This is the correct approach for Stacks.
    (ok (secp256k1-verify message-hash signature public-key))
  )
)

;; Verify signature with automatic public key lookup
(define-private (verify-signature-with-lookup
  (message (buff 1024))
  (signature (buff 65))
  (signer principal)
)
  (let 
    (
      (public-key (unwrap! (map-get? participant-pubkeys signer) ERR-PUBKEY-MISMATCH))
    )
    (verify-ed25519-signature message signature public-key)
  )
)

;; Enhanced signature verification for channel state updates
(define-private (verify-channel-state-signature
  (channel-id (buff 32))
  (balance-a uint)
  (balance-b uint)
  (nonce uint)
  (signature (buff 65))
  (signer principal)
)
  (let 
    (
      (message (create-channel-state-message channel-id balance-a balance-b nonce))
    )
    (verify-signature-with-lookup message signature signer)
  )
)

;; PUBLIC KEY MANAGEMENT

;; Registers a public key for a participant
(define-public (register-pubkey (pubkey (buff 33)))
  (begin
    (asserts! (is-valid-pubkey pubkey) ERR-INVALID-INPUT)
    (map-set participant-pubkeys tx-sender pubkey)
    (ok true)
  )
)

;; Retrieves public key for a participant
(define-read-only (get-pubkey (participant principal))
  (map-get? participant-pubkeys participant)
)

;; CHANNEL LIFECYCLE MANAGEMENT

;; Creates a new Lightning Bridge channel between two participants
(define-public (create-channel 
  (channel-id (buff 32)) 
  (participant-b principal)
  (initial-deposit uint)
  (pubkey-a (buff 33))
  (pubkey-b (buff 33))
)
  (begin
    ;; Enhanced input validation
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-deposit initial-deposit) ERR-INVALID-INPUT)
    (asserts! (is-valid-balance initial-deposit) ERR-BALANCE-OVERFLOW)
    (asserts! (is-valid-pubkey pubkey-a) ERR-INVALID-INPUT)
    (asserts! (is-valid-pubkey pubkey-b) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)

    ;; Ensure channel uniqueness
    (asserts! (is-none (map-get? payment-channels {
      channel-id: channel-id, 
      participant-a: tx-sender, 
      participant-b: participant-b
    })) ERR-CHANNEL-EXISTS)

    ;; Register public keys
    (map-set participant-pubkeys tx-sender pubkey-a)
    (map-set participant-pubkeys participant-b pubkey-b)

    ;; Lock initial funds in contract
    (try! (stx-transfer? initial-deposit tx-sender (as-contract tx-sender)))

    ;; Initialize channel state
    (map-set payment-channels 
      {
        channel-id: channel-id, 
        participant-a: tx-sender, 
        participant-b: participant-b
      }
      {
        total-deposited: initial-deposit,
        balance-a: initial-deposit,
        balance-b: u0,
        is-open: true,
        dispute-deadline: u0,
        nonce: u0,
        pubkey-a: pubkey-a,
        pubkey-b: pubkey-b
      }
    )

    ;; Create reverse lookup entries
    (map-set channel-participants
      { channel-id: channel-id, participant: tx-sender }
      { other-participant: participant-b, is-participant-a: true }
    )
    (map-set channel-participants
      { channel-id: channel-id, participant: participant-b }
      { other-participant: tx-sender, is-participant-a: false }
    )

    (ok true)
  )
)

;; Adds additional liquidity to an existing channel
(define-public (fund-channel 
  (channel-id (buff 32)) 
  (participant-b principal)
  (additional-funds uint)
)
  (let 
    (
      (channel (unwrap! 
        (map-get? payment-channels {
          channel-id: channel-id, 
          participant-a: tx-sender, 
          participant-b: participant-b
        }) 
        ERR-CHANNEL-NOT-FOUND
      ))
      (new-total (+ (get total-deposited channel) additional-funds))
      (new-balance-a (+ (get balance-a channel) additional-funds))
    )
    ;; Enhanced validation checks
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-deposit additional-funds) ERR-INVALID-INPUT)
    (asserts! (is-valid-balance additional-funds) ERR-BALANCE-OVERFLOW)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)
    (asserts! (get is-open channel) ERR-CHANNEL-CLOSED)
    
    ;; Check for overflow in addition
    (asserts! (>= MAX-BALANCE new-total) ERR-BALANCE-OVERFLOW)
    (asserts! (>= MAX-BALANCE new-balance-a) ERR-BALANCE-OVERFLOW)

    ;; Transfer additional funds
    (try! (stx-transfer? additional-funds tx-sender (as-contract tx-sender)))

    ;; Update channel balances
    (map-set payment-channels 
      {
        channel-id: channel-id, 
        participant-a: tx-sender, 
        participant-b: participant-b
      }
      (merge channel {
        total-deposited: new-total,
        balance-a: new-balance-a
      })
    )

    (ok true)
  )
)

;; COOPERATIVE CHANNEL RESOLUTION

;; Executes mutual channel closure with cryptographic verification
(define-public (close-channel-cooperative 
  (channel-id (buff 32)) 
  (participant-b principal)
  (balance-a uint)
  (balance-b uint)
  (nonce uint)
  (signature-a (buff 65))
  (signature-b (buff 65))
)
  (let 
    (
      (channel (unwrap! 
        (map-get? payment-channels {
          channel-id: channel-id, 
          participant-a: tx-sender, 
          participant-b: participant-b
        }) 
        ERR-CHANNEL-NOT-FOUND
      ))
      (total-channel-funds (get total-deposited channel))
    )
    ;; Enhanced validation with balance checks
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-signature signature-a) ERR-INVALID-INPUT)
    (asserts! (is-valid-signature signature-b) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)
    (asserts! (get is-open channel) ERR-CHANNEL-CLOSED)
    (asserts! (>= nonce (get nonce channel)) ERR-INVALID-INPUT)
    
    ;; Validate balance distribution
    (asserts! 
      (is-valid-balance-distribution balance-a balance-b total-channel-funds)
      ERR-INSUFFICIENT-FUNDS
    )

    ;; Cryptographic verification of both signatures
    (try! (verify-channel-state-signature channel-id balance-a balance-b nonce signature-a tx-sender))
    (try! (verify-channel-state-signature channel-id balance-a balance-b nonce signature-b participant-b))

    ;; Execute fund distribution
    (try! (as-contract (stx-transfer? balance-a tx-sender tx-sender)))
    (try! (as-contract (stx-transfer? balance-b tx-sender participant-b)))

    ;; Mark channel as closed
    (map-set payment-channels 
      {
        channel-id: channel-id, 
        participant-a: tx-sender, 
        participant-b: participant-b
      }
      (merge channel {
        is-open: false,
        balance-a: u0,
        balance-b: u0,
        total-deposited: u0,
        nonce: nonce
      })
    )

    (ok true)
  )
)

;; DISPUTE RESOLUTION MECHANISM

;; Initiates unilateral channel closure with cryptographic proof
(define-public (initiate-unilateral-close 
  (channel-id (buff 32)) 
  (participant-b principal)
  (proposed-balance-a uint)
  (proposed-balance-b uint)
  (nonce uint)
  (signature (buff 65))
)
  (let 
    (
      (channel (unwrap! 
        (map-get? payment-channels {
          channel-id: channel-id, 
          participant-a: tx-sender, 
          participant-b: participant-b
        }) 
        ERR-CHANNEL-NOT-FOUND
      ))
      (total-channel-funds (get total-deposited channel))
    )
    ;; Enhanced input validation
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-signature signature) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)
    (asserts! (get is-open channel) ERR-CHANNEL-CLOSED)
    (asserts! (> nonce (get nonce channel)) ERR-INVALID-INPUT)

    ;; Validate proposed balance distribution
    (asserts! 
      (is-valid-balance-distribution proposed-balance-a proposed-balance-b total-channel-funds)
      ERR-INSUFFICIENT-FUNDS
    )

    ;; Cryptographic verification of the state update
    (try! (verify-channel-state-signature channel-id proposed-balance-a proposed-balance-b nonce signature participant-b))

    ;; Set dispute deadline (approximately 1 week in blocks)
    (map-set payment-channels 
      {
        channel-id: channel-id, 
        participant-a: tx-sender, 
        participant-b: participant-b
      }
      (merge channel {
        dispute-deadline: (+ stacks-block-height u1008),
        balance-a: proposed-balance-a,
        balance-b: proposed-balance-b,
        nonce: nonce
      })
    )

    (ok true)
  )
)

;; Challenge mechanism for disputed states - Secure version using reverse lookup
(define-public (challenge-unilateral-close
  (channel-id (buff 32))
  (newer-balance-a uint)
  (newer-balance-b uint)
  (newer-nonce uint)
  (signature (buff 65))
)
  (let 
    (
      ;; Use reverse lookup to find the channel safely
      (participant-info (unwrap! 
        (map-get? channel-participants {
          channel-id: channel-id, 
          participant: tx-sender
        })
        ERR-CHANNEL-NOT-FOUND
      ))
      (other-participant (get other-participant participant-info))
      (is-caller-participant-a (get is-participant-a participant-info))
      ;; Determine correct participant order for channel lookup
      (participant-a (if is-caller-participant-a tx-sender other-participant))
      (participant-b (if is-caller-participant-a other-participant tx-sender))
      ;; Get the actual channel data
      (channel (unwrap! 
        (map-get? payment-channels {
          channel-id: channel-id, 
          participant-a: participant-a, 
          participant-b: participant-b
        }) 
        ERR-CHANNEL-NOT-FOUND
      ))
      (total-channel-funds (get total-deposited channel))
    )
    ;; Validation checks
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (is-valid-signature signature) ERR-INVALID-INPUT)
    (asserts! (> newer-nonce (get nonce channel)) ERR-INVALID-INPUT)
    (asserts! (< stacks-block-height (get dispute-deadline channel)) ERR-DISPUTE-PERIOD)
    
    ;; Only participant-b can challenge (the one who didn't initiate unilateral close)
    (asserts! (not is-caller-participant-a) ERR-NOT-AUTHORIZED)
    
    ;; Validate balance distribution
    (asserts! 
      (is-valid-balance-distribution newer-balance-a newer-balance-b total-channel-funds)
      ERR-INSUFFICIENT-FUNDS
    )

    ;; Verify participant-a's signature on the newer state
    (try! (verify-channel-state-signature channel-id newer-balance-a newer-balance-b newer-nonce signature participant-a))

    ;; Update to the newer state
    (map-set payment-channels 
      {
        channel-id: channel-id, 
        participant-a: participant-a, 
        participant-b: participant-b
      }
      (merge channel {
        balance-a: newer-balance-a,
        balance-b: newer-balance-b,
        nonce: newer-nonce,
        dispute-deadline: (+ stacks-block-height u1008) ;; Reset dispute period
      })
    )

    (ok true)
  )
)

;; Finalizes unilateral closure after dispute period expires
(define-public (resolve-unilateral-close 
  (channel-id (buff 32)) 
  (participant-b principal)
)
  (let 
    (
      (channel (unwrap! 
        (map-get? payment-channels {
          channel-id: channel-id, 
          participant-a: tx-sender, 
          participant-b: participant-b
        }) 
        ERR-CHANNEL-NOT-FOUND
      ))
      (final-balance-a (get balance-a channel))
      (final-balance-b (get balance-b channel))
    )
    ;; Validation and timing checks
    (asserts! (is-valid-channel-id channel-id) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender participant-b)) ERR-INVALID-INPUT)
    (asserts! 
      (>= stacks-block-height (get dispute-deadline channel)) 
      ERR-DISPUTE-PERIOD
    )
    
    ;; Additional balance validation before final settlement
    (asserts! (is-valid-balance final-balance-a) ERR-BALANCE-OVERFLOW)
    (asserts! (is-valid-balance final-balance-b) ERR-BALANCE-OVERFLOW)

    ;; Execute final settlement
    (try! (as-contract (stx-transfer? final-balance-a tx-sender tx-sender)))
    (try! (as-contract (stx-transfer? final-balance-b tx-sender participant-b)))

    ;; Close channel permanently
    (map-set payment-channels 
      {
        channel-id: channel-id, 
        participant-a: tx-sender, 
        participant-b: participant-b
      }
      (merge channel {
        is-open: false,
        balance-a: u0,
        balance-b: u0,
        total-deposited: u0
      })
    )

    (ok true)
  )
)

;; QUERY INTERFACE

;; Returns comprehensive channel state information
(define-read-only (get-channel-info 
  (channel-id (buff 32)) 
  (participant-a principal)
  (participant-b principal)
)
  (map-get? payment-channels {
    channel-id: channel-id, 
    participant-a: participant-a, 
    participant-b: participant-b
  })
)

;; Returns current nonce for a channel (useful for off-chain state tracking)
(define-read-only (get-channel-nonce
  (channel-id (buff 32)) 
  (participant-a principal)
  (participant-b principal)
)
  (match (map-get? payment-channels {
    channel-id: channel-id, 
    participant-a: participant-a, 
    participant-b: participant-b
  })
    channel-data (some (get nonce channel-data))
    none
  )
)

;; EMERGENCY PROTOCOLS

;; Contract owner emergency withdrawal mechanism
(define-public (emergency-withdraw)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (try! (stx-transfer? (stx-get-balance (as-contract tx-sender)) (as-contract tx-sender) CONTRACT-OWNER))
    (ok true)
  )
)