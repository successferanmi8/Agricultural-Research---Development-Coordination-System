;; Farmer Participation Contract
;; Manages farmer registration, participation tracking, feedback collection, and rewards

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-FARMER-NOT-FOUND (err u301))
(define-constant ERR-INVALID-INPUT (err u302))
(define-constant ERR-FARMER-ALREADY-EXISTS (err u303))
(define-constant ERR-INSUFFICIENT-REWARDS (err u304))

;; Data Variables
(define-data-var total-farmers uint u0)
(define-data-var total-rewards-distributed uint u0)

;; Data Maps
(define-map farmers
  { farmer: principal }
  {
    name: (string-ascii 100),
    location: (string-ascii 100),
    farm-size: uint,
    crop-types: (string-ascii 200),
    experience-years: uint,
    registration-block: uint,
    active: bool,
    reputation-score: uint
  }
)

(define-map farmer-participation
  { farmer: principal, activity-id: uint }
  {
    activity-type: (string-ascii 50),
    project-id: uint,
    trial-id: (optional uint),
    participation-date: uint,
    contribution-level: uint,
    reward-earned: uint,
    feedback-provided: bool
  }
)

(define-map farmer-feedback
  { farmer: principal, feedback-id: uint }
  {
    target-type: (string-ascii 50),
    target-id: uint,
    rating: uint,
    comments: (string-ascii 500),
    submitted-at: uint,
    verified: bool
  }
)

(define-map farmer-rewards
  { farmer: principal }
  {
    total-earned: uint,
    total-claimed: uint,
    pending-rewards: uint,
    last-claim-block: uint
  }
)

(define-map participation-stats
  { farmer: principal }
  {
    total-activities: uint,
    completed-activities: uint,
    average-rating: uint,
    total-feedback-count: uint
  }
)

;; Read-only functions
(define-read-only (get-farmer (farmer principal))
  (map-get? farmers { farmer: farmer })
)

(define-read-only (get-farmer-participation (farmer principal) (activity-id uint))
  (map-get? farmer-participation { farmer: farmer, activity-id: activity-id })
)

(define-read-only (get-farmer-feedback (farmer principal) (feedback-id uint))
  (map-get? farmer-feedback { farmer: farmer, feedback-id: feedback-id })
)

(define-read-only (get-farmer-rewards (farmer principal))
  (default-to { total-earned: u0, total-claimed: u0, pending-rewards: u0, last-claim-block: u0 }
    (map-get? farmer-rewards { farmer: farmer }))
)

(define-read-only (get-participation-stats (farmer principal))
  (default-to { total-activities: u0, completed-activities: u0, average-rating: u0, total-feedback-count: u0 }
    (map-get? participation-stats { farmer: farmer }))
)

(define-read-only (get-total-farmers)
  (var-get total-farmers)
)

(define-read-only (get-total-rewards-distributed)
  (var-get total-rewards-distributed)
)

;; Public functions
(define-public (register-farmer
  (name (string-ascii 100))
  (location (string-ascii 100))
  (farm-size uint)
  (crop-types (string-ascii 200))
  (experience-years uint))
  (begin
    (asserts! (is-none (get-farmer tx-sender)) ERR-FARMER-ALREADY-EXISTS)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len location) u0) ERR-INVALID-INPUT)
    (asserts! (> farm-size u0) ERR-INVALID-INPUT)

    (map-set farmers
      { farmer: tx-sender }
      {
        name: name,
        location: location,
        farm-size: farm-size,
        crop-types: crop-types,
        experience-years: experience-years,
        registration-block: block-height,
        active: true,
        reputation-score: u100
      }
    )

    ;; Initialize rewards and stats
    (map-set farmer-rewards
      { farmer: tx-sender }
      {
        total-earned: u0,
        total-claimed: u0,
        pending-rewards: u0,
        last-claim-block: block-height
      }
    )

    (map-set participation-stats
      { farmer: tx-sender }
      {
        total-activities: u0,
        completed-activities: u0,
        average-rating: u0,
        total-feedback-count: u0
      }
    )

    (var-set total-farmers (+ (var-get total-farmers) u1))

    (ok true)
  )
)

(define-public (record-participation
  (farmer principal)
  (activity-id uint)
  (activity-type (string-ascii 50))
  (project-id uint)
  (trial-id (optional uint))
  (contribution-level uint)
  (reward-amount uint))
  (let
    (
      (farmer-data (unwrap! (get-farmer farmer) ERR-FARMER-NOT-FOUND))
      (current-rewards (get-farmer-rewards farmer))
      (current-stats (get-participation-stats farmer))
    )
    (asserts! (get active farmer-data) ERR-NOT-AUTHORIZED)
    (asserts! (> (len activity-type) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= contribution-level u1) (<= contribution-level u5)) ERR-INVALID-INPUT)

    ;; Record participation
    (map-set farmer-participation
      { farmer: farmer, activity-id: activity-id }
      {
        activity-type: activity-type,
        project-id: project-id,
        trial-id: trial-id,
        participation-date: block-height,
        contribution-level: contribution-level,
        reward-earned: reward-amount,
        feedback-provided: false
      }
    )

    ;; Update rewards
    (map-set farmer-rewards
      { farmer: farmer }
      {
        total-earned: (+ (get total-earned current-rewards) reward-amount),
        total-claimed: (get total-claimed current-rewards),
        pending-rewards: (+ (get pending-rewards current-rewards) reward-amount),
        last-claim-block: (get last-claim-block current-rewards)
      }
    )

    ;; Update participation stats
    (map-set participation-stats
      { farmer: farmer }
      {
        total-activities: (+ (get total-activities current-stats) u1),
        completed-activities: (get completed-activities current-stats),
        average-rating: (get average-rating current-stats),
        total-feedback-count: (get total-feedback-count current-stats)
      }
    )

    (ok true)
  )
)

