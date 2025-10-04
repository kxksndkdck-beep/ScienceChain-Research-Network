;; Peer Review System Contract
;; Transparent peer review process with reviewer credentials and conflict-of-interest disclosure

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_NOT_FOUND (err u201))
(define-constant ERR_ALREADY_EXISTS (err u202))
(define-constant ERR_INVALID_DATA (err u203))
(define-constant ERR_INVALID_SCORE (err u204))
(define-constant ERR_ALREADY_REVIEWED (err u205))

;; Review Score Constants
(define-constant MIN_REVIEW_SCORE u1)
(define-constant MAX_REVIEW_SCORE u5)

;; Reviewer Status Constants
(define-constant REVIEWER_STATUS_PENDING u0)
(define-constant REVIEWER_STATUS_ACTIVE u1)
(define-constant REVIEWER_STATUS_SUSPENDED u2)

;; Data Maps
(define-map reviewers
  { reviewer: principal }
  {
    name: (string-utf8 100),
    institution: (string-utf8 150),
    expertise-areas: (list 10 (string-utf8 50)),
    total-reviews: uint,
    average-rating: uint,
    registration-date: uint,
    status: uint,
    credentials-hash: (string-ascii 64)
  }
)

(define-map research-reviews
  { research-id: (string-ascii 64), reviewer: principal }
  {
    review-score: uint,
    review-text: (string-utf8 1000),
    conflict-of-interest: bool,
    conflict-description: (optional (string-utf8 300)),
    review-date: uint,
    confidence-level: uint,
    recommendation: uint,
    review-hash: (string-ascii 64)
  }
)

(define-map research-review-summary
  { research-id: (string-ascii 64) }
  {
    total-reviews: uint,
    average-score: uint,
    total-score: uint,
    recommendation-accept: uint,
    recommendation-reject: uint,
    recommendation-minor-revision: uint,
    recommendation-major-revision: uint,
    last-review-date: uint
  }
)

(define-map reviewer-research-assignments
  { reviewer: principal, research-id: (string-ascii 64) }
  { assigned-date: uint, completed: bool }
)

;; Data Variables
(define-data-var total-reviewers uint u0)
(define-data-var total-reviews uint u0)
(define-data-var contract-admin principal tx-sender)

;; Private Functions
(define-private (is-valid-score (score uint))
  (and (>= score MIN_REVIEW_SCORE) (<= score MAX_REVIEW_SCORE))
)

(define-private (is-valid-recommendation (rec uint))
  (and (>= rec u0) (<= rec u3))
)

(define-private (update-reviewer-stats (reviewer principal) (new-rating uint))
  (let 
    (
      (reviewer-info (unwrap-panic (map-get? reviewers { reviewer: reviewer })))
      (current-total (get total-reviews reviewer-info))
      (current-avg (get average-rating reviewer-info))
      (new-total (+ current-total u1))
      (new-avg (/ (+ (* current-avg current-total) new-rating) new-total))
    )
    (map-set reviewers
      { reviewer: reviewer }
      (merge reviewer-info {
        total-reviews: new-total,
        average-rating: new-avg
      })
    )
  )
)

