(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_INVALID_SAMPLE (err u401))
(define-constant ERR_NO_DATA (err u402))

(define-constant MIN_INTEREST_RATE u1)
(define-constant MAX_INTEREST_RATE u20)
(define-constant BASE_RATE u5)
(define-constant SAMPLE_WINDOW u100)
(define-constant UTILIZATION_MULTIPLIER u10)

(define-data-var current-epoch uint u0)
(define-data-var cumulative-risk-score uint u0)
(define-data-var total-samples uint u0)

(define-map epoch-data
  { epoch: uint }
  {
    average-collateral-ratio: uint,
    platform-utilization: uint,
    recommended-rate: uint,
    timestamp: uint,
    sample-count: uint
  }
)

(define-map rate-history
  { index: uint }
  { rate: uint, block: uint }
)

(define-private (calculate-utilization-rate)
  (let ((stats (unwrap-panic (contract-call? .BTC-Collateralized-Lending-Platform get-platform-stats)))
        (total-collateral (get total-collateral-locked stats))
        (total-loans (get total-loans-issued stats)))
    (if (> total-collateral u0)
      (/ (* total-loans u100) total-collateral)
      u0
    )
  )
)

(define-private (compute-risk-adjusted-rate (utilization uint) (avg-ratio uint))
  (let ((utilization-premium (/ (* utilization UTILIZATION_MULTIPLIER) u100))
        (collateral-discount (if (> avg-ratio u180) u1 u0))
        (raw-rate (+ BASE_RATE utilization-premium (- collateral-discount))))
    (if (> raw-rate MAX_INTEREST_RATE)
      MAX_INTEREST_RATE
      (if (< raw-rate MIN_INTEREST_RATE)
        MIN_INTEREST_RATE
        raw-rate
      )
    )
  )
)

(define-public (record-platform-snapshot)
  (let ((current-utilization (calculate-utilization-rate))
        (epoch (var-get current-epoch))
        (sample-count (var-get total-samples)))
    
    (let ((new-rate (compute-risk-adjusted-rate current-utilization u150)))
      (map-set epoch-data
        { epoch: epoch }
        {
          average-collateral-ratio: u150,
          platform-utilization: current-utilization,
          recommended-rate: new-rate,
          timestamp: stacks-block-height,
          sample-count: (+ sample-count u1)
        }
      )
      
      (map-set rate-history
        { index: sample-count }
        { rate: new-rate, block: stacks-block-height }
      )
      
      (var-set total-samples (+ sample-count u1))
      (var-set cumulative-risk-score (+ (var-get cumulative-risk-score) current-utilization))
      
      (if (>= (+ sample-count u1) SAMPLE_WINDOW)
        (var-set current-epoch (+ epoch u1))
        true
      )
      
      (ok new-rate)
    )
  )
)

(define-read-only (get-recommended-rate)
  (let ((latest-epoch (var-get current-epoch)))
    (match (map-get? epoch-data { epoch: latest-epoch })
      data (ok (get recommended-rate data))
      (ok BASE_RATE)
    )
  )
)

(define-read-only (get-epoch-data (epoch uint))
  (ok (map-get? epoch-data { epoch: epoch }))
)

(define-read-only (get-rate-trend)
  (let ((sample-count (var-get total-samples)))
    (if (> sample-count u0)
      (ok {
        average-risk: (/ (var-get cumulative-risk-score) sample-count),
        total-epochs: (var-get current-epoch),
        samples-collected: sample-count,
        current-recommended-rate: (unwrap-panic (get-recommended-rate))
      })
      ERR_NO_DATA
    )
  )
)

(define-read-only (get-historical-rate (index uint))
  (ok (map-get? rate-history { index: index }))
)

