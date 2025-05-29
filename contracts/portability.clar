;; Portability Contract
;; Enables seamless identity migration between platforms

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_MIGRATION_NOT_FOUND (err u401))
(define-constant ERR_INVALID_STATE (err u402))
(define-constant ERR_MIGRATION_EXPIRED (err u403))

;; Data structures
(define-map migration-requests
  { migration-id: (buff 32) }
  {
    identity-id: (buff 32),
    requester: principal,
    source-platform: (string-ascii 100),
    destination-platform: (string-ascii 100),
    initiated-at: uint,
    status: (string-ascii 20),
    data-package-hash: (buff 32),
    verification-hash: (buff 32),
    expires-at: uint
  }
)

(define-map migration-approvals
  { migration-id: (buff 32), approver: principal }
  {
    approved-at: uint,
    signature-hash: (buff 32),
    conditions: (string-ascii 200)
  }
)

(define-map platform-integrations
  { platform-id: (string-ascii 100) }
  {
    platform-address: principal,
    integration-type: (string-ascii 50),
    supported-features: (list 10 (string-ascii 50)),
    verified: bool,
    registered-at: uint
  }
)

(define-data-var migration-counter uint u0)

;; Public functions

;; Register a platform for identity portability
(define-public (register-platform
  (platform-id (string-ascii 100))
  (platform-address principal)
  (integration-type (string-ascii 50))
  (supported-features (list 10 (string-ascii 50)))
)
  (begin
    (map-set platform-integrations
      { platform-id: platform-id }
      {
        platform-address: platform-address,
        integration-type: integration-type,
        supported-features: supported-features,
        verified: false,
        registered-at: block-height
      }
    )
    (print { event: "platform-registered", platform-id: platform-id, address: platform-address })
    (ok true)
  )
)

;; Initiate identity migration
(define-public (initiate-migration
  (identity-id (buff 32))
  (destination-platform (string-ascii 100))
)
  (let (
    (migration-id (hash160 (concat identity-id (unwrap-panic (to-consensus-buff? block-height)))))
    (current-counter (var-get migration-counter))
  )
    (map-set migration-requests
      { migration-id: migration-id }
      {
        identity-id: identity-id,
        requester: tx-sender,
        source-platform: "stacks",
        destination-platform: destination-platform,
        initiated-at: block-height,
        status: "initiated",
        data-package-hash: 0x00,
        verification-hash: 0x00,
        expires-at: (+ block-height u1440) ;; 24 hours
      }
    )
    (var-set migration-counter (+ current-counter u1))
    (print { event: "migration-initiated", migration-id: migration-id, identity-id: identity-id, destination: destination-platform })
    (ok migration-id)
  )
)

;; Package data for migration
(define-public (package-migration-data
  (migration-id (buff 32))
  (data-package-hash (buff 32))
  (verification-hash (buff 32))
)
  (let ((migration (unwrap! (map-get? migration-requests { migration-id: migration-id }) ERR_MIGRATION_NOT_FOUND)))
    (if (and
      (is-eq (get requester migration) tx-sender)
      (is-eq (get status migration) "initiated")
    )
      (begin
        (map-set migration-requests
          { migration-id: migration-id }
          (merge migration {
            status: "packaged",
            data-package-hash: data-package-hash,
            verification-hash: verification-hash
          })
        )
        (print { event: "migration-data-packaged", migration-id: migration-id })
        (ok true)
      )
      ERR_UNAUTHORIZED
    )
  )
)

;; Approve migration (multi-signature support)
(define-public (approve-migration
  (migration-id (buff 32))
  (signature-hash (buff 32))
  (conditions (string-ascii 200))
)
  (let ((migration (unwrap! (map-get? migration-requests { migration-id: migration-id }) ERR_MIGRATION_NOT_FOUND)))
    (if (> (get expires-at migration) block-height)
      (begin
        (map-set migration-approvals
          { migration-id: migration-id, approver: tx-sender }
          {
            approved-at: block-height,
            signature-hash: signature-hash,
            conditions: conditions
          }
        )
        (print { event: "migration-approved", migration-id: migration-id, approver: tx-sender })
        (ok true)
      )
      ERR_MIGRATION_EXPIRED
    )
  )
)

;; Execute migration
(define-public (execute-migration (migration-id (buff 32)))
  (let ((migration (unwrap! (map-get? migration-requests { migration-id: migration-id }) ERR_MIGRATION_NOT_FOUND)))
    (if (and
      (is-eq (get requester migration) tx-sender)
      (is-eq (get status migration) "packaged")
      (> (get expires-at migration) block-height)
    )
      (begin
        (map-set migration-requests
          { migration-id: migration-id }
          (merge migration { status: "completed" })
        )
        (print { event: "migration-executed", migration-id: migration-id, identity-id: (get identity-id migration) })
        (ok true)
      )
      ERR_INVALID_STATE
    )
  )
)

;; Cancel migration
(define-public (cancel-migration (migration-id (buff 32)))
  (let ((migration (unwrap! (map-get? migration-requests { migration-id: migration-id }) ERR_MIGRATION_NOT_FOUND)))
    (if (is-eq (get requester migration) tx-sender)
      (begin
        (map-set migration-requests
          { migration-id: migration-id }
          (merge migration { status: "cancelled" })
        )
        (print { event: "migration-cancelled", migration-id: migration-id })
        (ok true)
      )
      ERR_UNAUTHORIZED
    )
  )
)

;; Verify migration integrity
(define-public (verify-migration-integrity
  (migration-id (buff 32))
  (provided-verification-hash (buff 32))
)
  (let ((migration (unwrap! (map-get? migration-requests { migration-id: migration-id }) ERR_MIGRATION_NOT_FOUND)))
    (if (is-eq (get verification-hash migration) provided-verification-hash)
      (begin
        (print { event: "migration-verified", migration-id: migration-id })
        (ok true)
      )
      (ok false)
    )
  )
)

;; Read-only functions

;; Get migration request
(define-read-only (get-migration-request (migration-id (buff 32)))
  (map-get? migration-requests { migration-id: migration-id })
)

;; Get migration approval
(define-read-only (get-migration-approval (migration-id (buff 32)) (approver principal))
  (map-get? migration-approvals { migration-id: migration-id, approver: approver })
)

;; Get platform integration
(define-read-only (get-platform-integration (platform-id (string-ascii 100)))
  (map-get? platform-integrations { platform-id: platform-id })
)

;; Check migration status
(define-read-only (get-migration-status (migration-id (buff 32)))
  (match (map-get? migration-requests { migration-id: migration-id })
    migration (get status migration)
    "not-found"
  )
)

;; Check if platform is verified
(define-read-only (is-platform-verified (platform-id (string-ascii 100)))
  (match (map-get? platform-integrations { platform-id: platform-id })
    platform (get verified platform)
    false
  )
)
