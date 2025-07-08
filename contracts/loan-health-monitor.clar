(define-constant HEALTH_EXCELLENT u100)
(define-constant HEALTH_GOOD u80)
(define-constant HEALTH_MODERATE u60)
(define-constant HEALTH_POOR u40)
(define-constant HEALTH_CRITICAL u20)

(define-constant RISK_LOW u1)
(define-constant RISK_MEDIUM u2)
(define-constant RISK_HIGH u3)
(define-constant RISK_CRITICAL u4)

(define-data-var total-monitored-loans uint u0)
(define-data-var high-risk-loan-count uint u0)

(define-map loan-health-scores
  { borrower: principal }
  { 
    health-score: uint,
    risk-level: uint,
    last-updated: uint,
    days-to-liquidation: uint
  }
)

(define-map platform-risk-metrics
  { timestamp: uint }
  {
    total-loans: uint,
    healthy-loans: uint,
    at-risk-loans: uint,
    average-health: uint
  }
)

(define-private (calculate-health-score (collateral-ratio uint))
  (if (>= collateral-ratio u200)
    HEALTH_EXCELLENT
    (if (>= collateral-ratio u160)
      HEALTH_GOOD
      (if (>= collateral-ratio u140)
        HEALTH_MODERATE
        (if (>= collateral-ratio u125)
          HEALTH_POOR
          HEALTH_CRITICAL
        )
      )
    )
  )
)

(define-private (get-risk-level (health-score uint))
  (if (>= health-score HEALTH_GOOD)
    RISK_LOW
    (if (>= health-score HEALTH_MODERATE)
      RISK_MEDIUM
      (if (>= health-score HEALTH_POOR)
        RISK_HIGH
        RISK_CRITICAL
      )
    )
  )
)

(define-private (estimate-liquidation-days (current-ratio uint) (interest-rate uint))
  (if (> current-ratio u120)
    (let ((buffer-ratio (- current-ratio u120))
          (daily-decay (/ interest-rate u365)))
      (if (> daily-decay u0)
        (/ buffer-ratio daily-decay)
        u999
      )
    )
    u0
  )
)

(define-public (update-loan-health (borrower principal))
  (let ((loan-info (try! (contract-call? .BTC-Collateralized-Lending-Platform get-loan-info borrower)))
        (collateral-amount (get collateral-amount loan-info))
        (total-debt (get total-debt loan-info))
        (current-ratio (if (> total-debt u0) (/ (* collateral-amount u100) total-debt) u0))
        (health-score (calculate-health-score current-ratio))
        (risk-level (get-risk-level health-score))
        (liquidation-days (estimate-liquidation-days current-ratio u5)))
    
    (map-set loan-health-scores
      { borrower: borrower }
      {
        health-score: health-score,
        risk-level: risk-level,
        last-updated: stacks-block-height,
        days-to-liquidation: liquidation-days
      }
    )
    
    (if (>= risk-level RISK_HIGH)
      (var-set high-risk-loan-count (+ (var-get high-risk-loan-count) u1))
      true
    )
    
    (ok health-score)
  )
)

(define-public (batch-update-health (borrowers (list 50 principal)))
  (let ((results (map update-loan-health borrowers)))
    (var-set total-monitored-loans (len borrowers))
    (ok (len results))
  )
)

(define-read-only (get-loan-health (borrower principal))
  (match (map-get? loan-health-scores { borrower: borrower })
    health-data
    (ok health-data)
    (err u404)
  )
)

(define-read-only (get-platform-health-summary)
  (ok {
    total-monitored: (var-get total-monitored-loans),
    high-risk-count: (var-get high-risk-loan-count),
    risk-percentage: (if (> (var-get total-monitored-loans) u0)
      (/ (* (var-get high-risk-loan-count) u100) (var-get total-monitored-loans))
      u0
    )
  })
)

(define-read-only (is-loan-healthy (borrower principal))
  (match (map-get? loan-health-scores { borrower: borrower })
    health-data
    (>= (get health-score health-data) HEALTH_MODERATE)
    true
  )
)
