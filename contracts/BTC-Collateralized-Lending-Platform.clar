(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u101))
(define-constant ERR_LOAN_NOT_FOUND (err u102))
(define-constant ERR_INSUFFICIENT_BALANCE (err u103))
(define-constant ERR_LOAN_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_LIQUIDATION_NOT_ALLOWED (err u106))
(define-constant ERR_REPAYMENT_FAILED (err u107))

(define-constant COLLATERAL_RATIO u150)
(define-constant LIQUIDATION_THRESHOLD u120)
(define-constant INTEREST_RATE u5)
(define-constant BLOCKS_PER_YEAR u52560)

(define-data-var total-loans-issued uint u0)
(define-data-var total-collateral-locked uint u0)
(define-data-var platform-treasury uint u0)

(define-map loans
  { borrower: principal }
  {
    collateral-amount: uint,
    loan-amount: uint,
    interest-rate: uint,
    start-block: uint,
    last-payment-block: uint,
    is-active: bool
  }
)

(define-map user-balances
  { user: principal }
  { stable-balance: uint }
)

(define-map collateral-deposits
  { user: principal }
  { btc-amount: uint }
)

(define-private (calculate-interest (principal-amount uint) (blocks-elapsed uint))
  (let ((annual-interest (/ (* principal-amount INTEREST_RATE) u100)))
    (/ (* annual-interest blocks-elapsed) BLOCKS_PER_YEAR)
  )
)

(define-private (get-loan-value (collateral-amount uint))
  (/ (* collateral-amount u100) COLLATERAL_RATIO)
)

