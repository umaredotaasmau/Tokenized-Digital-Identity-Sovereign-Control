;; Data Sovereignty Contract
;; Ensures complete user control over personal data

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_DATA_NOT_FOUND (err u301))
(define-constant ERR_ACCESS_DENIED (err u302))
(define-constant ERR_INVALID_DURATION (err u303))

;; Data structures
(define-map data-records
  { identity-id: (buff 32), data-category: (string-ascii 50) }
  {
    owner: principal,
    data-hash: (buff 32),
    encryption-key-hash: (buff 32),
    created-at: uint,
    last-accessed: uint,
    access-count: uint,
    metadata: (string-ascii 256)
  }
)

(define-map data-access-permissions
  { identity-id: (buff 32), data-category: (string-ascii 50), accessor: principal }
  {
    granted-at: uint,
    expires-at: uint,
    access-level: (string-ascii 20),
    purpose: (string-ascii 100),
    conditions: (string-ascii 200)
  }
)

(define-map access-audit-log
  { identity-id: (buff 32), access-id: uint }
  {
    accessor: principal,
    data-category: (string-ascii 50),
    access-type: (string-ascii 20),
    timestamp: uint,
    ip-hash: (buff 32),
    success: bool
  }
)

(define-data-var next-access-id uint u1)

;; Public functions

;; Initialize data control for an identity
(define-public (initialize-data-control (identity-id (buff 32)) (owner principal))
  (begin
    (print { event: "data-control-initialized", identity-id: identity-id, owner: owner })
    (ok true)
  )
)

;; Store encrypted data
(define-public (store-data
  (identity-id (buff 32))
  (data-category (string-ascii 50))
  (data-hash (buff 32))
  (encryption-key-hash (buff 32))
  (metadata (string-ascii 256))
)
  (begin
    (map-set data-records
      { identity-id: identity-id, data-category: data-category }
      {
        owner: tx-sender,
        data-hash: data-hash,
        encryption-key-hash: encryption-key-hash,
        created-at: block-height,
        last-accessed: block-height,
        access-count: u1,
        metadata: metadata
      }
    )
    (print { event: "data-stored", identity-id: identity-id, category: data-category })
    (ok true)
  )
)

;; Grant data access permission
(define-public (grant-access
  (identity-id (buff 32))
  (data-category (string-ascii 50))
  (accessor principal)
  (duration uint)
  (access-level (string-ascii 20))
  (purpose (string-ascii 100))
)
  (let ((data-record (unwrap! (map-get? data-records { identity-id: identity-id, data-category: data-category }) ERR_DATA_NOT_FOUND)))
    (if (is-eq (get owner data-record) tx-sender)
      (begin
        (map-set data-access-permissions
          { identity-id: identity-id, data-category: data-category, accessor: accessor }
          {
            granted-at: block-height,
            expires-at: (+ block-height duration),
            access-level: access-level,
            purpose: purpose,
            conditions: ""
          }
        )
        (print { event: "access-granted", identity-id: identity-id, category: data-category, accessor: accessor })
        (ok true)
      )
      ERR_UNAUTHORIZED
    )
  )
)

;; Revoke data access permission
(define-public (revoke-access
  (identity-id (buff 32))
  (data-category (string-ascii 50))
  (accessor principal)
)
  (let ((data-record (unwrap! (map-get? data-records { identity-id: identity-id, data-category: data-category }) ERR_DATA_NOT_FOUND)))
    (if (is-eq (get owner data-record) tx-sender)
      (begin
        (map-delete data-access-permissions { identity-id: identity-id, data-category: data-category, accessor: accessor })
        (print { event: "access-revoked", identity-id: identity-id, category: data-category, accessor: accessor })
        (ok true)
      )
      ERR_UNAUTHORIZED
    )
  )
)

;; Access data (with permission check)
(define-public (access-data
  (identity-id (buff 32))
  (data-category (string-ascii 50))
  (access-type (string-ascii 20))
)
  (let (
    (data-record (unwrap! (map-get? data-records { identity-id: identity-id, data-category: data-category }) ERR_DATA_NOT_FOUND))
    (permission (map-get? data-access-permissions { identity-id: identity-id, data-category: data-category, accessor: tx-sender }))
    (access-id (var-get next-access-id))
  )
    (if (or
      (is-eq (get owner data-record) tx-sender)
      (and
        (is-some permission)
        (> (get expires-at (unwrap-panic permission)) block-height)
      )
    )
      (begin
        ;; Update access count and timestamp
        (map-set data-records
          { identity-id: identity-id, data-category: data-category }
          (merge data-record {
            last-accessed: block-height,
            access-count: (+ (get access-count data-record) u1)
          })
        )

        ;; Log access
        (map-set access-audit-log
          { identity-id: identity-id, access-id: access-id }
          {
            accessor: tx-sender,
            data-category: data-category,
            access-type: access-type,
            timestamp: block-height,
            ip-hash: 0x00, ;; Would be populated by oracle in real implementation
            success: true
          }
        )

        (var-set next-access-id (+ access-id u1))
        (print { event: "data-accessed", identity-id: identity-id, category: data-category, accessor: tx-sender })
        (ok (get data-hash data-record))
      )
      (begin
        ;; Log failed access attempt
        (map-set access-audit-log
          { identity-id: identity-id, access-id: access-id }
          {
            accessor: tx-sender,
            data-category: data-category,
            access-type: access-type,
            timestamp: block-height,
            ip-hash: 0x00,
            success: false
          }
        )
        (var-set next-access-id (+ access-id u1))
        ERR_ACCESS_DENIED
      )
    )
  )
)

;; Update data
(define-public (update-data
  (identity-id (buff 32))
  (data-category (string-ascii 50))
  (new-data-hash (buff 32))
  (new-metadata (string-ascii 256))
)
  (let ((data-record (unwrap! (map-get? data-records { identity-id: identity-id, data-category: data-category }) ERR_DATA_NOT_FOUND)))
    (if (is-eq (get owner data-record) tx-sender)
      (begin
        (map-set data-records
          { identity-id: identity-id, data-category: data-category }
          (merge data-record {
            data-hash: new-data-hash,
            metadata: new-metadata,
            last-accessed: block-height
          })
        )
        (print { event: "data-updated", identity-id: identity-id, category: data-category })
        (ok true)
      )
      ERR_UNAUTHORIZED
    )
  )
)

;; Read-only functions

;; Get data record
(define-read-only (get-data-record (identity-id (buff 32)) (data-category (string-ascii 50)))
  (map-get? data-records { identity-id: identity-id, data-category: data-category })
)

;; Check access permission
(define-read-only (has-access-permission (identity-id (buff 32)) (data-category (string-ascii 50)) (accessor principal))
  (match (map-get? data-access-permissions { identity-id: identity-id, data-category: data-category, accessor: accessor })
    permission (> (get expires-at permission) block-height)
    false
  )
)

;; Get access audit entry
(define-read-only (get-access-audit (identity-id (buff 32)) (access-id uint))
  (map-get? access-audit-log { identity-id: identity-id, access-id: access-id })
)

;; Get data access count
(define-read-only (get-access-count (identity-id (buff 32)) (data-category (string-ascii 50)))
  (match (map-get? data-records { identity-id: identity-id, data-category: data-category })
    record (get access-count record)
    u0
  )
)