(define-private (update-research-review-summary 
    (research-id (string-ascii 64))
    (score uint)
    (recommendation uint)
  )
  (let 
    (
      (current-summary (default-to {
        total-reviews: u0,
        average-score: u0,
        total-score: u0,
        recommendation-accept: u0,
        recommendation-reject: u0,
        recommendation-minor-revision: u0,
        recommendation-major-revision: u0,
        last-review-date: u0
      } (map-get? research-review-summary { research-id: research-id })))
      (new-total-reviews (+ (get total-reviews current-summary) u1))
      (new-total-score (+ (get total-score current-summary) score))
      (new-average-score (/ new-total-score new-total-reviews))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (map-set research-review-summary
      { research-id: research-id }
      (merge current-summary {
        total-reviews: new-total-reviews,
        average-score: new-average-score,
        total-score: new-total-score,
        recommendation-accept: (if (is-eq recommendation u0) (+ (get recommendation-accept current-summary) u1) (get recommendation-accept current-summary)),
        recommendation-reject: (if (is-eq recommendation u1) (+ (get recommendation-reject current-summary) u1) (get recommendation-reject current-summary)),
        recommendation-minor-revision: (if (is-eq recommendation u2) (+ (get recommendation-minor-revision current-summary) u1) (get recommendation-minor-revision current-summary)),
        recommendation-major-revision: (if (is-eq recommendation u3) (+ (get recommendation-major-revision current-summary) u1) (get recommendation-major-revision current-summary)),
        last-review-date: current-timestamp
      })
    )
  )
)

;; Public Functions

;; Register as a qualified peer reviewer
(define-public (register-reviewer
    (name (string-utf8 100))
    (institution (string-utf8 150))
    (expertise-areas (list 10 (string-utf8 50)))
    (credentials-hash (string-ascii 64))
  )
  (let 
    (
      (existing-reviewer (map-get? reviewers { reviewer: tx-sender }))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (is-none existing-reviewer) ERR_ALREADY_EXISTS)
    (asserts! (> (len name) u0) ERR_INVALID_DATA)
    (asserts! (> (len institution) u0) ERR_INVALID_DATA)
    (asserts! (> (len expertise-areas) u0) ERR_INVALID_DATA)
    (asserts! (is-eq (len credentials-hash) u64) ERR_INVALID_DATA)
    
    (map-set reviewers
      { reviewer: tx-sender }
      {
        name: name,
        institution: institution,
        expertise-areas: expertise-areas,
        total-reviews: u0,
        average-rating: u0,
        registration-date: current-timestamp,
        status: REVIEWER_STATUS_ACTIVE,
        credentials-hash: credentials-hash
      }
    )
    
    (var-set total-reviewers (+ (var-get total-reviewers) u1))
    
    (print {
      event: "reviewer-registered",
      reviewer: tx-sender,
      name: name,
      institution: institution,
      timestamp: current-timestamp
    })
    
    (ok tx-sender)
  )
)

;; Submit a peer review with conflict of interest disclosure
(define-public (submit-review
    (research-id (string-ascii 64))
    (review-score uint)
    (review-text (string-utf8 1000))
    (conflict-of-interest bool)
    (conflict-description (optional (string-utf8 300)))
    (confidence-level uint)
    (recommendation uint)
    (review-hash (string-ascii 64))
  )
  (let 
    (
      (reviewer-info (unwrap! (map-get? reviewers { reviewer: tx-sender }) ERR_UNAUTHORIZED))
      (existing-review (map-get? research-reviews { research-id: research-id, reviewer: tx-sender }))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (is-none existing-review) ERR_ALREADY_REVIEWED)
    (asserts! (is-eq (get status reviewer-info) REVIEWER_STATUS_ACTIVE) ERR_UNAUTHORIZED)
    (asserts! (is-valid-score review-score) ERR_INVALID_SCORE)
    (asserts! (is-valid-score confidence-level) ERR_INVALID_SCORE)
    (asserts! (is-valid-recommendation recommendation) ERR_INVALID_DATA)
    (asserts! (> (len review-text) u0) ERR_INVALID_DATA)
    (asserts! (is-eq (len review-hash) u64) ERR_INVALID_DATA)
    
    (map-set research-reviews
      { research-id: research-id, reviewer: tx-sender }
      {
        review-score: review-score,
        review-text: review-text,
        conflict-of-interest: conflict-of-interest,
        conflict-description: conflict-description,
        review-date: current-timestamp,
        confidence-level: confidence-level,
        recommendation: recommendation,
        review-hash: review-hash
      }
    )
    
    (map-set reviewer-research-assignments
      { reviewer: tx-sender, research-id: research-id }
      { assigned-date: current-timestamp, completed: true }
    )
    
    (update-reviewer-stats tx-sender review-score)
    (update-research-review-summary research-id review-score recommendation)
    (var-set total-reviews (+ (var-get total-reviews) u1))
    
    (print {
      event: "review-submitted",
      research-id: research-id,
      reviewer: tx-sender,
      score: review-score,
      recommendation: recommendation,
      has-conflict: conflict-of-interest,
      timestamp: current-timestamp
    })
    
    (ok research-id)
  )
)

;; Retrieve reviewer qualifications and history
(define-read-only (get-reviewer-credentials (reviewer principal))
  (map-get? reviewers { reviewer: reviewer })
)

;; Calculate weighted review scores
(define-read-only (calculate-review-score (research-id (string-ascii 64)))
  (map-get? research-review-summary { research-id: research-id })
)

;; Get specific review details
(define-read-only (get-review-details 
    (research-id (string-ascii 64))
    (reviewer principal)
  )
  (map-get? research-reviews { research-id: research-id, reviewer: reviewer })
)

;; Check if reviewer is qualified and active
(define-read-only (is-reviewer-active (reviewer principal))
  (match (map-get? reviewers { reviewer: reviewer })
    reviewer-info (is-eq (get status reviewer-info) REVIEWER_STATUS_ACTIVE)
    false
  )
)

;; Get reviewer assignment info
(define-read-only (get-assignment-info 
    (reviewer principal)
    (research-id (string-ascii 64))
  )
  (map-get? reviewer-research-assignments { reviewer: reviewer, research-id: research-id })
)

;; Get total number of reviewers
(define-read-only (get-total-reviewers)
  (var-get total-reviewers)
)

;; Get total number of reviews
(define-read-only (get-total-reviews)
  (var-get total-reviews)
)

;; Update reviewer status (admin function)
(define-public (update-reviewer-status
    (reviewer principal)
    (new-status uint)
  )
  (let 
    (
      (reviewer-info (unwrap! (map-get? reviewers { reviewer: reviewer }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_UNAUTHORIZED)
    (asserts! (<= new-status REVIEWER_STATUS_SUSPENDED) ERR_INVALID_DATA)
    
    (map-set reviewers
      { reviewer: reviewer }
      (merge reviewer-info { status: new-status })
    )
    
    (print {
      event: "reviewer-status-updated",
      reviewer: reviewer,
      new-status: new-status,
      admin: tx-sender
    })
    
    (ok new-status)
  )
)

