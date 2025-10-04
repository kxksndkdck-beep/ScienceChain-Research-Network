;; Research Integrity Rewards Contract
;; Token incentives for open data sharing, successful replications, and quality peer reviews

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_NOT_FOUND (err u401))
(define-constant ERR_ALREADY_EXISTS (err u402))
(define-constant ERR_INVALID_DATA (err u403))
(define-constant ERR_INSUFFICIENT_BALANCE (err u404))
(define-constant ERR_INVALID_AMOUNT (err u405))
(define-constant ERR_ALREADY_CLAIMED (err u406))

;; Token Constants
(define-constant TOKEN_NAME "ScienceChain")
(define-constant TOKEN_SYMBOL "SCI")
(define-constant TOKEN_DECIMALS u6)
(define-constant TOTAL_SUPPLY u1000000000000000) ;; 1 billion tokens with 6 decimals
(define-constant INITIAL_MINT u400000000000000) ;; 400M tokens for rewards pool

;; Reward Constants
(define-constant REWARD_DATA_REGISTRATION u1000000) ;; 1 SCI token
(define-constant REWARD_PEER_REVIEW u5000000) ;; 5 SCI tokens
(define-constant REWARD_SUCCESSFUL_REPLICATION u10000000) ;; 10 SCI tokens
(define-constant REWARD_DATA_VERIFICATION u2000000) ;; 2 SCI tokens
(define-constant REWARD_QUALITY_REVIEW u3000000) ;; 3 SCI tokens

;; Reputation Score Multipliers
(define-constant MULTIPLIER_BRONZE u100) ;; 1.0x
(define-constant MULTIPLIER_SILVER u125) ;; 1.25x
(define-constant MULTIPLIER_GOLD u150) ;; 1.5x
(define-constant MULTIPLIER_PLATINUM u200) ;; 2.0x

;; Token Definition
(define-fungible-token sci-token TOTAL_SUPPLY)

;; Data Maps
(define-map token-balances
  { owner: principal }
  { balance: uint }
)

(define-map user-rewards
  { user: principal }
  {
    total-earned: uint,
    total-claimed: uint,
    pending-rewards: uint,
    last-claim-date: uint,
    reputation-score: uint,
    reputation-level: uint
  }
)

(define-map reward-activities
  { activity-id: (string-ascii 64) }
  {
    user: principal,
    activity-type: uint,
    reward-amount: uint,
    timestamp: uint,
    claimed: bool,
    research-id: (optional (string-ascii 64)),
    quality-score: (optional uint)
  }
)

(define-map reputation-levels
  { level: uint }
  {
    min-score: uint,
    max-score: uint,
    multiplier: uint,
    level-name: (string-ascii 20)
  }
)

;; Data Variables
(define-data-var total-rewards-distributed uint u0)
(define-data-var contract-admin principal tx-sender)
(define-data-var rewards-pool-balance uint INITIAL_MINT)
(define-data-var next-activity-id uint u1)

;; Activity Type Constants
(define-constant ACTIVITY_DATA_REGISTRATION u1)
(define-constant ACTIVITY_PEER_REVIEW u2)
(define-constant ACTIVITY_REPLICATION u3)
(define-constant ACTIVITY_DATA_VERIFICATION u4)
(define-constant ACTIVITY_QUALITY_REVIEW u5)

;; Initialize reputation levels
(map-set reputation-levels { level: u1 } { min-score: u0, max-score: u999, multiplier: MULTIPLIER_BRONZE, level-name: "Bronze" })
(map-set reputation-levels { level: u2 } { min-score: u1000, max-score: u4999, multiplier: MULTIPLIER_SILVER, level-name: "Silver" })
(map-set reputation-levels { level: u3 } { min-score: u5000, max-score: u19999, multiplier: MULTIPLIER_GOLD, level-name: "Gold" })
(map-set reputation-levels { level: u4 } { min-score: u20000, max-score: u999999999, multiplier: MULTIPLIER_PLATINUM, level-name: "Platinum" })

;; Private Functions
(define-private (get-reward-multiplier (reputation-score uint))
  (if (<= reputation-score u999)
    MULTIPLIER_BRONZE
    (if (<= reputation-score u4999)
      MULTIPLIER_SILVER
      (if (<= reputation-score u19999)
        MULTIPLIER_GOLD
        MULTIPLIER_PLATINUM
      )
    )
  )
)

