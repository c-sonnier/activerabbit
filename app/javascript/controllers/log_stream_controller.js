import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["entries", "toggleBtn", "indicator", "label"]
  static values = { projectId: String }

  connect() {
    this.active = false
    this.consumer = null
    this.subscription = null
  }

  disconnect() {
    this.stop()
  }

  toggle() {
    if (this.active) {
      this.stop()
    } else {
      this.start()
    }
  }

  start() {
    if (!this.projectIdValue) return

    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "LogStreamChannel", project_id: this.projectIdValue },
      {
        received: (data) => this.appendEntry(data),
        connected: () => this.setActive(true),
        disconnected: () => this.setActive(false)
      }
    )
  }

  stop() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
    this.setActive(false)
  }

  setActive(active) {
    this.active = active

    if (this.hasToggleBtnTarget) {
      this.toggleBtnTarget.classList.toggle("border-green-500", active)
      this.toggleBtnTarget.classList.toggle("bg-green-50", active)
    }
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.classList.toggle("bg-green-500", active)
      this.indicatorTarget.classList.toggle("bg-gray-400", !active)
      if (active) {
        this.indicatorTarget.classList.add("animate-pulse")
      } else {
        this.indicatorTarget.classList.remove("animate-pulse")
      }
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = active ? "Live" : "Live Tail"
    }
  }

  appendEntry(data) {
    if (!this.hasEntriesTarget) return

    const levelColors = {
      trace: "bg-gray-100 text-gray-700",
      debug: "bg-gray-100 text-gray-700",
      info: "bg-blue-100 text-blue-700",
      warn: "bg-yellow-100 text-yellow-800",
      error: "bg-red-100 text-red-800",
      fatal: "bg-red-200 text-red-900"
    }

    const dotColors = {
      trace: "bg-gray-400",
      debug: "bg-gray-400",
      info: "bg-blue-400",
      warn: "bg-yellow-400",
      error: "bg-red-400",
      fatal: "bg-red-600"
    }

    const level = data.level || "info"
    const timestamp = data.occurred_at ? new Date(data.occurred_at).toISOString().replace("T", " ").slice(0, 23) : ""

    const html = `
      <div class="group px-4 py-3 hover:bg-gray-50 transition-colors bg-green-50/30 animate-fade-in">
        <div class="flex items-start gap-3">
          <div class="flex-shrink-0 mt-1.5">
            <div class="w-2 h-2 rounded-full ${dotColors[level] || "bg-gray-400"}"></div>
          </div>
          <div class="flex-shrink-0 w-44 text-xs text-gray-500 font-mono mt-0.5">${timestamp}</div>
          <div class="flex-shrink-0">
            <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${levelColors[level] || "bg-gray-100 text-gray-700"}">
              ${level.toUpperCase()}
            </span>
          </div>
          ${data.source ? `<div class="flex-shrink-0 text-xs text-gray-500 font-mono">${this.escapeHtml(data.source)}</div>` : ""}
          <div class="flex-1 min-w-0">
            <p class="text-sm text-gray-900 truncate font-mono">${this.escapeHtml(data.message)}</p>
          </div>
          ${data.trace_id ? `<div class="flex-shrink-0"><span class="text-xs text-indigo-600 font-mono">${this.escapeHtml(data.trace_id.slice(0, 12))}</span></div>` : ""}
        </div>
      </div>
    `

    this.entriesTarget.insertAdjacentHTML("afterbegin", html)

    // Remove the empty state if present
    const emptyState = this.entriesTarget.querySelector(".text-center")
    if (emptyState) emptyState.remove()

    // Cap at 500 entries to prevent memory issues
    while (this.entriesTarget.children.length > 500) {
      this.entriesTarget.removeChild(this.entriesTarget.lastChild)
    }
  }

  escapeHtml(str) {
    if (!str) return ""
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
