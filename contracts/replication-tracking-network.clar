;; Replication Tracking Network Contract
;; Track research replication attempts and verify reproducibility of scientific findings

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_NOT_FOUND (err u301))
(define-constant ERR_ALREADY_EXISTS (err u302))
(define-constant ERR_INVALID_DATA (err u303))
(define-constant ERR_INVALID_STATUS (err u304))
(define-constant ERR_INVALID_OUTCOME (err u305))

;; Replication Status Constants
(define-constant STATUS_REGISTERED u0)
(define-constant STATUS_IN_PROGRESS u1)
(define-constant STATUS_COMPLETED u2)
(define-constant STATUS_ABANDONED u3)
(define-constant STATUS_DISPUTED u4)

;; Replication Outcome Constants
(define-constant OUTCOME_SUCCESSFUL u0)
(define-constant OUTCOME_PARTIAL u1)
(define-constant OUTCOME_FAILED u2)
(define-constant OUTCOME_INCONCLUSIVE u3)

;; Data Maps
(define-map replication-attempts
  { replication-id: (string-ascii 64) }
  {
    original-research-id: (string-ascii 64),
    replicator: principal,
    institution: (string-utf8 150),
    methodology-hash: (string-ascii 64),
    registration-date: uint,
    expected-completion-date: uint,
    status: uint,
    funding-source: (optional (string-utf8 200)),
    collaborators: (list 5 principal)
  }
)

(define-map replication-results
  { replication-id: (string-ascii 64) }
  {
    outcome: uint,
    results-hash: (string-ascii 64),
    completion-date: uint,
    findings-summary: (string-utf8 1000),
    statistical-significance: bool,
    confidence-interval: (optional (string-utf8 50)),
    effect-size: (optional (string-utf8 50)),
    data-availability: bool,
    code-availability: bool,
    reproducibility-score: uint
  }
)

(define-map research-replication-summary
  { research-id: (string-ascii 64) }
  {
    total-attempts: uint,
    successful-replications: uint,
    failed-replications: uint,
    partial-replications: uint,
    inconclusive-replications: uint,
    average-reproducibility-score: uint,
    last-replication-date: uint,
    replication-rate: uint
  }
)

(define-map replicator-profile
  { replicator: principal }
  {
    name: (string-utf8 100),
    total-attempts: uint,
    completed-replications: uint,
    success-rate: uint,
    average-quality-score: uint,
    reputation-score: uint,
    specialization-areas: (list 5 (string-utf8 50))
  }
)

(define-map replication-reviews
  { replication-id: (string-ascii 64), reviewer: principal }
  {
    quality-score: uint,
    methodology-score: uint,
    transparency-score: uint,
    review-text: (string-utf8 500),
    review-date: uint
  }
)

;; Data Variables
(define-data-var total-replication-attempts uint u0)
(define-data-var total-completed-replications uint u0)
(define-data-var contract-admin principal tx-sender)

;; Private Functions
(define-private (is-valid-status (status uint))
  (or 
    (is-eq status STATUS_REGISTERED)
    (is-eq status STATUS_IN_PROGRESS)
    (is-eq status STATUS_COMPLETED)
    (is-eq status STATUS_ABANDONED)
    (is-eq status STATUS_DISPUTED)
  )
)

(define-private (is-valid-outcome (outcome uint))
  (or 
    (is-eq outcome OUTCOME_SUCCESSFUL)
    (is-eq outcome OUTCOME_PARTIAL)
    (is-eq outcome OUTCOME_FAILED)
    (is-eq outcome OUTCOME_INCONCLUSIVE)
  )
)

