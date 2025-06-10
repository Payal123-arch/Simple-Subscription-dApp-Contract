;; Simple Subscription dApp Contract
;; A basic subscription management system with recurring payments

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-subscription-not-found (err u104))
(define-constant err-subscription-expired (err u105))
(define-constant err-already-subscribed (err u106))

;; Data Variables
(define-data-var subscription-price uint u1000000) ;; 1 STX in microSTX
(define-data-var subscription-duration uint u2592000) ;; 30 days in seconds
(define-data-var total-subscribers uint u0)

;; Data Maps
(define-map subscriptions 
  principal 
  {
    start-time: uint,
    end-time: uint,
    is-active: bool,
    amount-paid: uint
  })

(define-map subscriber-payments principal uint)

;; Function 1: Subscribe to the service
(define-public (subscribe)
  (let (
    (subscriber tx-sender)
    (price (var-get subscription-price))
    (duration (var-get subscription-duration))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (end-time (+ current-time duration))
    (existing-subscription (map-get? subscriptions subscriber))
  )
    ;; Check if user already has an active subscription
    (asserts! (is-none existing-subscription) err-already-subscribed)
    
    ;; Check if user has sufficient STX balance
    (asserts! (>= (stx-get-balance subscriber) price) err-insufficient-balance)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? price subscriber (as-contract tx-sender)))
    
    ;; Create subscription record
    (map-set subscriptions subscriber {
      start-time: current-time,
      end-time: end-time,
      is-active: true,
      amount-paid: price
    })
    
    ;; Track total payment for subscriber
    (map-set subscriber-payments subscriber 
             (+ (default-to u0 (map-get? subscriber-payments subscriber)) price))
    
    ;; Increment total subscribers
    (var-set total-subscribers (+ (var-get total-subscribers) u1))
    
    (print {
      event: "subscription-created",
      subscriber: subscriber,
      amount: price,
      duration: duration,
      end-time: end-time
    })
    
    (ok {
      message: "Subscription created successfully",
      end-time: end-time,
      amount-paid: price
    })))

;; Function 2: Check subscription status
(define-read-only (check-subscription (subscriber principal))
  (let (
    (subscription-data (map-get? subscriptions subscriber))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
  )
    (match subscription-data
      subscription-info
        (let (
          (is-expired (> current-time (get end-time subscription-info)))
          (is-active (and (get is-active subscription-info) (not is-expired)))
        )
          (ok {
            subscriber: subscriber,
            is-active: is-active,
            is-expired: is-expired,
            start-time: (get start-time subscription-info),
            end-time: (get end-time subscription-info),
            amount-paid: (get amount-paid subscription-info),
            days-remaining: (if is-active 
                           (/ (- (get end-time subscription-info) current-time) u86400)
                           u0)
          }))
      (err err-subscription-not-found))))

;; Helper read-only functions
(define-read-only (get-subscription-price)
  (ok (var-get subscription-price)))

(define-read-only (get-subscription-duration)
  (ok (var-get subscription-duration)))

(define-read-only (get-total-subscribers)
  (ok (var-get total-subscribers)))

(define-read-only (get-contract-balance)
  (ok (stx-get-balance (as-contract tx-sender))))

;; Owner-only functions
(define-public (set-subscription-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-price u0) err-invalid-amount)
    (var-set subscription-price new-price)
    (ok true)))

(define-public (withdraw-funds (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= (stx-get-balance (as-contract tx-sender)) amount) err-insufficient-balance)
    (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
    (ok true)))