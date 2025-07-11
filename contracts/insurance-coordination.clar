;; Insurance Coordination Contract
;; Provides security system documentation for coverage

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_POLICY_NOT_FOUND (err u501))
(define-constant ERR_CLAIM_NOT_FOUND (err u502))
(define-constant ERR_INVALID_STATUS (err u503))
(define-constant ERR_INSUFFICIENT_TOKENS (err u504))

;; Data Variables
(define-data-var policy-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var documentation-fee uint u20)
(define-data-var contract-paused bool false)

;; Token balances
(define-map token-balances principal uint)

;; Insurance policies
(define-map insurance-policies
  uint
  {
    policyholder: principal,
    policy-number: (string-ascii 50),
    provider: (string-ascii 100),
    coverage-type: (string-ascii 50),
    premium-discount: uint,
    security-score: uint,
    registration-date: uint,
    expiry-date: uint,
    active: bool
  }
)

;; Security compliance records
(define-map compliance-records
  uint
  {
    policy-id: uint,
    device-count: uint,
    monitoring-active: bool,
    emergency-contacts: bool,
    access-control: bool,
    community-participation: bool,
    last-inspection: uint,
    compliance-score: uint
  }
)

;; Insurance claims
(define-map insurance-claims
  uint
  {
    policy-id: uint,
    claimant: principal,
    incident-type: (string-ascii 50),
    incident-date: uint,
    claim-amount: uint,
    description: (string-ascii 300),
    status: (string-ascii 20),
    filed-date: uint,
    supporting-evidence: (string-ascii 200)
  }
)

;; Premium calculation factors
(define-map premium-factors
  principal
  {
    base-premium: uint,
    security-discount: uint,
    community-discount: uint,
    claim-history-penalty: uint,
    final-premium: uint,
    last-calculation: uint
  }
)

;; Security incident documentation
(define-map security-incidents
  uint
  {
    policy-id: uint,
    incident-type: (string-ascii 50),
    severity: uint,
    timestamp: uint,
    response-time: (optional uint),
    damages: uint,
    resolved: bool,
    documentation: (string-ascii 300)
  }
)

(define-data-var incident-counter uint u0)

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

;; Register insurance policy
(define-public (register-policy
  (policy-number (string-ascii 50))
  (provider (string-ascii 100))
  (coverage-type (string-ascii 50))
  (expiry-date uint))
  (let
    (
      (policy-id (+ (var-get policy-counter) u1))
      (user-balance (default-to u0 (map-get? token-balances tx-sender)))
      (fee (var-get documentation-fee))
    )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (>= user-balance fee) ERR_INSUFFICIENT_TOKENS)

    ;; Deduct documentation fee
    (map-set token-balances tx-sender (- user-balance fee))

    ;; Register policy
    (map-set insurance-policies policy-id {
      policyholder: tx-sender,
      policy-number: policy-number,
      provider: provider,
      coverage-type: coverage-type,
      premium-discount: u0,
      security-score: u0,
      registration-date: block-height,
      expiry-date: expiry-date,
      active: true
    })

    ;; Initialize compliance record
    (map-set compliance-records policy-id {
      policy-id: policy-id,
      device-count: u0,
      monitoring-active: false,
      emergency-contacts: false,
      access-control: false,
      community-participation: false,
      last-inspection: block-height,
      compliance-score: u0
    })

    (var-set policy-counter policy-id)
    (ok policy-id)
  )
)