(define-private (update-research-replication-stats
    (research-id (string-ascii 64))
    (outcome uint)
    (reproducibility-score uint)
  )
  (let 
    (
      (current-summary (default-to {
        total-attempts: u0,
        successful-replications: u0,
        failed-replications: u0,
        partial-replications: u0,
        inconclusive-replications: u0,
        average-reproducibility-score: u0,
        last-replication-date: u0,
        replication-rate: u0
      } (map-get? research-replication-summary { research-id: research-id })))
      (new-total-attempts (+ (get total-attempts current-summary) u1))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
      (current-total-score (* (get average-reproducibility-score current-summary) (get total-attempts current-summary)))
      (new-average-score (/ (+ current-total-score reproducibility-score) new-total-attempts))
    )
    (map-set research-replication-summary
      { research-id: research-id }
      (merge current-summary {
        total-attempts: new-total-attempts,
        successful-replications: (if (is-eq outcome OUTCOME_SUCCESSFUL) (+ (get successful-replications current-summary) u1) (get successful-replications current-summary)),
        failed-replications: (if (is-eq outcome OUTCOME_FAILED) (+ (get failed-replications current-summary) u1) (get failed-replications current-summary)),
        partial-replications: (if (is-eq outcome OUTCOME_PARTIAL) (+ (get partial-replications current-summary) u1) (get partial-replications current-summary)),
        inconclusive-replications: (if (is-eq outcome OUTCOME_INCONCLUSIVE) (+ (get inconclusive-replications current-summary) u1) (get inconclusive-replications current-summary)),
        average-reproducibility-score: new-average-score,
        last-replication-date: current-timestamp,
        replication-rate: (/ (* (get successful-replications current-summary) u100) new-total-attempts)
      })
    )
  )
)

(define-private (update-replicator-stats (replicator principal) (outcome uint) (quality-score uint))
  (let 
    (
      (current-profile (default-to {
        name: u"Unknown",
        total-attempts: u0,
        completed-replications: u0,
        success-rate: u0,
        average-quality-score: u0,
        reputation-score: u0,
        specialization-areas: (list)
      } (map-get? replicator-profile { replicator: replicator })))
      (new-completed (+ (get completed-replications current-profile) u1))
      (new-total (+ (get total-attempts current-profile) u1))
      (successful-count (if (is-eq outcome OUTCOME_SUCCESSFUL) (+ u1 u0) u0))
      (new-success-rate (/ (* successful-count u100) new-completed))
    )
    (map-set replicator-profile
      { replicator: replicator }
      (merge current-profile {
        completed-replications: new-completed,
        total-attempts: new-total,
        success-rate: new-success-rate,
        average-quality-score: quality-score,
        reputation-score: (+ (get reputation-score current-profile) quality-score)
      })
    )
  )
)

;; Public Functions

;; Register a new replication attempt
(define-public (register-replication-attempt
    (replication-id (string-ascii 64))
    (original-research-id (string-ascii 64))
    (institution (string-utf8 150))
    (methodology-hash (string-ascii 64))
    (expected-completion-date uint)
    (funding-source (optional (string-utf8 200)))
    (collaborators (list 5 principal))
  )
  (let 
    (
      (existing-attempt (map-get? replication-attempts { replication-id: replication-id }))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (is-none existing-attempt) ERR_ALREADY_EXISTS)
    (asserts! (> (len replication-id) u0) ERR_INVALID_DATA)
    (asserts! (> (len original-research-id) u0) ERR_INVALID_DATA)
    (asserts! (> (len institution) u0) ERR_INVALID_DATA)
    (asserts! (is-eq (len methodology-hash) u64) ERR_INVALID_DATA)
    (asserts! (> expected-completion-date current-timestamp) ERR_INVALID_DATA)
    
    (map-set replication-attempts
      { replication-id: replication-id }
      {
        original-research-id: original-research-id,
        replicator: tx-sender,
        institution: institution,
        methodology-hash: methodology-hash,
        registration-date: current-timestamp,
        expected-completion-date: expected-completion-date,
        status: STATUS_REGISTERED,
        funding-source: funding-source,
        collaborators: collaborators
      }
    )
    
    (var-set total-replication-attempts (+ (var-get total-replication-attempts) u1))
    
    (print {
      event: "replication-registered",
      replication-id: replication-id,
      original-research-id: original-research-id,
      replicator: tx-sender,
      timestamp: current-timestamp
    })
    
    (ok replication-id)
  )
)

