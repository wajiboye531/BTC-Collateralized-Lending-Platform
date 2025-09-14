(define-constant ERR_NOT_AUTHORIZED (err u300))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u301))
(define-constant ERR_VOTING_PERIOD_ENDED (err u302))
(define-constant ERR_PROPOSAL_NOT_ACTIVE (err u303))
(define-constant ERR_ALREADY_VOTED (err u304))
(define-constant ERR_EXECUTION_TIME_NOT_REACHED (err u305))
(define-constant ERR_INVALID_PARAMETER (err u306))

(define-constant VOTING_PERIOD_BLOCKS u14400)
(define-constant TIME_LOCK_BLOCKS u43200)
(define-constant PROPOSAL_THRESHOLD u100000)
(define-constant QUORUM_PERCENTAGE u25)

(define-data-var proposal-nonce uint u0)
(define-data-var total-voting-power uint u0)

(define-map proposals
  { proposal-id: uint }
  {
    proposer: principal,
    parameter-name: (string-ascii 32),
    new-value: uint,
    votes-for: uint,
    votes-against: uint,
    start-block: uint,
    end-block: uint,
    execution-block: uint,
    is-executed: bool,
    is-active: bool
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, power: uint }
)

(define-private (get-voting-power (voter principal))
  (unwrap-panic (contract-call? .BTC-Collateralized-Lending-Platform get-user-collateral voter))
)

(define-private (validate-parameter (name (string-ascii 32)) (value uint))
  (if (is-eq name "interest-rate")
    (and (>= value u1) (<= value u20))
    (if (is-eq name "collateral-ratio")
      (and (>= value u120) (<= value u200))
      (if (is-eq name "liquidation-threshold")
        (and (>= value u110) (<= value u150))
        false
      )
    )
  )
)

(define-public (create-proposal (parameter-name (string-ascii 32)) (new-value uint))
  (let ((proposer-power (get-voting-power tx-sender))
        (proposal-id (var-get proposal-nonce)))
    
    (asserts! (>= proposer-power PROPOSAL_THRESHOLD) ERR_NOT_AUTHORIZED)
    (asserts! (validate-parameter parameter-name new-value) ERR_INVALID_PARAMETER)
    
    (map-set proposals
      { proposal-id: proposal-id }
      {
        proposer: tx-sender,
        parameter-name: parameter-name,
        new-value: new-value,
        votes-for: u0,
        votes-against: u0,
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height VOTING_PERIOD_BLOCKS),
        execution-block: (+ stacks-block-height VOTING_PERIOD_BLOCKS TIME_LOCK_BLOCKS),
        is-executed: false,
        is-active: true
      }
    )
    
    (var-set proposal-nonce (+ proposal-id u1))
    (ok proposal-id)
  )
)

(define-public (vote (proposal-id uint) (support bool))
  (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
        (voter-power (get-voting-power tx-sender)))
    
    (asserts! (get is-active proposal) ERR_PROPOSAL_NOT_ACTIVE)
    (asserts! (<= stacks-block-height (get end-block proposal)) ERR_VOTING_PERIOD_ENDED)
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender })) ERR_ALREADY_VOTED)
    
    (map-set votes
      { proposal-id: proposal-id, voter: tx-sender }
      { vote: support, power: voter-power }
    )
    
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal 
        (if support
          { votes-for: (+ (get votes-for proposal) voter-power), votes-against: (get votes-against proposal) }
          { votes-for: (get votes-for proposal), votes-against: (+ (get votes-against proposal) voter-power) }
        )
      )
    )
    
    (ok voter-power)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND)))
    
    (asserts! (get is-active proposal) ERR_PROPOSAL_NOT_ACTIVE)
    (asserts! (not (get is-executed proposal)) ERR_PROPOSAL_NOT_ACTIVE)
    (asserts! (>= stacks-block-height (get execution-block proposal)) ERR_EXECUTION_TIME_NOT_REACHED)
    
    (let ((total-votes (+ (get votes-for proposal) (get votes-against proposal)))
          (quorum-threshold (/ (* (var-get total-voting-power) QUORUM_PERCENTAGE) u100)))
      
      (if (and (>= total-votes quorum-threshold) 
               (> (get votes-for proposal) (get votes-against proposal)))
        (begin
          (map-set proposals
            { proposal-id: proposal-id }
            (merge proposal { is-executed: true, is-active: false })
          )
          (ok true)
        )
        (begin
          (map-set proposals
            { proposal-id: proposal-id }
            (merge proposal { is-active: false })
          )
          (ok false)
        )
      )
    )
  )
)

(define-read-only (get-proposal (proposal-id uint))
  (ok (map-get? proposals { proposal-id: proposal-id }))
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (ok (map-get? votes { proposal-id: proposal-id, voter: voter }))
)
