;; Access Control Contract
;; Handles smart lock and entry system management

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_LOCK_NOT_FOUND (err u301))
(define-constant ERR_ACCESS_DENIED (err u302))
(define-constant ERR_INVALID_PERMISSION (err u303))
(define-constant ERR_INSUFFICIENT_TOKENS (err u304))

;; Data Variables
(define-data-var lock-counter uint u0)
(define-data-var access-fee uint u25)
(define-data-var contract-paused bool false)

;; Token balances
(define-map token-balances principal uint)

;; Smart lock registry
(define-map smart-locks
  uint
  {
    owner: principal,
    location: (string-ascii 100),
    lock-type: (string-ascii 50),
    status: (string-ascii 20),
    installation-block: uint,
    last-activity: uint
  }
)

;; Access permissions
(define-map access-permissions
  {lock-id: uint, user: principal}
  {
    permission-level: uint,
    granted-by: principal,
    granted-at: uint,
    expires-at: (optional uint),
    active: bool
  }
)

;; User lock ownership
(define-map user-locks principal (list 20 uint))

;; Access logs
(define-map access-logs
  uint
  {
    lock-id: uint,
    user: principal,
    action: (string-ascii 20),
    timestamp: uint,
    success: bool,
    method: (string-ascii 30)
  }
)

(define-data-var log-counter uint u0)

;; Temporary access codes
(define-map temp-access-codes
  {lock-id: uint, code: (string-ascii 20)}
  {
    created-by: principal,
    expires-at: uint,
    uses-remaining: uint,
    active: bool
  }
)

;; Public Functions

;; Initialize token balance
(define-public (mint-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set token-balances recipient
      (+ (default-to u0 (map-get? token-balances recipient)) amount))
    (ok amount)
  )
)

;; Register smart lock
(define-public (register-smart-lock (location (string-ascii 100)) (lock-type (string-ascii 50)))
  (let
    (
      (lock-id (+ (var-get lock-counter) u1))
      (user-balance (default-to u0 (map-get? token-balances tx-sender)))
      (fee (var-get access-fee))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (>= user-balance fee) ERR_INSUFFICIENT_TOKENS)

    ;; Deduct registration fee
    (map-set token-balances tx-sender (- user-balance fee))

    ;; Register lock
    (map-set smart-locks lock-id {
      owner: tx-sender,
      location: location,
      lock-type: lock-type,
      status: "active",
      installation-block: block-height,
      last-activity: block-height
    })

    ;; Grant owner full access
    (map-set access-permissions {lock-id: lock-id, user: tx-sender} {
      permission-level: u10,
      granted-by: tx-sender,
      granted-at: block-height,
      expires-at: none,
      active: true
    })

    ;; Update user lock list
    (let ((current-locks (default-to (list) (map-get? user-locks tx-sender))))
      (map-set user-locks tx-sender (unwrap! (as-max-len? (append current-locks lock-id) u20) ERR_UNAUTHORIZED))
    )

    (var-set lock-counter lock-id)
    (ok lock-id)
  )
)