;; Submit replication results and outcomes
(define-public (submit-replication-results
    (replication-id (string-ascii 64))
    (outcome uint)
    (results-hash (string-ascii 64))
    (findings-summary (string-utf8 1000))
    (statistical-significance bool)
    (confidence-interval (optional (string-utf8 50)))
    (effect-size (optional (string-utf8 50)))
    (data-availability bool)
    (code-availability bool)
    (reproducibility-score uint)
  )
  (let 
    (
      (attempt-info (unwrap! (map-get? replication-attempts { replication-id: replication-id }) ERR_NOT_FOUND))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (is-eq (get replicator attempt-info) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-valid-outcome outcome) ERR_INVALID_OUTCOME)
    (asserts! (is-eq (len results-hash) u64) ERR_INVALID_DATA)
    (asserts! (> (len findings-summary) u0) ERR_INVALID_DATA)
    (asserts! (<= reproducibility-score u100) ERR_INVALID_DATA)
    
    (map-set replication-results
      { replication-id: replication-id }
      {
        outcome: outcome,
        results-hash: results-hash,
        completion-date: current-timestamp,
        findings-summary: findings-summary,
        statistical-significance: statistical-significance,
        confidence-interval: confidence-interval,
        effect-size: effect-size,
        data-availability: data-availability,
        code-availability: code-availability,
        reproducibility-score: reproducibility-score
      }
    )
    
    (map-set replication-attempts
      { replication-id: replication-id }
      (merge attempt-info { status: STATUS_COMPLETED })
    )
    
    (update-research-replication-stats (get original-research-id attempt-info) outcome reproducibility-score)
    (update-replicator-stats tx-sender outcome reproducibility-score)
    (var-set total-completed-replications (+ (var-get total-completed-replications) u1))
    
    (print {
      event: "replication-results-submitted",
      replication-id: replication-id,
      outcome: outcome,
      replicator: tx-sender,
      reproducibility-score: reproducibility-score,
      timestamp: current-timestamp
    })
    
    (ok replication-id)
  )
)

;; Retrieve complete replication history for research
(define-read-only (get-replication-history (research-id (string-ascii 64)))
  (map-get? research-replication-summary { research-id: research-id })
)

;; Update the status of ongoing replications
(define-public (update-replication-status
    (replication-id (string-ascii 64))
    (new-status uint)
  )
  (let 
    (
      (attempt-info (unwrap! (map-get? replication-attempts { replication-id: replication-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq (get replicator attempt-info) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-valid-status new-status) ERR_INVALID_STATUS)
    
    (map-set replication-attempts
      { replication-id: replication-id }
      (merge attempt-info { status: new-status })
    )
    
    (print {
      event: "replication-status-updated",
      replication-id: replication-id,
      new-status: new-status,
      replicator: tx-sender
    })
    
    (ok new-status)
  )
)

;; Get replication attempt details
(define-read-only (get-replication-attempt (replication-id (string-ascii 64)))
  (map-get? replication-attempts { replication-id: replication-id })
)

;; Get replication results
(define-read-only (get-replication-results (replication-id (string-ascii 64)))
  (map-get? replication-results { replication-id: replication-id })
)

;; Get replicator profile
(define-read-only (get-replicator-profile (replicator principal))
  (map-get? replicator-profile { replicator: replicator })
)

;; Get total replication attempts
(define-read-only (get-total-attempts)
  (var-get total-replication-attempts)
)

;; Get total completed replications
(define-read-only (get-total-completed)
  (var-get total-completed-replications)
)

;; Check if replication exists
(define-read-only (replication-exists (replication-id (string-ascii 64)))
  (is-some (map-get? replication-attempts { replication-id: replication-id }))
)

;; Submit quality review for a replication
(define-public (submit-replication-review
    (replication-id (string-ascii 64))
    (quality-score uint)
    (methodology-score uint)
    (transparency-score uint)
    (review-text (string-utf8 500))
  )
  (let 
    (
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (replication-exists replication-id) ERR_NOT_FOUND)
    (asserts! (<= quality-score u10) ERR_INVALID_DATA)
    (asserts! (<= methodology-score u10) ERR_INVALID_DATA)
    (asserts! (<= transparency-score u10) ERR_INVALID_DATA)
    (asserts! (> (len review-text) u0) ERR_INVALID_DATA)
    
    (map-set replication-reviews
      { replication-id: replication-id, reviewer: tx-sender }
      {
        quality-score: quality-score,
        methodology-score: methodology-score,
        transparency-score: transparency-score,
        review-text: review-text,
        review-date: current-timestamp
      }
    )
    
    (print {
      event: "replication-review-submitted",
      replication-id: replication-id,
      reviewer: tx-sender,
      quality-score: quality-score,
      timestamp: current-timestamp
    })
    
    (ok replication-id)
  )
)

