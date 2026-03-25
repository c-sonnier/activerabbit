import { Controller } from "@hotwired/stimulus"

// Records the current browser session using rrweb (loaded via CDN script tag).
// Keeps ALL events in memory and sends the full recording on page leave.
// Also sends periodic snapshots every 30s so data isn't lost on crash.
export default class extends Controller {
  static values = {
    apiToken: String,
    flushInterval: { type: Number, default: 30000 },
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

    this.stopFn = window.rrweb.record({
      emit: (event) => {
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

    // Save on page leave
    this.boundSave = () => this.save(true)
    document.addEventListener("visibilitychange", this.boundSave)
    window.addEventListener("beforeunload", this.boundSave)
  }

  disconnect() {
    if (this.stopFn) this.stopFn()
    if (this.flushTimer) clearInterval(this.flushTimer)
    if (this.boundSave) {
      document.removeEventListener("visibilitychange", this.boundSave)
      window.removeEventListener("beforeunload", this.boundSave)
    }
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
