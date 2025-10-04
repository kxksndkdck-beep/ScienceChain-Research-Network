;; Research Data Registry Contract
;; Timestamp and store research data with cryptographic integrity for reproducibility verification

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_DATA (err u103))
(define-constant ERR_INVALID_STATUS (err u104))

;; Data Types
(define-constant STATUS_DRAFT u0)
(define-constant STATUS_UNDER_REVIEW u1)
(define-constant STATUS_PUBLISHED u2)
(define-constant STATUS_RETRACTED u3)
(define-constant STATUS_VERIFIED u4)

;; Data Maps
(define-map research-data
  { data-id: (string-ascii 64) }
  {
    researcher: principal,
    title: (string-utf8 200),
    data-hash: (string-ascii 64),
    timestamp: uint,
    status: uint,
    ipfs-hash: (optional (string-ascii 64)),
    metadata: (string-utf8 500),
    verification-count: uint,
    last-updated: uint
  }
)

(define-map researcher-data-count
  { researcher: principal }
  { count: uint }
)

(define-map data-verifications
  { data-id: (string-ascii 64), verifier: principal }
  { verification-hash: (string-ascii 64), timestamp: uint }
)

;; Data Variables
(define-data-var total-research-entries uint u0)
(define-data-var contract-admin principal tx-sender)

;; Private Functions
(define-private (is-valid-status (status uint))
  (or 
    (is-eq status STATUS_DRAFT)
    (is-eq status STATUS_UNDER_REVIEW)
    (is-eq status STATUS_PUBLISHED)
    (is-eq status STATUS_RETRACTED)
    (is-eq status STATUS_VERIFIED)
  )
)

(define-private (increment-researcher-count (researcher principal))
  (let 
    (
      (current-count (default-to u0 (get count (map-get? researcher-data-count { researcher: researcher }))))
    )
    (map-set researcher-data-count 
      { researcher: researcher }
      { count: (+ current-count u1) }
    )
  )
)

;; Public Functions

;; Register new research data with cryptographic hash
(define-public (register-research-data
    (data-id (string-ascii 64))
    (title (string-utf8 200))
    (data-hash (string-ascii 64))
    (ipfs-hash (optional (string-ascii 64)))
    (metadata (string-utf8 500))
  )
  (let 
    (
      (existing-data (map-get? research-data { data-id: data-id }))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (is-none existing-data) ERR_ALREADY_EXISTS)
    (asserts! (> (len data-id) u0) ERR_INVALID_DATA)
    (asserts! (> (len title) u0) ERR_INVALID_DATA)
    (asserts! (is-eq (len data-hash) u64) ERR_INVALID_DATA)
    
    (map-set research-data
      { data-id: data-id }
      {
        researcher: tx-sender,
        title: title,
        data-hash: data-hash,
        timestamp: current-timestamp,
        status: STATUS_DRAFT,
        ipfs-hash: ipfs-hash,
        metadata: metadata,
        verification-count: u0,
        last-updated: current-timestamp
      }
    )
    
    (increment-researcher-count tx-sender)
    (var-set total-research-entries (+ (var-get total-research-entries) u1))
    
    (print {
      event: "research-data-registered",
      data-id: data-id,
      researcher: tx-sender,
      timestamp: current-timestamp
    })
    
    (ok data-id)
  )
)

;; Verify the integrity of existing research data
(define-public (verify-data-integrity 
    (data-id (string-ascii 64))
    (provided-hash (string-ascii 64))
  )
  (let 
    (
      (data-info (unwrap! (map-get? research-data { data-id: data-id }) ERR_NOT_FOUND))
      (stored-hash (get data-hash data-info))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (if (is-eq stored-hash provided-hash)
      (begin
        (map-set data-verifications
          { data-id: data-id, verifier: tx-sender }
          { verification-hash: provided-hash, timestamp: current-timestamp }
        )
        
        (map-set research-data
          { data-id: data-id }
          (merge data-info { verification-count: (+ (get verification-count data-info) u1) })
        )
        
        (print {
          event: "data-integrity-verified",
          data-id: data-id,
          verifier: tx-sender,
          timestamp: current-timestamp
        })
        
        (ok true)
      )
      (ok false)
    )
  )
)

;; Retrieve metadata and verification information
(define-read-only (get-research-metadata (data-id (string-ascii 64)))
  (map-get? research-data { data-id: data-id })
)

;; Update research data status (published, under review, etc.)
(define-public (update-data-status
    (data-id (string-ascii 64))
    (new-status uint)
  )
  (let 
    (
      (data-info (unwrap! (map-get? research-data { data-id: data-id }) ERR_NOT_FOUND))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (is-eq (get researcher data-info) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-valid-status new-status) ERR_INVALID_STATUS)
    
    (map-set research-data
      { data-id: data-id }
      (merge data-info { status: new-status, last-updated: current-timestamp })
    )
    
    (print {
      event: "data-status-updated",
      data-id: data-id,
      new-status: new-status,
      researcher: tx-sender,
      timestamp: current-timestamp
    })
    
    (ok new-status)
  )
)

;; Get research data by researcher
(define-read-only (get-researcher-data-count (researcher principal))
  (default-to u0 (get count (map-get? researcher-data-count { researcher: researcher })))
)

;; Get verification info for specific data and verifier
(define-read-only (get-verification-info 
    (data-id (string-ascii 64))
    (verifier principal)
  )
  (map-get? data-verifications { data-id: data-id, verifier: verifier })
)

;; Check if data exists
(define-read-only (data-exists (data-id (string-ascii 64)))
  (is-some (map-get? research-data { data-id: data-id }))
)

;; Get total number of research entries
(define-read-only (get-total-entries)
  (var-get total-research-entries)
)

;; Get contract admin
(define-read-only (get-contract-admin)
  (var-get contract-admin)
)

;; Update IPFS hash for existing research data
(define-public (update-ipfs-hash
    (data-id (string-ascii 64))
    (new-ipfs-hash (string-ascii 64))
  )
  (let 
    (
      (data-info (unwrap! (map-get? research-data { data-id: data-id }) ERR_NOT_FOUND))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (is-eq (get researcher data-info) tx-sender) ERR_UNAUTHORIZED)
    
    (map-set research-data
      { data-id: data-id }
      (merge data-info { ipfs-hash: (some new-ipfs-hash), last-updated: current-timestamp })
    )
    
    (print {
      event: "ipfs-hash-updated",
      data-id: data-id,
      new-ipfs-hash: new-ipfs-hash,
      researcher: tx-sender,
      timestamp: current-timestamp
    })
    
    (ok new-ipfs-hash)
  )
)