(define-private (get-reputation-level (reputation-score uint))
  (if (<= reputation-score u999)
    u1
    (if (<= reputation-score u4999)
      u2
      (if (<= reputation-score u19999)
        u3
        u4
      )
    )
  )
)

(define-private (calculate-final-reward (base-reward uint) (reputation-score uint))
  (let 
    (
      (multiplier (get-reward-multiplier reputation-score))
    )
    (/ (* base-reward multiplier) u100)
  )
)

(define-private (update-user-reputation (user principal) (points uint))
  (let 
    (
      (current-rewards (default-to {
        total-earned: u0,
        total-claimed: u0,
        pending-rewards: u0,
        last-claim-date: u0,
        reputation-score: u0,
        reputation-level: u1
      } (map-get? user-rewards { user: user })))
      (new-reputation-score (+ (get reputation-score current-rewards) points))
      (new-level (get-reputation-level new-reputation-score))
    )
    (map-set user-rewards
      { user: user }
      (merge current-rewards {
        reputation-score: new-reputation-score,
        reputation-level: new-level
      })
    )
  )
)

;; Public Functions

;; Mint integrity tokens for verified research integrity actions
(define-public (mint-integrity-tokens
    (activity-type uint)
    (research-id (optional (string-ascii 64)))
    (quality-score (optional uint))
  )
  (let 
    (
      (user-info (default-to {
        total-earned: u0,
        total-claimed: u0,
        pending-rewards: u0,
        last-claim-date: u0,
        reputation-score: u0,
        reputation-level: u1
      } (map-get? user-rewards { user: tx-sender })))
      (base-reward (if (is-eq activity-type ACTIVITY_DATA_REGISTRATION)
        REWARD_DATA_REGISTRATION
        (if (is-eq activity-type ACTIVITY_PEER_REVIEW)
          REWARD_PEER_REVIEW
          (if (is-eq activity-type ACTIVITY_REPLICATION)
            REWARD_SUCCESSFUL_REPLICATION
            (if (is-eq activity-type ACTIVITY_DATA_VERIFICATION)
              REWARD_DATA_VERIFICATION
              (if (is-eq activity-type ACTIVITY_QUALITY_REVIEW)
                REWARD_QUALITY_REVIEW
                u0
              )
            )
          )
        )
      ))
      (final-reward (calculate-final-reward base-reward (get reputation-score user-info)))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
      (activity-id (int-to-ascii (var-get next-activity-id)))
    )
    (asserts! (> base-reward u0) ERR_INVALID_DATA)
    (asserts! (<= final-reward (var-get rewards-pool-balance)) ERR_INSUFFICIENT_BALANCE)
    
    (map-set reward-activities
      { activity-id: activity-id }
      {
        user: tx-sender,
        activity-type: activity-type,
        reward-amount: final-reward,
        timestamp: current-timestamp,
        claimed: false,
        research-id: research-id,
        quality-score: quality-score
      }
    )
    
    (map-set user-rewards
      { user: tx-sender }
      (merge user-info {
        total-earned: (+ (get total-earned user-info) final-reward),
        pending-rewards: (+ (get pending-rewards user-info) final-reward)
      })
    )
    
    (var-set rewards-pool-balance (- (var-get rewards-pool-balance) final-reward))
    (var-set next-activity-id (+ (var-get next-activity-id) u1))
    (update-user-reputation tx-sender base-reward)
    
    (print {
      event: "integrity-tokens-minted",
      user: tx-sender,
      activity-type: activity-type,
      reward-amount: final-reward,
      activity-id: activity-id,
      timestamp: current-timestamp
    })
    
    (ok final-reward)
  )
)