(define-public (submit-feedback
  (feedback-id uint)
  (target-type (string-ascii 50))
  (target-id uint)
  (rating uint)
  (comments (string-ascii 500)))
  (let
    (
      (farmer-data (unwrap! (get-farmer tx-sender) ERR-FARMER-NOT-FOUND))
      (current-stats (get-participation-stats tx-sender))
    )
    (asserts! (get active farmer-data) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-INPUT)
    (asserts! (> (len target-type) u0) ERR-INVALID-INPUT)

    (map-set farmer-feedback
      { farmer: tx-sender, feedback-id: feedback-id }
      {
        target-type: target-type,
        target-id: target-id,
        rating: rating,
        comments: comments,
        submitted-at: block-height,
        verified: false
      }
    )

    ;; Update feedback stats
    (let
      (
        (new-feedback-count (+ (get total-feedback-count current-stats) u1))
        (new-average (/ (+ (* (get average-rating current-stats) (get total-feedback-count current-stats)) rating) new-feedback-count))
      )
      (map-set participation-stats
        { farmer: tx-sender }
        {
          total-activities: (get total-activities current-stats),
          completed-activities: (get completed-activities current-stats),
          average-rating: new-average,
          total-feedback-count: new-feedback-count
        }
      )
    )

    (ok true)
  )
)

(define-public (claim-rewards)
  (let
    (
      (farmer-data (unwrap! (get-farmer tx-sender) ERR-FARMER-NOT-FOUND))
      (current-rewards (get-farmer-rewards tx-sender))
    )
    (asserts! (get active farmer-data) ERR-NOT-AUTHORIZED)
    (asserts! (> (get pending-rewards current-rewards) u0) ERR-INSUFFICIENT-REWARDS)

    (let
      (
        (claim-amount (get pending-rewards current-rewards))
      )
      (map-set farmer-rewards
        { farmer: tx-sender }
        {
          total-earned: (get total-earned current-rewards),
          total-claimed: (+ (get total-claimed current-rewards) claim-amount),
          pending-rewards: u0,
          last-claim-block: block-height
        }
      )

      (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) claim-amount))

      (ok claim-amount)
    )
  )
)

(define-public (verify-feedback (farmer principal) (feedback-id uint))
  (let
    (
      (feedback (unwrap! (get-farmer-feedback farmer feedback-id) ERR-FARMER-NOT-FOUND))
    )
    ;; Only contract owner can verify feedback for now
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (get verified feedback)) ERR-INVALID-INPUT)

    (map-set farmer-feedback
      { farmer: farmer, feedback-id: feedback-id }
      (merge feedback { verified: true })
    )

    (ok true)
  )
)

(define-public (update-reputation-score (farmer principal) (new-score uint))
  (let
    (
      (farmer-data (unwrap! (get-farmer farmer) ERR-FARMER-NOT-FOUND))
    )
    ;; Only contract owner can update reputation scores
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-score u1000) ERR-INVALID-INPUT)

    (map-set farmers
      { farmer: farmer }
      (merge farmer-data { reputation-score: new-score })
    )

    (ok true)
  )
)

(define-public (complete-activity (farmer principal) (activity-id uint))
  (let
    (
      (participation (unwrap! (get-farmer-participation farmer activity-id) ERR-FARMER-NOT-FOUND))
      (current-stats (get-participation-stats farmer))
    )
    ;; Only contract owner or the farmer can mark activity as complete
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender farmer)) ERR-NOT-AUTHORIZED)

    (map-set participation-stats
      { farmer: farmer }
      {
        total-activities: (get total-activities current-stats),
        completed-activities: (+ (get completed-activities current-stats) u1),
        average-rating: (get average-rating current-stats),
        total-feedback-count: (get total-feedback-count current-stats)
      }
    )

    (ok true)
  )
)

(define-public (deactivate-farmer (farmer principal))
  (let
    (
      (farmer-data (unwrap! (get-farmer farmer) ERR-FARMER-NOT-FOUND))
    )
    ;; Only contract owner can deactivate farmers
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set farmers
      { farmer: farmer }
      (merge farmer-data { active: false })
    )

    (ok true)
  )
)
