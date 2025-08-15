(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_INSUFFICIENT_POOL_FUNDS (err u201))
(define-constant ERR_POLICY_NOT_FOUND (err u202))
(define-constant ERR_INVALID_PREMIUM (err u203))
(define-constant ERR_POLICY_EXPIRED (err u204))

(define-constant COVERAGE_PERCENTAGE u80)
(define-constant BASE_PREMIUM_RATE u2)
(define-constant POLICY_DURATION_BLOCKS u26280)

(define-data-var total-pool-balance uint u0)
(define-data-var total-claims-paid uint u0)
(define-data-var active-policies uint u0)

(define-map insurance-policies
  { borrower: principal }
  {
    coverage-amount: uint,
    premium-paid: uint,
    start-block: uint,
    expiry-block: uint,
    is-active: bool
  }
)

(define-map pool-contributions
  { contributor: principal }
  { amount: uint }
)

(define-private (calculate-premium (loan-amount uint))
  (/ (* loan-amount BASE_PREMIUM_RATE) u100)
)

(define-private (is-policy-valid (borrower principal))
  (match (map-get? insurance-policies { borrower: borrower })
    policy-data
    (and 
      (get is-active policy-data)
      (> (get expiry-block policy-data) stacks-block-height)
    )
    false
  )
)

(define-public (contribute-to-pool (amount uint))
  (begin
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set pool-contributions
      { contributor: tx-sender }
      { amount: (+ amount (default-to u0 (get amount (map-get? pool-contributions { contributor: tx-sender }))))
      }
    )
    (var-set total-pool-balance (+ (var-get total-pool-balance) amount))
    (ok amount)
  )
)

(define-public (purchase-insurance (loan-amount uint))
  (let ((premium (calculate-premium loan-amount))
        (coverage-amount (/ (* loan-amount COVERAGE_PERCENTAGE) u100))
        (expiry-block (+ stacks-block-height POLICY_DURATION_BLOCKS)))
    
    (asserts! (> premium u0) ERR_INVALID_PREMIUM)
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    (map-set insurance-policies
      { borrower: tx-sender }
      {
        coverage-amount: coverage-amount,
        premium-paid: premium,
        start-block: stacks-block-height,
        expiry-block: expiry-block,
        is-active: true
      }
    )
    
    (var-set total-pool-balance (+ (var-get total-pool-balance) premium))
    (var-set active-policies (+ (var-get active-policies) u1))
    (ok coverage-amount)
  )
)

(define-public (file-insurance-claim (borrower principal) (loss-amount uint))
  (let ((policy-data (unwrap! (map-get? insurance-policies { borrower: borrower }) ERR_POLICY_NOT_FOUND))
        (payout-amount (if (<= loss-amount (get coverage-amount policy-data))
          loss-amount
          (get coverage-amount policy-data))))
    
    (asserts! (is-policy-valid borrower) ERR_POLICY_EXPIRED)
    (asserts! (<= payout-amount (var-get total-pool-balance)) ERR_INSUFFICIENT_POOL_FUNDS)
    
    (try! (as-contract (stx-transfer? payout-amount tx-sender borrower)))
    (map-set insurance-policies
      { borrower: borrower }
      (merge policy-data { is-active: false })
    )
    
    (var-set total-pool-balance (- (var-get total-pool-balance) payout-amount))
    (var-set total-claims-paid (+ (var-get total-claims-paid) payout-amount))
    (var-set active-policies (- (var-get active-policies) u1))
    (ok payout-amount)
  )
)

(define-read-only (get-policy-info (borrower principal))
  (match (map-get? insurance-policies { borrower: borrower })
    policy-data
    (ok {
      coverage-amount: (get coverage-amount policy-data),
      premium-paid: (get premium-paid policy-data),
      blocks-remaining: (if (> (get expiry-block policy-data) stacks-block-height)
        (- (get expiry-block policy-data) stacks-block-height)
        u0
      ),
      is-active: (get is-active policy-data),
      is-valid: (is-policy-valid borrower)
    })
    ERR_POLICY_NOT_FOUND
  )
)

(define-read-only (get-pool-stats)
  (ok {
    total-balance: (var-get total-pool-balance),
    total-claims-paid: (var-get total-claims-paid),
    active-policies: (var-get active-policies),
    coverage-ratio: (if (> (var-get total-claims-paid) u0)
      (/ (* (var-get total-pool-balance) u100) (var-get total-claims-paid))
      u100
    )
  })
)