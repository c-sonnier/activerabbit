import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "statusBar", "tooltip"]
  static values = { data: Array }

  connect() {
    this._onResize = () => this.draw()
    window.addEventListener("resize", this._onResize)
    this.draw()
  }

  disconnect() {
    window.removeEventListener("resize", this._onResize)
    if (this._mouseMoveHandler) {
      this.canvasTarget.removeEventListener("mousemove", this._mouseMoveHandler)
      this.canvasTarget.removeEventListener("mouseleave", this._mouseLeaveHandler)
    }
  }

  draw() {
    this.drawResponseChart()
    this.drawStatusBar()
  }

  drawResponseChart() {
    const canvas = this.canvasTarget
    const container = canvas.parentElement
    const data = this.dataValue

    // Size canvas to container
    const width = container.clientWidth
    const height = 200
    const dpr = window.devicePixelRatio || 1
    canvas.width = width * dpr
    canvas.height = height * dpr
    canvas.style.width = width + "px"
    canvas.style.height = height + "px"

    const ctx = canvas.getContext("2d")
    ctx.scale(dpr, dpr)

    if (!data || data.length === 0) {
      ctx.font = "14px -apple-system, BlinkMacSystemFont, sans-serif"
      ctx.fillStyle = "#9ca3af"
      ctx.textAlign = "center"
      ctx.fillText("No data yet", width / 2, height / 2)
      return
    }

    const padding = { top: 20, right: 20, bottom: 30, left: 55 }
    const chartW = width - padding.left - padding.right
    const chartH = height - padding.top - padding.bottom

    const times = data.map(d => new Date(d.t).getTime())
    const values = data.map(d => d.ms || 0)
    const maxMs = Math.ceil((Math.max(...values) * 1.15) / 50) * 50 || 100
    const minTime = Math.min(...times)
    const maxTime = Math.max(...times)
    const timeRange = maxTime - minTime || 1

    const xFor = (i) => padding.left + ((times[i] - minTime) / timeRange) * chartW
    const yFor = (ms) => padding.top + chartH - (ms / maxMs) * chartH

    // Grid lines
    ctx.strokeStyle = "#f3f4f6"
    ctx.lineWidth = 1
    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (chartH * (4 - i) / 4)
      ctx.beginPath()
      ctx.moveTo(padding.left, y)
      ctx.lineTo(width - padding.right, y)
      ctx.stroke()
    }

    // Y-axis labels
    ctx.fillStyle = "#9ca3af"
    ctx.font = "11px -apple-system, BlinkMacSystemFont, sans-serif"
    ctx.textAlign = "right"
    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (chartH * (4 - i) / 4)
      const label = Math.round(maxMs * i / 4)
      ctx.fillText(`${label}ms`, padding.left - 8, y + 4)
    }

    // X-axis time labels
    ctx.textAlign = "center"
    ctx.fillStyle = "#9ca3af"
    const labelCount = Math.min(6, data.length)
    for (let i = 0; i < labelCount; i++) {
      const idx = Math.floor(i * (data.length - 1) / (labelCount - 1 || 1))
      const x = xFor(idx)
      const time = new Date(data[idx].t)
      ctx.fillText(time.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }), x, height - 8)
    }

    // Area fill under line
    ctx.beginPath()
    ctx.moveTo(xFor(0), yFor(values[0]))
    data.forEach((d, i) => {
      if (i > 0) ctx.lineTo(xFor(i), yFor(d.ms || 0))
    })
    ctx.lineTo(xFor(data.length - 1), padding.top + chartH)
    ctx.lineTo(xFor(0), padding.top + chartH)
    ctx.closePath()
    const gradient = ctx.createLinearGradient(0, padding.top, 0, padding.top + chartH)
    gradient.addColorStop(0, "rgba(99, 102, 241, 0.15)")
    gradient.addColorStop(1, "rgba(99, 102, 241, 0.01)")
    ctx.fillStyle = gradient
    ctx.fill()

    // Response time line
    ctx.beginPath()
    ctx.strokeStyle = "#6366f1"
    ctx.lineWidth = 2.5
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    data.forEach((d, i) => {
      const x = xFor(i)
      const y = yFor(d.ms || 0)
      if (i === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    })
    ctx.stroke()

    // Failed check markers
    data.forEach((d, i) => {
      if (!d.ok) {
        const x = xFor(i)
        const y = d.ms ? yFor(d.ms) : padding.top + chartH
        ctx.beginPath()
        ctx.fillStyle = "#ef4444"
        ctx.arc(x, y, 4, 0, Math.PI * 2)
        ctx.fill()
        ctx.strokeStyle = "#ffffff"
        ctx.lineWidth = 1.5
        ctx.stroke()
      }
    })

    // Store layout for hover
    this._chartLayout = { padding, chartW, chartH, maxMs, minTime, timeRange, times, data, width, height, xFor, yFor }

    // Hover interaction
    if (!this._mouseMoveHandler) {
      this._mouseMoveHandler = (e) => this.handleHover(e)
      this._mouseLeaveHandler = () => this.hideTooltip()
      canvas.addEventListener("mousemove", this._mouseMoveHandler)
      canvas.addEventListener("mouseleave", this._mouseLeaveHandler)
      canvas.style.cursor = "crosshair"
    }
  }

  handleHover(e) {
    if (!this._chartLayout || !this.hasTooltipTarget) return

    const rect = this.canvasTarget.getBoundingClientRect()
    const mouseX = e.clientX - rect.left
    const { padding, data, xFor, yFor } = this._chartLayout

    // Find nearest data point
    let nearest = 0
    let nearestDist = Infinity
    data.forEach((d, i) => {
      const dist = Math.abs(xFor(i) - mouseX)
      if (dist < nearestDist) {
        nearestDist = dist
        nearest = i
      }
    })

    if (nearestDist > 30) {
      this.hideTooltip()
      return
    }

    const d = data[nearest]
    const time = new Date(d.t)
    const tooltip = this.tooltipTarget

    tooltip.innerHTML = `
      <div class="text-xs font-medium ${d.ok ? "text-green-600" : "text-red-600"}">${d.ok ? "OK" : "FAIL"}</div>
      <div class="text-xs text-gray-900 font-semibold">${d.ms ? d.ms + "ms" : "—"}</div>
      <div class="text-xs text-gray-500">${time.toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit" })}</div>
    `

    const x = xFor(nearest)
    const tooltipWidth = 130
    let left = x - tooltipWidth / 2
    left = Math.max(4, Math.min(left, rect.width - tooltipWidth - 4))

    tooltip.style.left = left + "px"
    tooltip.style.top = "4px"
    tooltip.style.display = "block"

    // Draw hover line
    this.drawResponseChart()
    const canvas = this.canvasTarget
    const dpr = window.devicePixelRatio || 1
    const ctx = canvas.getContext("2d")
    ctx.scale(dpr, dpr)

    ctx.beginPath()
    ctx.strokeStyle = "#d1d5db"
    ctx.lineWidth = 1
    ctx.setLineDash([4, 4])
    ctx.moveTo(x, this._chartLayout.padding.top)
    ctx.lineTo(x, this._chartLayout.padding.top + this._chartLayout.chartH)
    ctx.stroke()
    ctx.setLineDash([])

    // Dot on the line
    const y = d.ms ? yFor(d.ms) : this._chartLayout.padding.top + this._chartLayout.chartH
    ctx.beginPath()
    ctx.fillStyle = d.ok ? "#6366f1" : "#ef4444"
    ctx.arc(x, y, 5, 0, Math.PI * 2)
    ctx.fill()
    ctx.strokeStyle = "#ffffff"
    ctx.lineWidth = 2
    ctx.stroke()
  }

  hideTooltip() {
    if (this.hasTooltipTarget) {
      this.tooltipTarget.style.display = "none"
    }
  }

  drawStatusBar() {
    if (!this.hasStatusBarTarget) return

    const bar = this.statusBarTarget
    const data = this.dataValue

    bar.innerHTML = ""

    if (!data || data.length === 0) {
      bar.innerHTML = '<div class="text-xs text-gray-400 text-center py-2">No checks yet</div>'
      return
    }

    // Group checks into time buckets (one per visual slot)
    const barWidth = bar.clientWidth || 600
    const slotCount = Math.min(data.length, Math.floor(barWidth / 4))
    const bucketSize = Math.ceil(data.length / slotCount)

    const fragment = document.createDocumentFragment()

    for (let i = 0; i < slotCount; i++) {
      const start = i * bucketSize
      const end = Math.min(start + bucketSize, data.length)
      const bucket = data.slice(start, end)

      const allOk = bucket.every(d => d.ok)
      const anyFail = bucket.some(d => !d.ok)

      const dot = document.createElement("div")
      dot.className = "inline-block rounded-sm cursor-pointer transition-opacity hover:opacity-80"
      dot.style.width = "3px"
      dot.style.height = "24px"
      dot.style.marginRight = "1px"

      if (allOk) {
        dot.style.backgroundColor = "#22c55e"
      } else if (anyFail && bucket.some(d => d.ok)) {
        dot.style.backgroundColor = "#f59e0b"
      } else {
        dot.style.backgroundColor = "#ef4444"
      }

      // Tooltip on hover
      const firstTime = new Date(bucket[0].t)
      const lastTime = new Date(bucket[bucket.length - 1].t)
      const avgMs = Math.round(bucket.filter(d => d.ms).reduce((s, d) => s + d.ms, 0) / (bucket.filter(d => d.ms).length || 1))
      const okCount = bucket.filter(d => d.ok).length

      dot.title = `${firstTime.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} — ${okCount}/${bucket.length} OK, avg ${avgMs}ms`

      fragment.appendChild(dot)
    }

    bar.appendChild(fragment)
  }
}