(define-private (is-loan-undercollateralized (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan-data
    (let ((current-block stacks-block-height)
          (blocks-elapsed (- current-block (get last-payment-block loan-data)))
          (interest-owed (calculate-interest (get loan-amount loan-data) blocks-elapsed))
          (total-debt (+ (get loan-amount loan-data) interest-owed))
          (collateral-value (* (get collateral-amount loan-data) u100))
          (current-ratio (/ collateral-value total-debt)))
      (< current-ratio LIQUIDATION_THRESHOLD)
    )
    false
  )
)

(define-public (deposit-collateral (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set collateral-deposits
      { user: tx-sender }
      { btc-amount: (+ amount (default-to u0 (get btc-amount (map-get? collateral-deposits { user: tx-sender }))))
      }
    )
    (var-set total-collateral-locked (+ (var-get total-collateral-locked) amount))
    (ok amount)
  )
)

(define-public (create-loan (collateral-amount uint))
  (let ((existing-loan (map-get? loans { borrower: tx-sender }))
        (user-collateral (default-to u0 (get btc-amount (map-get? collateral-deposits { user: tx-sender }))))
        (loan-amount (get-loan-value collateral-amount)))
    (asserts! (is-none existing-loan) ERR_LOAN_ALREADY_EXISTS)
    (asserts! (>= user-collateral collateral-amount) ERR_INSUFFICIENT_COLLATERAL)
    (asserts! (> collateral-amount u0) ERR_INVALID_AMOUNT)
    
    (map-set loans
      { borrower: tx-sender }
      {
        collateral-amount: collateral-amount,
        loan-amount: loan-amount,
        interest-rate: INTEREST_RATE,
        start-block: stacks-block-height,
        last-payment-block: stacks-block-height,
        is-active: true
      }
    )
    
    (map-set user-balances
      { user: tx-sender }
      { stable-balance: (+ loan-amount (default-to u0 (get stable-balance (map-get? user-balances { user: tx-sender }))))
      }
    )
    
    (var-set total-loans-issued (+ (var-get total-loans-issued) loan-amount))
    (ok loan-amount)
  )
)

(define-public (repay-loan (amount uint))
  (match (map-get? loans { borrower: tx-sender })
    loan-data
    (let ((current-block stacks-block-height)
          (blocks-elapsed (- current-block (get last-payment-block loan-data)))
          (interest-owed (calculate-interest (get loan-amount loan-data) blocks-elapsed))
          (total-debt (+ (get loan-amount loan-data) interest-owed))
          (user-balance (default-to u0 (get stable-balance (map-get? user-balances { user: tx-sender })))))
      
      (asserts! (get is-active loan-data) ERR_LOAN_NOT_FOUND)
      (asserts! (>= user-balance amount) ERR_INSUFFICIENT_BALANCE)
      (asserts! (<= amount total-debt) ERR_INVALID_AMOUNT)
      
      (if (>= amount total-debt)
        (begin
          (map-delete loans { borrower: tx-sender })
          (try! (as-contract (stx-transfer? (get collateral-amount loan-data) tx-sender tx-sender)))
          (map-set user-balances
            { user: tx-sender }
            { stable-balance: (- user-balance amount) }
          )
          (var-set platform-treasury (+ (var-get platform-treasury) interest-owed))
          (ok true)
        )
        (begin
          (map-set loans
            { borrower: tx-sender }
            (merge loan-data { 
              loan-amount: (- total-debt amount),
              last-payment-block: current-block 
            })
          )
          (map-set user-balances
            { user: tx-sender }
            { stable-balance: (- user-balance amount) }
          )
          (var-set platform-treasury (+ (var-get platform-treasury) (if (> interest-owed amount) amount interest-owed)))
          (ok false)
        )
      )
    )
    ERR_LOAN_NOT_FOUND
  )
)
(define-public (liquidate-loan (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan-data
    (let ((current-block stacks-block-height)
          (blocks-elapsed (- current-block (get last-payment-block loan-data)))
          (interest-owed (calculate-interest (get loan-amount loan-data) blocks-elapsed))
          (total-debt (+ (get loan-amount loan-data) interest-owed))
          (liquidation-bonus (/ (get collateral-amount loan-data) u10)))
      
      (asserts! (get is-active loan-data) ERR_LOAN_NOT_FOUND)
      (asserts! (is-loan-undercollateralized borrower) ERR_LIQUIDATION_NOT_ALLOWED)
      
      (map-delete loans { borrower: borrower })
      
      (try! (as-contract (stx-transfer? liquidation-bonus tx-sender tx-sender)))
      (try! (as-contract (stx-transfer? (- (get collateral-amount loan-data) liquidation-bonus) tx-sender borrower)))
      
      (var-set platform-treasury (+ (var-get platform-treasury) interest-owed))
      (ok (get collateral-amount loan-data))
    )
    ERR_LOAN_NOT_FOUND
  )
)

(define-public (withdraw-collateral (amount uint))
  (let ((user-collateral (default-to u0 (get btc-amount (map-get? collateral-deposits { user: tx-sender }))))
        (user-loan (map-get? loans { borrower: tx-sender })))
    
    (asserts! (>= user-collateral amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    (match user-loan
      loan-data
      (let ((remaining-collateral (- user-collateral amount))
            (max-loan-value (get-loan-value remaining-collateral)))
        (asserts! (>= max-loan-value (get loan-amount loan-data)) ERR_INSUFFICIENT_COLLATERAL)
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (map-set collateral-deposits
          { user: tx-sender }
          { btc-amount: remaining-collateral }
        )
        (var-set total-collateral-locked (- (var-get total-collateral-locked) amount))
        (ok amount)
      )
      (begin
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (map-set collateral-deposits
          { user: tx-sender }
          { btc-amount: (- user-collateral amount) }
        )
        (var-set total-collateral-locked (- (var-get total-collateral-locked) amount))
        (ok amount)
      )
    )
  )
)

(define-read-only (get-loan-info (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan-data
    (let ((current-block stacks-block-height)
          (blocks-elapsed (- current-block (get last-payment-block loan-data)))
          (interest-owed (calculate-interest (get loan-amount loan-data) blocks-elapsed))
          (total-debt (+ (get loan-amount loan-data) interest-owed)))
      (ok {
        collateral-amount: (get collateral-amount loan-data),
        loan-amount: (get loan-amount loan-data),
        interest-owed: interest-owed,
        total-debt: total-debt,
        is-active: (get is-active loan-data),
        can-be-liquidated: (is-loan-undercollateralized borrower)
      })
    )
    ERR_LOAN_NOT_FOUND
  )
)

(define-read-only (get-user-collateral (user principal))
  (ok (default-to u0 (get btc-amount (map-get? collateral-deposits { user: user }))))
)

(define-read-only (get-user-balance (user principal))
  (ok (default-to u0 (get stable-balance (map-get? user-balances { user: user }))))
)

(define-read-only (get-platform-stats)
  (ok {
    total-loans-issued: (var-get total-loans-issued),
    total-collateral-locked: (var-get total-collateral-locked),
    platform-treasury: (var-get platform-treasury),
    collateral-ratio: COLLATERAL_RATIO,
    liquidation-threshold: LIQUIDATION_THRESHOLD,
    interest-rate: INTEREST_RATE
  })
)

(define-public (emergency-withdraw)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (as-contract (stx-transfer? (stx-get-balance tx-sender) tx-sender CONTRACT_OWNER)))
    (ok true)
  )
)
