import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["entries", "toggleBtn", "indicator", "label", "pagination", "loader"]
  static values = { projectId: String }

  connect() {
    this.active = false
    this.consumer = null
    this.subscription = null
    this.loading = false
    this.nextPage = 2
    this.noMorePages = false
    this.scrollHandler = this.onScroll.bind(this)
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

    // Hide/show pagination when live tail toggles
    if (this.hasPaginationTarget) {
      this.paginationTarget.classList.toggle("hidden", active)
    }

    // Setup/teardown scroll-based loading
    if (active) {
      this.nextPage = 2
      this.noMorePages = false
      window.addEventListener("scroll", this.scrollHandler)
    } else {
      window.removeEventListener("scroll", this.scrollHandler)
      if (this.hasLoaderTarget) {
        this.loaderTarget.classList.add("hidden")
      }
    }
  }

  onScroll() {
    if (!this.active || this.loading || this.noMorePages) return

    const scrollBottom = window.innerHeight + window.scrollY
    const docHeight = document.documentElement.scrollHeight

    if (docHeight - scrollBottom < 200) {
      this.loadNextPage()
    }
  }

  async loadNextPage() {
    this.loading = true
    if (this.hasLoaderTarget) {
      this.loaderTarget.classList.remove("hidden")
    }

    try {
      const url = new URL(window.location.href)
      url.searchParams.set("page", this.nextPage)

      const response = await fetch(url.toString(), {
        headers: { "X-Requested-With": "XMLHttpRequest" }
      })

      if (!response.ok) {
        this.noMorePages = true
        return
      }

      const html = await response.text()
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, "text/html")
      const newRows = doc.querySelectorAll("#log-entries > tr")

      if (newRows.length === 0) {
        this.noMorePages = true
        return
      }

      newRows.forEach(row => {
        this.entriesTarget.appendChild(row.cloneNode(true))
      })

      this.nextPage++
    } catch (e) {
      this.noMorePages = true
    } finally {
      this.loading = false
      if (this.hasLoaderTarget) {
        this.loaderTarget.classList.add("hidden")
      }
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
    const traceHtml = data.trace_id ? `<span class="text-xs text-indigo-600 font-mono">${this.escapeHtml(data.trace_id.slice(0, 12))}</span>` : ""

    const html = `
      <tr class="hover:bg-gray-50 cursor-pointer bg-green-50/30 animate-fade-in">
        <td class="px-4 py-2">
          <div class="w-1.5 h-1.5 rounded-full ${dotColors[level] || "bg-gray-400"}"></div>
        </td>
        <td class="px-4 py-2 font-mono text-xs text-gray-500 whitespace-nowrap">${timestamp}</td>
        <td class="px-4 py-2">
          <span class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-medium ${levelColors[level] || "bg-gray-100 text-gray-700"}">
            ${level.toUpperCase()}
          </span>
        </td>
        <td class="px-4 py-2 font-mono text-xs text-gray-500 whitespace-nowrap">${this.escapeHtml(data.source)}</td>
        <td class="px-4 py-2 text-xs text-gray-900 font-mono max-w-md truncate">${this.escapeHtml(data.message)}</td>
        <td class="px-4 py-2 font-mono text-xs text-indigo-600 whitespace-nowrap">${traceHtml}</td>
      </tr>
    `

    this.entriesTarget.insertAdjacentHTML("afterbegin", html)

    // Remove the empty state if present
    const emptyState = this.entriesTarget.querySelector(".text-center")
    if (emptyState) emptyState.closest("tr")?.remove()

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
