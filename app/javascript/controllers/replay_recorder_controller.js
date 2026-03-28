import { Controller } from "@hotwired/stimulus"

// Records the current browser session using rrweb (loaded via CDN script tag).
// Keeps ALL events in memory and sends the full recording on page leave.
// Also sends periodic snapshots every 30s so data isn't lost on crash.
//
// Limits (Sentry-style):
//   Max duration:       60 minutes — hard stop
//   Inactivity timeout: 15 minutes — stop if no user events
//   Mutation limit:     10,000     — stop to prevent bloated replays
export default class extends Controller {
  static values = {
    apiToken: String,
    flushInterval: { type: Number, default: 30000 },
    maxDuration: { type: Number, default: 3600000 },       // 60 min in ms
    inactivityTimeout: { type: Number, default: 900000 },  // 15 min in ms
    mutationLimit: { type: Number, default: 10000 },
  }

  connect() {
    this.waitForRrweb()
  }

  waitForRrweb(attempts = 0) {
    if (window.rrweb && window.rrweb.record) {
      this.startRecording()
    } else if (attempts < 50) {
      setTimeout(() => this.waitForRrweb(attempts + 1), 200)
    } else {
      console.warn("[ReplayRecorder] rrweb not loaded after 10s")
    }
  }

  startRecording() {
    this.replayId = this.generateUUID()
    this.sessionId = this.generateUUID()
    this.allEvents = []
    this.startedAt = new Date().toISOString()
    this.startTime = Date.now()
    this.lastSentCount = 0
    this.lastActivityAt = Date.now()
    this.mutationCount = 0
    this.stopped = false

    this.stopFn = window.rrweb.record({
      emit: (event) => {
        if (this.stopped) return

        // Track mutations (type 3 = IncrementalSnapshot, source 0 = Mutation)
        if (event.type === 3 && event.data && event.data.source === 0) {
          var adds = (event.data.adds && event.data.adds.length) || 0
          var removes = (event.data.removes && event.data.removes.length) || 0
          this.mutationCount += adds + removes
          if (this.mutationCount >= this.mutationLimitValue) {
            console.warn(`[ReplayRecorder] Mutation limit reached (${this.mutationCount}), stopping`)
            this.stopRecording("mutation_limit")
            return
          }
        }

        // Track user activity (mouse, keyboard, scroll, touch events)
        if (event.type === 3) {
          this.lastActivityAt = Date.now()
        }

        this.allEvents.push(event)
      },
      sampling: {
        mousemove: 50,
        mouseInteraction: true,
        scroll: 150,
        media: 800,
        input: "last",
      },
      blockClass: "rr-block",
      maskInputOptions: { password: true },
    })

    console.log("[ReplayRecorder] Recording started, replay:", this.replayId)

    // Periodic save — sends full event list as a checkpoint
    this.flushTimer = setInterval(() => this.save(), this.flushIntervalValue)

    // Check max duration and inactivity every 10s
    this.limitTimer = setInterval(() => this.checkLimits(), 10000)

    // Save on page leave
    this.boundSave = () => this.save(true)
    document.addEventListener("visibilitychange", this.boundSave)
    window.addEventListener("beforeunload", this.boundSave)
  }

  checkLimits() {
    if (this.stopped) return
    var elapsed = Date.now() - this.startTime
    var idle = Date.now() - this.lastActivityAt

    if (elapsed >= this.maxDurationValue) {
      console.log(`[ReplayRecorder] Max duration reached (${Math.round(elapsed / 60000)}min), stopping`)
      this.stopRecording("max_duration")
    } else if (idle >= this.inactivityTimeoutValue) {
      console.log(`[ReplayRecorder] Inactivity timeout (${Math.round(idle / 60000)}min idle), stopping`)
      this.stopRecording("inactivity")
    }
  }

  stopRecording(reason) {
    if (this.stopped) return
    this.stopped = true
    if (this.stopFn) this.stopFn()
    if (this.limitTimer) clearInterval(this.limitTimer)
    this.save(true)
    console.log("[ReplayRecorder] Recording stopped, reason:", reason)
  }

  disconnect() {
    if (this.stopFn) this.stopFn()
    if (this.flushTimer) clearInterval(this.flushTimer)
    if (this.limitTimer) clearInterval(this.limitTimer)
    if (this.boundSave) {
      document.removeEventListener("visibilitychange", this.boundSave)
      window.removeEventListener("beforeunload", this.boundSave)
    }
    this.stopped = true
    this.save(true)
  }

  save(sync = false) {
    if (!this.allEvents || this.allEvents.length < 2) return
    // Don't re-send if nothing new
    if (this.allEvents.length === this.lastSentCount) return
    this.lastSentCount = this.allEvents.length

    const duration = Date.now() - this.startTime

    const payload = {
      replay_id: this.replayId,
      session_id: this.sessionId,
      events: this.allEvents,
      started_at: this.startedAt,
      duration_ms: duration,
      segment_index: 0,
      url: window.location.href,
      user_agent: navigator.userAgent,
      viewport_width: window.innerWidth,
      viewport_height: window.innerHeight,
      environment: "production",
      sdk_version: "0.1.0",
      rrweb_version: "2.0.0-alpha.4",
    }

    const url = "/api/v1/replay_sessions"
    const headers = {
      "Content-Type": "application/json",
      "X-Project-Token": this.apiTokenValue,
    }
    const body = JSON.stringify(payload)

    console.log(`[ReplayRecorder] Saving ${this.allEvents.length} events (${(body.length / 1024).toFixed(1)}KB)`)

    if (sync) {
      try {
        fetch(url, { method: "POST", headers, body, keepalive: true })
      } catch (_) {}
    } else {
      fetch(url, { method: "POST", headers, body }).catch(() => {})
    }
  }

  generateUUID() {
    if (crypto.randomUUID) return crypto.randomUUID()
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0
      return (c === "x" ? r : (r & 0x3) | 0x8).toString(16)
    })
  }
}
