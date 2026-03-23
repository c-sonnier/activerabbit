import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "statusBar", "tooltip", "barTooltip"]
  static values = { data: Array }

  connect() {
    this._onResize = () => this.draw()
    window.addEventListener("resize", this._onResize)
    this.draw()
    this._setupHover()
  }

  disconnect() {
    window.removeEventListener("resize", this._onResize)
    this.canvasTarget.removeEventListener("mousemove", this._mouseMoveHandler)
    this.canvasTarget.removeEventListener("mouseleave", this._mouseLeaveHandler)
  }

  draw() {
    this._drawChart()
    this._cacheImage()
    this.drawStatusBar()
  }

  _drawChart() {
    const canvas = this.canvasTarget
    const data = this.dataValue

    // Get width from canvas parent; ensure canvas doesn't inflate it
    canvas.style.width = "0px"
    const width = canvas.parentElement.clientWidth
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

    const pad = { top: 20, right: 20, bottom: 30, left: 55 }
    const cw = width - pad.left - pad.right
    const ch = height - pad.top - pad.bottom

    const times = data.map(d => new Date(d.t).getTime())
    const values = data.map(d => d.ms || 0)
    const maxMs = Math.ceil((Math.max(...values) * 1.15) / 50) * 50 || 100
    const minT = Math.min(...times)
    const range = (Math.max(...times) - minT) || 1

    const xFor = (i) => pad.left + ((times[i] - minT) / range) * cw
    const yFor = (ms) => pad.top + ch - (ms / maxMs) * ch

    // Grid
    ctx.strokeStyle = "#f3f4f6"
    ctx.lineWidth = 1
    for (let i = 0; i <= 4; i++) {
      const y = pad.top + (ch * (4 - i) / 4)
      ctx.beginPath()
      ctx.moveTo(pad.left, y)
      ctx.lineTo(width - pad.right, y)
      ctx.stroke()
    }

    // Y labels
    ctx.fillStyle = "#9ca3af"
    ctx.font = "11px -apple-system, BlinkMacSystemFont, sans-serif"
    ctx.textAlign = "right"
    for (let i = 0; i <= 4; i++) {
      const y = pad.top + (ch * (4 - i) / 4)
      ctx.fillText(`${Math.round(maxMs * i / 4)}ms`, pad.left - 8, y + 4)
    }

    // X labels
    ctx.textAlign = "center"
    const n = Math.min(6, data.length)
    for (let i = 0; i < n; i++) {
      const idx = Math.floor(i * (data.length - 1) / (n - 1 || 1))
      const t = new Date(data[idx].t)
      ctx.fillText(t.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }), xFor(idx), height - 8)
    }

    // Area fill
    ctx.beginPath()
    ctx.moveTo(xFor(0), yFor(values[0]))
    for (let i = 1; i < data.length; i++) ctx.lineTo(xFor(i), yFor(data[i].ms || 0))
    ctx.lineTo(xFor(data.length - 1), pad.top + ch)
    ctx.lineTo(xFor(0), pad.top + ch)
    ctx.closePath()
    const grad = ctx.createLinearGradient(0, pad.top, 0, pad.top + ch)
    grad.addColorStop(0, "rgba(99, 102, 241, 0.15)")
    grad.addColorStop(1, "rgba(99, 102, 241, 0.01)")
    ctx.fillStyle = grad
    ctx.fill()

    // Line
    ctx.beginPath()
    ctx.strokeStyle = "#6366f1"
    ctx.lineWidth = 2.5
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    for (let i = 0; i < data.length; i++) {
      if (i === 0) {
        ctx.moveTo(xFor(i), yFor(data[i].ms || 0))
      } else {
        ctx.lineTo(xFor(i), yFor(data[i].ms || 0))
      }
    }
    ctx.stroke()

    // Fail markers
    data.forEach((d, i) => {
      if (!d.ok) {
        const x = xFor(i), y = d.ms ? yFor(d.ms) : pad.top + ch
        ctx.beginPath()
        ctx.fillStyle = "#ef4444"
        ctx.arc(x, y, 4, 0, Math.PI * 2)
        ctx.fill()
        ctx.strokeStyle = "#fff"
        ctx.lineWidth = 1.5
        ctx.stroke()
      }
    })

    this._layout = { pad, cw, ch, maxMs, width, height, xFor, yFor, data, times }
  }

  _cacheImage() {
    // Save the clean chart so we can restore it on each hover without full redraw
    const canvas = this.canvasTarget
    this._imageData = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height)
  }

  _setupHover() {
    this._mouseMoveHandler = (e) => this._onHover(e)
    this._mouseLeaveHandler = () => this._clearHover()
    this.canvasTarget.addEventListener("mousemove", this._mouseMoveHandler)
    this.canvasTarget.addEventListener("mouseleave", this._mouseLeaveHandler)
    this.canvasTarget.style.cursor = "crosshair"
  }

  _onHover(e) {
    if (!this._layout || !this._imageData) return

    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")
    const rect = canvas.getBoundingClientRect()
    const mouseX = e.clientX - rect.left
    const { pad, ch, data, xFor, yFor, width, height } = this._layout
    const dpr = window.devicePixelRatio || 1

    // Find nearest point
    let nearest = 0, nearestDist = Infinity
    data.forEach((d, i) => {
      const dist = Math.abs(xFor(i) - mouseX)
      if (dist < nearestDist) { nearestDist = dist; nearest = i }
    })

    if (nearestDist > 40) { this._clearHover(); return }

    // Restore clean chart
    ctx.putImageData(this._imageData, 0, 0)
    // Re-apply scale for drawing hover elements
    ctx.save()
    ctx.scale(dpr, dpr)

    const d = data[nearest]
    const x = xFor(nearest)
    const y = d.ms ? yFor(d.ms) : pad.top + ch

    // Vertical dashed line
    ctx.beginPath()
    ctx.strokeStyle = "#d1d5db"
    ctx.lineWidth = 1
    ctx.setLineDash([4, 4])
    ctx.moveTo(x, pad.top)
    ctx.lineTo(x, pad.top + ch)
    ctx.stroke()
    ctx.setLineDash([])

    // Highlighted dot
    ctx.beginPath()
    ctx.fillStyle = d.ok ? "#6366f1" : "#ef4444"
    ctx.arc(x, y, 6, 0, Math.PI * 2)
    ctx.fill()
    ctx.strokeStyle = "#fff"
    ctx.lineWidth = 2
    ctx.stroke()

    ctx.restore()

    // Tooltip
    if (this.hasTooltipTarget) {
      const time = new Date(d.t)
      const tooltip = this.tooltipTarget
      tooltip.innerHTML = `
        <div class="text-xs font-medium ${d.ok ? "text-green-600" : "text-red-600"}">${d.ok ? "OK" : "FAIL"}${d.ms ? " — " + d.ms + "ms" : ""}</div>
        <div class="text-xs text-gray-500">${time.toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit" })}</div>
      `
      const tw = 140
      let left = x - tw / 2
      left = Math.max(4, Math.min(left, width - tw - 4))
      const top = Math.min(y + 14, height - 44)
      tooltip.style.left = left + "px"
      tooltip.style.top = top + "px"
      tooltip.style.display = "block"
    }
  }

  _clearHover() {
    if (this._imageData) {
      this.canvasTarget.getContext("2d").putImageData(this._imageData, 0, 0)
    }
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

    bar.style.display = "flex"
    bar.style.gap = "1px"

    const total = data.length
    const slotCount = Math.min(90, total)
    const fragment = document.createDocumentFragment()

    for (let i = 0; i < slotCount; i++) {
      const start = Math.floor(i * total / slotCount)
      const end = Math.floor((i + 1) * total / slotCount)
      const bucket = data.slice(start, end)

      const dot = document.createElement("div")
      dot.style.cssText = "flex:1;height:28px;border-radius:2px;cursor:pointer;transition:opacity 0.15s;"

      if (bucket.length === 0) {
        dot.style.background = "#e5e7eb"
        fragment.appendChild(dot)
        continue
      }

      const allOk = bucket.every(d => d.ok)
      const anyFail = bucket.some(d => !d.ok)
      const anyOk = bucket.some(d => d.ok)

      if (allOk) {
        dot.style.background = "#22c55e"
      } else if (anyFail && anyOk) {
        dot.style.background = "#f59e0b"
      } else {
        dot.style.background = "#ef4444"
      }

      const t0 = new Date(bucket[0].t)
      const t1 = new Date(bucket[bucket.length - 1].t)
      const avgMs = Math.round(bucket.filter(d => d.ms).reduce((s, d) => s + d.ms, 0) / (bucket.filter(d => d.ms).length || 1))
      const okCount = bucket.filter(d => d.ok).length
      const statusLabel = allOk ? "Operational" : (anyOk ? "Degraded" : "Down")
      const dotColor = allOk ? "#22c55e" : (anyOk ? "#f59e0b" : "#ef4444")

      const html = `
        <div style="display:flex;align-items:center;gap:6px;margin-bottom:4px;">
          <span style="width:8px;height:8px;border-radius:50%;background:${dotColor};display:inline-block;"></span>
          <strong>${statusLabel}</strong>
        </div>
        <div style="color:#d1d5db;">${t0.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} – ${t1.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</div>
        <div style="margin-top:3px;">${okCount}/${bucket.length} checks OK · avg ${avgMs}ms</div>
      `

      dot.onmouseenter = () => {
        dot.style.opacity = "0.7"
        if (this.hasBarTooltipTarget) {
          const tip = this.barTooltipTarget
          tip.innerHTML = html
          const dotRect = dot.getBoundingClientRect()
          const barRect = bar.getBoundingClientRect()
          let left = dotRect.left - barRect.left + dotRect.width / 2 - 75
          left = Math.max(0, Math.min(left, barRect.width - 160))
          tip.style.left = left + "px"
          tip.style.display = "block"
        }
      }
      dot.onmouseleave = () => {
        dot.style.opacity = "1"
        if (this.hasBarTooltipTarget) {
          this.barTooltipTarget.style.display = "none"
        }
      }

      fragment.appendChild(dot)
    }
    bar.appendChild(fragment)
  }
}