;; Grant access permission
(define-public (grant-access (lock-id uint) (user principal) (permission-level uint) (expires-at (optional uint)))
  (let ((lock (unwrap! (map-get? smart-locks lock-id) ERR_LOCK_NOT_FOUND)))
    (asserts! (is-eq (get owner lock) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (<= permission-level u10) ERR_INVALID_PERMISSION)

    (map-set access-permissions {lock-id: lock-id, user: user} {
      permission-level: permission-level,
      granted-by: tx-sender,
      granted-at: block-height,
      expires-at: expires-at,
      active: true
    })
    (ok true)
  )
)

;; Revoke access permission
(define-public (revoke-access (lock-id uint) (user principal))
  (let ((lock (unwrap! (map-get? smart-locks lock-id) ERR_LOCK_NOT_FOUND)))
    (asserts! (is-eq (get owner lock) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

    (match (map-get? access-permissions {lock-id: lock-id, user: user})
      permission (map-set access-permissions {lock-id: lock-id, user: user}
                   (merge permission {active: false}))
      false
    )
    (ok true)
  )
)

;; Attempt access
(define-public (attempt-access (lock-id uint) (method (string-ascii 30)))
  (let
    (
      (lock (unwrap! (map-get? smart-locks lock-id) ERR_LOCK_NOT_FOUND))
      (permission (map-get? access-permissions {lock-id: lock-id, user: tx-sender}))
      (log-id (+ (var-get log-counter) u1))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

    (let ((access-granted (match permission
      perm (and (get active perm)
                (match (get expires-at perm)
                  expiry (< block-height expiry)
                  true))
      false)))

      ;; Log access attempt
      (map-set access-logs log-id {
        lock-id: lock-id,
        user: tx-sender,
        action: "access-attempt",
        timestamp: block-height,
        success: access-granted,
        method: method
      })

      ;; Update lock activity
      (if access-granted
        (map-set smart-locks lock-id (merge lock {last-activity: block-height}))
        false
      )

      (var-set log-counter log-id)

      (if access-granted
        (ok true)
        ERR_ACCESS_DENIED)
    )
  )
)

;; Create temporary access code
(define-public (create-temp-access (lock-id uint) (code (string-ascii 20)) (duration uint) (max-uses uint))
  (let ((lock (unwrap! (map-get? smart-locks lock-id) ERR_LOCK_NOT_FOUND)))
    (asserts! (is-eq (get owner lock) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

    (map-set temp-access-codes {lock-id: lock-id, code: code} {
      created-by: tx-sender,
      expires-at: (+ block-height duration),
      uses-remaining: max-uses,
      active: true
    })
    (ok true)
  )
)

;; Use temporary access code
(define-public (use-temp-access (lock-id uint) (code (string-ascii 20)))
  (let
    (
      (temp-access (unwrap! (map-get? temp-access-codes {lock-id: lock-id, code: code}) ERR_ACCESS_DENIED))
      (log-id (+ (var-get log-counter) u1))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (get active temp-access) ERR_ACCESS_DENIED)
    (asserts! (< block-height (get expires-at temp-access)) ERR_ACCESS_DENIED)
    (asserts! (> (get uses-remaining temp-access) u0) ERR_ACCESS_DENIED)

    ;; Update temp access usage
    (let ((updated-access (merge temp-access {
      uses-remaining: (- (get uses-remaining temp-access) u1)
    })))
      (map-set temp-access-codes {lock-id: lock-id, code: code}
        (if (is-eq (get uses-remaining updated-access) u0)
          (merge updated-access {active: false})
          updated-access))
    )

    ;; Log access
    (map-set access-logs log-id {
      lock-id: lock-id,
      user: tx-sender,
      action: "temp-access",
      timestamp: block-height,
      success: true,
      method: "temporary-code"
    })

    (var-set log-counter log-id)
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-smart-lock (lock-id uint))
  (map-get? smart-locks lock-id)
)

(define-read-only (get-access-permission (lock-id uint) (user principal))
  (map-get? access-permissions {lock-id: lock-id, user: user})
)

(define-read-only (get-user-locks (user principal))
  (map-get? user-locks user)
)

(define-read-only (get-access-log (log-id uint))
  (map-get? access-logs log-id)
)

(define-read-only (get-token-balance (user principal))
  (default-to u0 (map-get? token-balances user))
)

(define-read-only (get-access-fee)
  (var-get access-fee)
)

(define-read-only (get-lock-count)
  (var-get lock-counter)
)

(define-read-only (has-access (lock-id uint) (user principal))
  (match (map-get? access-permissions {lock-id: lock-id, user: user})
    permission (and (get active permission)
                    (match (get expires-at permission)
                      expiry (< block-height expiry)
                      true))
    false
  )
)

;; Admin functions

(define-public (set-access-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set access-fee new-fee)
    (ok true)
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)
