import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas"]
  static values = { data: Array }

  connect() {
    this.drawChart()
  }

  drawChart() {
    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")
    const data = this.dataValue

    if (!data || data.length === 0) {
      ctx.font = "14px sans-serif"
      ctx.fillStyle = "#9ca3af"
      ctx.textAlign = "center"
      ctx.fillText("No data yet", canvas.width / 2, canvas.height / 2)
      return
    }

    const rect = canvas.parentElement.getBoundingClientRect()
    canvas.width = rect.width
    canvas.height = 200

    const padding = { top: 20, right: 20, bottom: 30, left: 50 }
    const chartWidth = canvas.width - padding.left - padding.right
    const chartHeight = canvas.height - padding.top - padding.bottom

    const times = data.map(d => new Date(d.t).getTime())
    const values = data.map(d => d.ms || 0)
    const maxMs = Math.max(...values) * 1.1 || 100

    ctx.strokeStyle = "#e5e7eb"
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(padding.left, padding.top)
    ctx.lineTo(padding.left, canvas.height - padding.bottom)
    ctx.lineTo(canvas.width - padding.right, canvas.height - padding.bottom)
    ctx.stroke()

    ctx.fillStyle = "#6b7280"
    ctx.font = "11px sans-serif"
    ctx.textAlign = "right"
    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (chartHeight * (4 - i) / 4)
      const label = Math.round(maxMs * i / 4)
      ctx.fillText(`${label}ms`, padding.left - 8, y + 4)
    }

    const minTime = Math.min(...times)
    const maxTime = Math.max(...times)
    const timeRange = maxTime - minTime || 1

    ctx.beginPath()
    ctx.strokeStyle = "#6366f1"
    ctx.lineWidth = 2
    data.forEach((d, i) => {
      const x = padding.left + ((times[i] - minTime) / timeRange) * chartWidth
      const y = padding.top + chartHeight - ((d.ms || 0) / maxMs) * chartHeight
      if (i === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    })
    ctx.stroke()

    data.forEach((d, i) => {
      if (!d.ok) {
        const x = padding.left + ((times[i] - minTime) / timeRange) * chartWidth
        const y = padding.top + chartHeight
        ctx.beginPath()
        ctx.fillStyle = "#ef4444"
        ctx.arc(x, y, 4, 0, Math.PI * 2)
        ctx.fill()
      }
    })
  }
}