;; Distribute tokens to researchers, reviewers, and replicators
(define-public (distribute-rewards (recipients (list 10 { user: principal, amount: uint })))
  (let 
    (
      (total-amount (fold + (map get-amount recipients) u0))
    )
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_UNAUTHORIZED)
    (asserts! (<= total-amount (var-get rewards-pool-balance)) ERR_INSUFFICIENT_BALANCE)
    
    (fold distribute-single-reward recipients { success: true, total: u0 })
    
    (var-set rewards-pool-balance (- (var-get rewards-pool-balance) total-amount))
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) total-amount))
    
    (print {
      event: "batch-rewards-distributed",
      total-amount: total-amount,
      recipients-count: (len recipients)
    })
    
    (ok total-amount)
  )
)

;; Helper function for distribute-rewards
(define-private (get-amount (recipient { user: principal, amount: uint }))
  (get amount recipient)
)

(define-private (distribute-single-reward 
    (recipient { user: principal, amount: uint })
    (acc { success: bool, total: uint })
  )
  (let 
    (
      (user (get user recipient))
      (amount (get amount recipient))
      (user-info (default-to {
        total-earned: u0,
        total-claimed: u0,
        pending-rewards: u0,
        last-claim-date: u0,
        reputation-score: u0,
        reputation-level: u1
      } (map-get? user-rewards { user: user })))
    )
    (map-set user-rewards
      { user: user }
      (merge user-info {
        total-earned: (+ (get total-earned user-info) amount),
        pending-rewards: (+ (get pending-rewards user-info) amount)
      })
    )
    { success: true, total: (+ (get total acc) amount) }
  )
)

;; Calculate reputation scores based on contributions
(define-read-only (calculate-reputation-score (user principal))
  (let 
    (
      (user-info (map-get? user-rewards { user: user }))
    )
    (match user-info
      info (get reputation-score info)
      u0
    )
  )
)

;; Allow users to claim earned token rewards
(define-public (claim-rewards)
  (let 
    (
      (user-info (unwrap! (map-get? user-rewards { user: tx-sender }) ERR_NOT_FOUND))
      (pending-amount (get pending-rewards user-info))
      (current-timestamp (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (> pending-amount u0) ERR_INVALID_AMOUNT)
    
    (try! (ft-mint? sci-token pending-amount tx-sender))
    
    (map-set user-rewards
      { user: tx-sender }
      (merge user-info {
        total-claimed: (+ (get total-claimed user-info) pending-amount),
        pending-rewards: u0,
        last-claim-date: current-timestamp
      })
    )
    
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) pending-amount))
    
    (print {
      event: "rewards-claimed",
      user: tx-sender,
      amount: pending-amount,
      timestamp: current-timestamp
    })
    
    (ok pending-amount)
  )
)

;; Get user reward information
(define-read-only (get-user-rewards (user principal))
  (map-get? user-rewards { user: user })
)

;; Get activity details
(define-read-only (get-activity-details (activity-id (string-ascii 64)))
  (map-get? reward-activities { activity-id: activity-id })
)

;; Get reputation level information
(define-read-only (get-reputation-level-info (level uint))
  (map-get? reputation-levels { level: level })
)

;; Get total rewards distributed
(define-read-only (get-total-rewards-distributed)
  (var-get total-rewards-distributed)
)

;; Get rewards pool balance
(define-read-only (get-rewards-pool-balance)
  (var-get rewards-pool-balance)
)

;; Get token balance for a user
(define-read-only (get-token-balance (user principal))
  (ft-get-balance sci-token user)
)

;; Get token info
(define-read-only (get-token-info)
  {
    name: TOKEN_NAME,
    symbol: TOKEN_SYMBOL,
    decimals: TOKEN_DECIMALS,
    total-supply: TOTAL_SUPPLY
  }
)

;; Transfer tokens between users
(define-public (transfer-tokens (amount uint) (recipient principal))
  (ft-transfer? sci-token amount tx-sender recipient)
)

;; Admin function to add tokens to rewards pool
(define-public (add-to-rewards-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    (var-set rewards-pool-balance (+ (var-get rewards-pool-balance) amount))
    
    (print {
      event: "rewards-pool-increased",
      amount: amount,
      new-balance: (var-get rewards-pool-balance)
    })
    
    (ok (var-get rewards-pool-balance))
  )
)

;; Get current reputation multiplier for a user
(define-read-only (get-user-multiplier (user principal))
  (let 
    (
      (reputation-score (calculate-reputation-score user))
    )
    (get-reward-multiplier reputation-score)
  )
)

