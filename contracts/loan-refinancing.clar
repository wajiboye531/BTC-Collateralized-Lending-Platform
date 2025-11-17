(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_NO_ACTIVE_LOAN (err u501))
(define-constant ERR_REFINANCE_NOT_BENEFICIAL (err u502))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u503))
(define-constant ERR_INVALID_TERMS (err u504))

(define-constant MIN_REFINANCE_IMPROVEMENT u50)
(define-constant MAX_REFINANCE_FEE u100)
(define-constant REFINANCE_COOLDOWN_BLOCKS u1440)

(define-data-var total-refinances uint u0)
(define-data-var platform-refinance-fees uint u0)

(define-map refinance-history
  { borrower: principal }
  {
    previous-rate: uint,
    new-rate: uint,
    collateral-added: uint,
    additional-borrowed: uint,
    timestamp: uint,
    refinance-count: uint
  }
)

(define-map refinance-cooldowns
  { borrower: principal }
  { last-refinance-block: uint }
)

(define-private (calculate-refinance-fee (loan-amount uint))
  (let ((fee-amount (/ (* loan-amount u1) u1000)))
    (if (> fee-amount MAX_REFINANCE_FEE)
      MAX_REFINANCE_FEE
      fee-amount
    )
  )
)

(define-private (is-rate-improvement (current-rate uint) (new-rate uint))
  (and 
    (< new-rate current-rate)
    (>= (- current-rate new-rate) (/ current-rate MIN_REFINANCE_IMPROVEMENT))
  )
)

(define-private (check-cooldown (borrower principal))
  (match (map-get? refinance-cooldowns { borrower: borrower })
    cooldown-data
    (>= (- stacks-block-height (get last-refinance-block cooldown-data)) REFINANCE_COOLDOWN_BLOCKS)
    true
  )
)

(define-public (refinance-loan (additional-collateral uint) (additional-borrow uint))
  (let ((loan-info (try! (contract-call? .BTC-Collateralized-Lending-Platform get-loan-info tx-sender)))
        (current-rate u5)
        (new-rate (unwrap-panic (contract-call? .interest-rate-oracle get-recommended-rate)))
        (total-debt (get total-debt loan-info))
        (refinance-fee (calculate-refinance-fee total-debt))
        (history (default-to 
          { previous-rate: u0, new-rate: u0, collateral-added: u0, additional-borrowed: u0, timestamp: u0, refinance-count: u0 }
          (map-get? refinance-history { borrower: tx-sender }))))
    
    (asserts! (check-cooldown tx-sender) ERR_UNAUTHORIZED)
    (asserts! (or (is-rate-improvement current-rate new-rate) (> additional-collateral u0)) ERR_REFINANCE_NOT_BENEFICIAL)
    
    (if (> additional-collateral u0)
      (try! (contract-call? .BTC-Collateralized-Lending-Platform deposit-collateral additional-collateral))
      u0
    )
    
    (map-set refinance-history
      { borrower: tx-sender }
      {
        previous-rate: current-rate,
        new-rate: new-rate,
        collateral-added: additional-collateral,
        additional-borrowed: additional-borrow,
        timestamp: stacks-block-height,
        refinance-count: (+ (get refinance-count history) u1)
      }
    )
    
    (map-set refinance-cooldowns
      { borrower: tx-sender }
      { last-refinance-block: stacks-block-height }
    )
    
    (var-set total-refinances (+ (var-get total-refinances) u1))
    (var-set platform-refinance-fees (+ (var-get platform-refinance-fees) refinance-fee))
    
    (ok { new-rate: new-rate, fee: refinance-fee, total-debt: total-debt })
  )
)

(define-read-only (get-refinance-terms (borrower principal))
  (let ((loan-info (unwrap-panic (contract-call? .BTC-Collateralized-Lending-Platform get-loan-info borrower)))
        (current-rate u5)
        (new-rate (unwrap-panic (contract-call? .interest-rate-oracle get-recommended-rate)))
        (total-debt (get total-debt loan-info)))
    (ok {
      current-rate: current-rate,
      available-rate: new-rate,
      potential-savings: (if (< new-rate current-rate) (- current-rate new-rate) u0),
      refinance-fee: (calculate-refinance-fee total-debt),
      cooldown-remaining: (match (map-get? refinance-cooldowns { borrower: borrower })
        cooldown (if (> (+ (get last-refinance-block cooldown) REFINANCE_COOLDOWN_BLOCKS) stacks-block-height)
          (- (+ (get last-refinance-block cooldown) REFINANCE_COOLDOWN_BLOCKS) stacks-block-height)
          u0)
        u0),
      is-beneficial: (is-rate-improvement current-rate new-rate)
    })
  )
)

(define-read-only (get-borrower-refinance-history (borrower principal))
  (ok (map-get? refinance-history { borrower: borrower }))
)

(define-read-only (get-platform-refinance-stats)
  (ok {
    total-refinances: (var-get total-refinances),
    total-fees-collected: (var-get platform-refinance-fees)
  })
)