;; Update compliance status
(define-public (update-compliance
  (policy-id uint)
  (device-count uint)
  (monitoring-active bool)
  (emergency-contacts bool)
  (access-control bool)
  (community-participation bool))
  (let ((policy (unwrap! (map-get? insurance-policies policy-id) ERR_POLICY_NOT_FOUND)))
    (asserts! (is-eq (get policyholder policy) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

    ;; Calculate compliance score
    (let ((score (+
      (if monitoring-active u20 u0)
      (if emergency-contacts u20 u0)
      (if access-control u20 u0)
      (if community-participation u20 u0)
      (if (> device-count u2) u20 u0))))

      (map-set compliance-records policy-id {
        policy-id: policy-id,
        device-count: device-count,
        monitoring-active: monitoring-active,
        emergency-contacts: emergency-contacts,
        access-control: access-control,
        community-participation: community-participation,
        last-inspection: block-height,
        compliance-score: score
      })

      ;; Update policy security score
      (map-set insurance-policies policy-id (merge policy {
        security-score: score,
        premium-discount: (/ score u5)
      }))
    )
    (ok true)
  )
)

;; File insurance claim
(define-public (file-claim
  (policy-id uint)
  (incident-type (string-ascii 50))
  (incident-date uint)
  (claim-amount uint)
  (description (string-ascii 300))
  (supporting-evidence (string-ascii 200)))
  (let
    (
      (policy (unwrap! (map-get? insurance-policies policy-id) ERR_POLICY_NOT_FOUND))
      (claim-id (+ (var-get claim-counter) u1))
    )
    (asserts! (is-eq (get policyholder policy) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (get active policy) ERR_UNAUTHORIZED)

    (map-set insurance-claims claim-id {
      policy-id: policy-id,
      claimant: tx-sender,
      incident-type: incident-type,
      incident-date: incident-date,
      claim-amount: claim-amount,
      description: description,
      status: "filed",
      filed-date: block-height,
      supporting-evidence: supporting-evidence
    })

    (var-set claim-counter claim-id)
    (ok claim-id)
  )
)

;; Document security incident
(define-public (document-incident
  (policy-id uint)
  (incident-type (string-ascii 50))
  (severity uint)
  (damages uint)
  (documentation (string-ascii 300)))
  (let
    (
      (policy (unwrap! (map-get? insurance-policies policy-id) ERR_POLICY_NOT_FOUND))
      (incident-id (+ (var-get incident-counter) u1))
    )
    (asserts! (is-eq (get policyholder policy) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (<= severity u10) ERR_INVALID_STATUS)

    (map-set security-incidents incident-id {
      policy-id: policy-id,
      incident-type: incident-type,
      severity: severity,
      timestamp: block-height,
      response-time: none,
      damages: damages,
      resolved: false,
      documentation: documentation
    })

    (var-set incident-counter incident-id)
    (ok incident-id)
  )
)

;; Calculate premium factors
(define-public (calculate-premium (policy-id uint) (base-premium uint))
  (let
    (
      (policy (unwrap! (map-get? insurance-policies policy-id) ERR_POLICY_NOT_FOUND))
      (compliance (unwrap! (map-get? compliance-records policy-id) ERR_POLICY_NOT_FOUND))
    )
    (asserts! (is-eq (get policyholder policy) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

    (let
      (
        (security-discount (/ (* base-premium (get compliance-score compliance)) u500))
        (community-discount (if (get community-participation compliance) (/ base-premium u20) u0))
        (final-premium (- base-premium (+ security-discount community-discount)))
      )
      (map-set premium-factors tx-sender {
        base-premium: base-premium,
        security-discount: security-discount,
        community-discount: community-discount,
        claim-history-penalty: u0,
        final-premium: final-premium,
        last-calculation: block-height
      })
      (ok final-premium)
    )
  )
)

;; Update claim status
(define-public (update-claim-status (claim-id uint) (new-status (string-ascii 20)))
  (let ((claim (unwrap! (map-get? insurance-claims claim-id) ERR_CLAIM_NOT_FOUND)))
    (asserts! (is-eq (get claimant claim) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

    (map-set insurance-claims claim-id (merge claim {
      status: new-status
    }))
    (ok true)
  )
)

;; Resolve security incident
(define-public (resolve-incident (incident-id uint) (response-time uint))
  (let ((incident (unwrap! (map-get? security-incidents incident-id) ERR_CLAIM_NOT_FOUND)))
    (let ((policy (unwrap! (map-get? insurance-policies (get policy-id incident)) ERR_POLICY_NOT_FOUND)))
      (asserts! (is-eq (get policyholder policy) tx-sender) ERR_UNAUTHORIZED)
      (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)

      (map-set security-incidents incident-id (merge incident {
        response-time: (some response-time),
        resolved: true
      }))
      (ok true)
    )
  )
)

;; Read-only functions

(define-read-only (get-insurance-policy (policy-id uint))
  (map-get? insurance-policies policy-id)
)

(define-read-only (get-compliance-record (policy-id uint))
  (map-get? compliance-records policy-id)
)

(define-read-only (get-insurance-claim (claim-id uint))
  (map-get? insurance-claims claim-id)
)

(define-read-only (get-security-incident (incident-id uint))
  (map-get? security-incidents incident-id)
)

(define-read-only (get-premium-factors (user principal))
  (map-get? premium-factors user)
)

(define-read-only (get-token-balance (user principal))
  (default-to u0 (map-get? token-balances user))
)

(define-read-only (get-documentation-fee)
  (var-get documentation-fee)
)

(define-read-only (get-policy-count)
  (var-get policy-counter)
)

(define-read-only (get-claim-count)
  (var-get claim-counter)
)

;; Admin functions

(define-public (set-documentation-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set documentation-fee new-fee)
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
